-- =====================================================================
-- F-Mate V4: 게시물, 동영상(숏폼·하이라이트), 팔로우, 차단, 좋아요, 댓글, 저장, 해시태그
-- 동영상 업로드: 앱 → (서버가 발급한 presigned URL) → 오브젝트 스토리지로 직접 업로드.
--   API 서버는 파일을 중계하지 않는다. 업로드 완료 통지 후 인코딩 작업(HLS + 썸네일)을 큐에 넣고
--   결과를 콜백으로 받아 READY 로 전환한다. 재생은 CDN의 HLS URL.
-- =====================================================================

CREATE TABLE follows (
  follower_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followee_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'ACCEPTED' CHECK (status IN ('PENDING','ACCEPTED')),  -- 비공개 계정은 PENDING
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, followee_id),
  CHECK (follower_id <> followee_id)
);
CREATE INDEX ix_follows_followee ON follows (followee_id, created_at DESC) WHERE status = 'ACCEPTED';
CREATE INDEX ix_follows_follower ON follows (follower_id, created_at DESC) WHERE status = 'ACCEPTED';

CREATE TABLE blocks (
  blocker_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
CREATE INDEX ix_blocks_blocked ON blocks (blocked_id);

-- 차단 시 양방향 팔로우 해제
CREATE OR REPLACE FUNCTION on_block_remove_follows() RETURNS trigger AS $$
BEGIN
  DELETE FROM follows
   WHERE (follower_id = NEW.blocker_id AND followee_id = NEW.blocked_id)
      OR (follower_id = NEW.blocked_id AND followee_id = NEW.blocker_id);
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_block_unfollow AFTER INSERT ON blocks
  FOR EACH ROW EXECUTE FUNCTION on_block_remove_follows();

-- 차단 관계 여부 (양방향)
CREATE OR REPLACE FUNCTION is_blocked_between(a BIGINT, b BIGINT) RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM blocks
                  WHERE (blocker_id = a AND blocked_id = b) OR (blocker_id = b AND blocked_id = a));
$$ LANGUAGE sql STABLE;

-- 차단 관계에서는 팔로우 생성 불가
CREATE OR REPLACE FUNCTION forbid_follow_if_blocked() RETURNS trigger AS $$
BEGIN
  IF is_blocked_between(NEW.follower_id, NEW.followee_id) THEN
    RAISE EXCEPTION 'BLOCKED' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_follow_block_check BEFORE INSERT ON follows
  FOR EACH ROW EXECUTE FUNCTION forbid_follow_if_blocked();

CREATE TABLE posts (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  author_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind            TEXT NOT NULL CHECK (kind IN ('PHOTO','VIDEO','TEXT')),
  caption         VARCHAR(2200),
  visibility      TEXT NOT NULL DEFAULT 'PUBLIC' CHECK (visibility IN ('PUBLIC','FOLLOWERS','PRIVATE')),
  is_highlight    BOOLEAN NOT NULL DEFAULT false,      -- 프로필 하이라이트 탭
  venue_id        BIGINT REFERENCES futsal_venues(id) ON DELETE SET NULL,  -- 구장 태그
  status          TEXT NOT NULL DEFAULT 'ACTIVE'
                  CHECK (status IN ('PENDING_MEDIA','ACTIVE','HIDDEN_BY_MODERATION','DELETED')),
  like_count      INT NOT NULL DEFAULT 0 CHECK (like_count >= 0),
  comment_count   INT NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);
CREATE INDEX ix_posts_author ON posts (author_id, created_at DESC) WHERE status = 'ACTIVE';
CREATE INDEX ix_posts_latest ON posts (created_at DESC) WHERE status = 'ACTIVE' AND visibility = 'PUBLIC';
CREATE INDEX ix_posts_video_feed ON posts (created_at DESC)
  WHERE status = 'ACTIVE' AND visibility = 'PUBLIC' AND kind = 'VIDEO';
CREATE TRIGGER trg_posts_updated BEFORE UPDATE ON posts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE post_media (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  post_id         BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  object_key      TEXT NOT NULL,
  content_type    TEXT NOT NULL CHECK (content_type IN ('image/jpeg','image/png','image/webp','image/heic')),
  width           INT, height INT,
  sort_order      SMALLINT NOT NULL DEFAULT 0
);
CREATE INDEX ix_post_media ON post_media (post_id, sort_order);

-- 동영상 업로드·인코딩 상태 머신
--   UPLOAD_PENDING → UPLOADED → PROCESSING → READY | FAILED
--   (어느 상태에서든) → DELETED
CREATE TABLE videos (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_id        BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id         BIGINT UNIQUE REFERENCES posts(id) ON DELETE SET NULL,
  status          TEXT NOT NULL DEFAULT 'UPLOAD_PENDING' CHECK (status IN (
                    'UPLOAD_PENDING','UPLOADED','PROCESSING','READY','FAILED','DELETED')),
  source_object_key TEXT NOT NULL UNIQUE,
  content_type    TEXT NOT NULL CHECK (content_type IN ('video/mp4','video/quicktime')),
  declared_size_bytes BIGINT NOT NULL CHECK (declared_size_bytes BETWEEN 1 AND 524288000),  -- 500MB
  actual_size_bytes   BIGINT,
  duration_ms     INT CHECK (duration_ms BETWEEN 1000 AND 90000),     -- 1~90초 (인코더가 측정)
  width           INT, height INT,
  hls_manifest_key TEXT,
  thumbnail_key   TEXT,
  multipart_upload_id TEXT,
  upload_expires_at TIMESTAMPTZ NOT NULL,
  failure_reason  VARCHAR(300),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (status <> 'READY' OR (hls_manifest_key IS NOT NULL AND thumbnail_key IS NOT NULL
                               AND duration_ms IS NOT NULL))
);
CREATE INDEX ix_videos_owner ON videos (owner_id, created_at DESC);
CREATE INDEX ix_videos_stale ON videos (upload_expires_at) WHERE status = 'UPLOAD_PENDING';
CREATE TRIGGER trg_videos_updated BEFORE UPDATE ON videos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION enforce_video_transition() RETURNS trigger AS $$
DECLARE ok BOOLEAN;
BEGIN
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;
  ok := NEW.status = 'DELETED' OR CASE OLD.status
    WHEN 'UPLOAD_PENDING' THEN NEW.status IN ('UPLOADED','FAILED')
    WHEN 'UPLOADED'       THEN NEW.status IN ('PROCESSING','FAILED')
    WHEN 'PROCESSING'     THEN NEW.status IN ('READY','FAILED')
    WHEN 'FAILED'         THEN NEW.status IN ('PROCESSING')   -- 인코딩 재시도
    ELSE false END;
  IF OLD.status = 'DELETED' THEN ok := false; END IF;
  IF NOT ok THEN
    RAISE EXCEPTION 'illegal video transition % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_video_transition BEFORE UPDATE ON videos
  FOR EACH ROW EXECUTE FUNCTION enforce_video_transition();

-- 영상이 READY 가 되면 연결된 게시물을 공개(ACTIVE)로 전환
CREATE OR REPLACE FUNCTION on_video_ready() RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'READY' AND OLD.status <> 'READY' AND NEW.post_id IS NOT NULL THEN
    UPDATE posts SET status = 'ACTIVE' WHERE id = NEW.post_id AND status = 'PENDING_MEDIA';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_video_ready AFTER UPDATE ON videos
  FOR EACH ROW EXECUTE FUNCTION on_video_ready();

CREATE TABLE likes (
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id         BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);
CREATE INDEX ix_likes_user ON likes (user_id, created_at DESC);

CREATE TABLE comments (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  post_id         BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  author_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  parent_id       BIGINT REFERENCES comments(id) ON DELETE CASCADE,  -- 1단계 답글
  body            VARCHAR(1000) NOT NULL CHECK (length(btrim(body)) > 0),
  status          TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','HIDDEN_BY_MODERATION','DELETED')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_comments_post ON comments (post_id, created_at) WHERE status = 'ACTIVE';

CREATE TABLE saved_posts (
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id         BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);

CREATE TABLE hashtags (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tag             CITEXT NOT NULL UNIQUE CHECK (tag ~ '^[A-Za-z0-9가-힣_]{1,50}$')
);
CREATE TABLE post_hashtags (
  post_id         BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  hashtag_id      BIGINT NOT NULL REFERENCES hashtags(id) ON DELETE CASCADE,
  PRIMARY KEY (hashtag_id, post_id)
);

-- 카운터 유지 (좋아요 / 댓글)
CREATE OR REPLACE FUNCTION maintain_post_counters() RETURNS trigger AS $$
BEGIN
  IF TG_TABLE_NAME = 'likes' THEN
    IF TG_OP = 'INSERT' THEN UPDATE posts SET like_count = like_count + 1 WHERE id = NEW.post_id;
    ELSE UPDATE posts SET like_count = like_count - 1 WHERE id = OLD.post_id; END IF;
  ELSIF TG_TABLE_NAME = 'comments' THEN
    IF TG_OP = 'INSERT' AND NEW.status = 'ACTIVE' THEN
      UPDATE posts SET comment_count = comment_count + 1 WHERE id = NEW.post_id;
    ELSIF TG_OP = 'UPDATE' AND OLD.status = 'ACTIVE' AND NEW.status <> 'ACTIVE' THEN
      UPDATE posts SET comment_count = comment_count - 1 WHERE id = NEW.post_id;
    ELSIF TG_OP = 'UPDATE' AND OLD.status <> 'ACTIVE' AND NEW.status = 'ACTIVE' THEN
      UPDATE posts SET comment_count = comment_count + 1 WHERE id = NEW.post_id;
    END IF;
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_likes_counter AFTER INSERT OR DELETE ON likes
  FOR EACH ROW EXECUTE FUNCTION maintain_post_counters();
CREATE TRIGGER trg_comments_counter AFTER INSERT OR UPDATE OF status ON comments
  FOR EACH ROW EXECUTE FUNCTION maintain_post_counters();

-- 게시물 열람 권한 (차단·공개범위·비공개 계정·삭제 상태를 한 곳에서 판단)
CREATE OR REPLACE FUNCTION can_view_post(p_viewer BIGINT, p_post_id BIGINT) RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM posts p JOIN user_profiles up ON up.user_id = p.author_id
                          JOIN users au ON au.id = p.author_id
     WHERE p.id = p_post_id
       AND au.status = 'ACTIVE'
       AND (p.status = 'ACTIVE' OR (p.author_id = p_viewer AND p.status = 'PENDING_MEDIA'))
       AND (p.author_id = p_viewer OR (
             NOT is_blocked_between(p_viewer, p.author_id)
             AND p.visibility <> 'PRIVATE'
             AND ((p.visibility = 'PUBLIC' AND NOT up.is_private)
                  OR EXISTS (SELECT 1 FROM follows f
                              WHERE f.follower_id = p_viewer AND f.followee_id = p.author_id
                                AND f.status = 'ACCEPTED')))));
$$ LANGUAGE sql STABLE;
