-- =====================================================================
-- F-Mate V5: 1:1 채팅, 알림, 신고, 제재, 관리자 감사 로그
-- =====================================================================

-- 1:1 채팅방: 두 사용자 쌍당 하나 (user_low < user_high 로 정규화)
CREATE TABLE chats (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_low        BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_high       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_message_id BIGINT,
  last_message_at TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (user_low < user_high),
  UNIQUE (user_low, user_high)
);
CREATE INDEX ix_chats_low ON chats (user_low, last_message_at DESC NULLS LAST);
CREATE INDEX ix_chats_high ON chats (user_high, last_message_at DESC NULLS LAST);

CREATE TABLE chat_members (
  chat_id         BIGINT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_read_message_id BIGINT NOT NULL DEFAULT 0,   -- 읽음 상태
  muted           BOOLEAN NOT NULL DEFAULT false,
  hidden_at       TIMESTAMPTZ,                       -- 목록에서 나가기 (상대 메시지 오면 다시 보임)
  PRIMARY KEY (chat_id, user_id)
);

CREATE TABLE messages (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  chat_id         BIGINT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  sender_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_message_id UUID NOT NULL,                   -- 재연결·재전송 시 중복 저장 방지
  body            VARCHAR(2000) NOT NULL CHECK (length(btrim(body)) > 0),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,
  UNIQUE (sender_id, client_message_id)
);
CREATE INDEX ix_messages_chat ON messages (chat_id, id DESC);

-- 메시지 전송 규칙: 채팅 참여자만, 차단 관계면 거부. 방 정보 갱신.
CREATE OR REPLACE FUNCTION on_message_insert() RETURNS trigger AS $$
DECLARE c chats%ROWTYPE; other BIGINT;
BEGIN
  SELECT * INTO c FROM chats WHERE id = NEW.chat_id FOR UPDATE;
  IF NEW.sender_id NOT IN (c.user_low, c.user_high) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'check_violation';
  END IF;
  other := CASE WHEN NEW.sender_id = c.user_low THEN c.user_high ELSE c.user_low END;
  IF is_blocked_between(NEW.sender_id, other) THEN
    RAISE EXCEPTION 'BLOCKED' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_message_rules BEFORE INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION on_message_insert();

CREATE OR REPLACE FUNCTION after_message_insert() RETURNS trigger AS $$
BEGIN
  UPDATE chats SET last_message_id = NEW.id, last_message_at = NEW.created_at WHERE id = NEW.chat_id;
  UPDATE chat_members SET hidden_at = NULL WHERE chat_id = NEW.chat_id;
  UPDATE chat_members SET last_read_message_id = NEW.id
   WHERE chat_id = NEW.chat_id AND user_id = NEW.sender_id;
  RETURN NULL;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_message_after AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION after_message_insert();

-- 채팅방 열기 (없으면 생성, 있으면 기존 방) — 동시 호출에도 방 1개
CREATE OR REPLACE FUNCTION fn_open_chat(p_me BIGINT, p_other BIGINT) RETURNS BIGINT AS $$
DECLARE lo BIGINT := least(p_me, p_other); hi BIGINT := greatest(p_me, p_other); cid BIGINT;
BEGIN
  IF p_me = p_other THEN RAISE EXCEPTION 'INVALID_TARGET'; END IF;
  IF is_blocked_between(p_me, p_other) THEN RAISE EXCEPTION 'BLOCKED'; END IF;
  INSERT INTO chats (user_low, user_high) VALUES (lo, hi)
    ON CONFLICT (user_low, user_high) DO NOTHING RETURNING id INTO cid;
  IF cid IS NULL THEN
    SELECT id INTO cid FROM chats WHERE user_low = lo AND user_high = hi;
  ELSE
    INSERT INTO chat_members (chat_id, user_id) VALUES (cid, lo), (cid, hi);
  END IF;
  RETURN cid;
END $$ LANGUAGE plpgsql;

-- 알림 (인앱 목록 + FCM 발송 기록)
CREATE TABLE notifications (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type            TEXT NOT NULL CHECK (type IN (
                    'RESERVATION_CONFIRMED','RESERVATION_CANCELED','RESERVATION_EXPIRED',
                    'REFUND_COMPLETED','REFUND_FAILED','RESERVATION_REMINDER',
                    'FOLLOW','FOLLOW_REQUEST','LIKE','COMMENT','MENTION','MESSAGE',
                    'VIDEO_READY','VIDEO_FAILED','CONTENT_ACTIONED','SYSTEM')),
  actor_id        BIGINT REFERENCES users(id) ON DELETE SET NULL,
  target_type     TEXT CHECK (target_type IN ('RESERVATION','POST','COMMENT','USER','CHAT','VIDEO')),
  target_id       BIGINT,
  data            JSONB NOT NULL DEFAULT '{}',
  read_at         TIMESTAMPTZ,
  push_status     TEXT NOT NULL DEFAULT 'PENDING' CHECK (push_status IN ('PENDING','SENT','SKIPPED','FAILED')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_notifications_user ON notifications (user_id, id DESC);
CREATE INDEX ix_notifications_unread ON notifications (user_id) WHERE read_at IS NULL;
CREATE INDEX ix_notifications_push ON notifications (created_at) WHERE push_status = 'PENDING';

CREATE TABLE notification_settings (
  user_id         BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  reservation     BOOLEAN NOT NULL DEFAULT true,
  social          BOOLEAN NOT NULL DEFAULT true,
  chat            BOOLEAN NOT NULL DEFAULT true,
  marketing       BOOLEAN NOT NULL DEFAULT false
);

-- 신고 (게시물·댓글·사용자·영상·메시지, 저작권 침해 포함)
CREATE TABLE reports (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reporter_id     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  target_type     TEXT NOT NULL CHECK (target_type IN ('POST','COMMENT','USER','MESSAGE','VENUE')),
  target_id       BIGINT NOT NULL,
  reason          TEXT NOT NULL CHECK (reason IN (
                    'SPAM','HARASSMENT','HATE','SEXUAL','VIOLENCE','ILLEGAL','COPYRIGHT',
                    'IMPERSONATION','FALSE_VENUE_INFO','OTHER')),
  detail          VARCHAR(1000),
  status          TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','REVIEWING','ACTIONED','DISMISSED')),
  handled_by      BIGINT REFERENCES users(id),
  handled_at      TIMESTAMPTZ,
  resolution_note VARCHAR(1000),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- 같은 사람이 같은 대상을 처리 대기 중에 중복 신고하지 못함
CREATE UNIQUE INDEX ux_reports_open ON reports (reporter_id, target_type, target_id)
  WHERE status IN ('OPEN','REVIEWING');
CREATE INDEX ix_reports_queue ON reports (status, created_at);
CREATE INDEX ix_reports_target ON reports (target_type, target_id);

-- 사용자 제재
CREATE TABLE user_sanctions (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind            TEXT NOT NULL CHECK (kind IN ('WARNING','SUSPENSION','PERMANENT_BAN')),
  reason          VARCHAR(500) NOT NULL,
  report_id       BIGINT REFERENCES reports(id),
  starts_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at         TIMESTAMPTZ,
  created_by      BIGINT NOT NULL REFERENCES users(id),
  revoked_at      TIMESTAMPTZ,
  CHECK (kind <> 'SUSPENSION' OR ends_at IS NOT NULL)
);
CREATE INDEX ix_sanctions_user ON user_sanctions (user_id, starts_at DESC);

-- 관리자 작업 감사 로그: 추가만 가능 (수정·삭제 불가)
CREATE TABLE admin_audit_logs (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id        BIGINT NOT NULL REFERENCES users(id),
  actor_role      TEXT NOT NULL,
  action          VARCHAR(60) NOT NULL,          -- VENUE_VERIFY, USER_SUSPEND, REFUND_FORCE, REPORT_RESOLVE ...
  target_type     VARCHAR(30) NOT NULL,
  target_id       BIGINT,
  before_state    JSONB,
  after_state     JSONB,
  reason          VARCHAR(500),
  ip_address      INET,
  request_id      VARCHAR(64),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_admin_audit_actor ON admin_audit_logs (actor_id, created_at DESC);
CREATE INDEX ix_admin_audit_target ON admin_audit_logs (target_type, target_id);

CREATE OR REPLACE FUNCTION forbid_audit_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'admin_audit_logs is append-only' USING ERRCODE = 'insufficient_privilege';
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_admin_audit_immutable BEFORE UPDATE OR DELETE ON admin_audit_logs
  FOR EACH ROW EXECUTE FUNCTION forbid_audit_mutation();

-- ---------------------------------------------------------------------
-- 회원 탈퇴: 개인정보 즉시 삭제/익명화, 법정 보존 대상(결제·예약 기록)은 사용자 식별정보 없이 유지
--   * 전자상거래법상 대금결제·계약 기록 보존 의무가 있어 payments/reservations 행은 남긴다.
--     (보존 기간·범위는 법률 검토 후 확정 — docs/03 참고)
--   * 프로필·게시물·댓글·좋아요·팔로우·기기토큰·소셜연결·토큰은 삭제.
--   * 확정된 미래 예약이 있으면 탈퇴 불가 (먼저 취소·환불 처리).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_delete_account(p_user_id BIGINT) RETURNS VOID AS $$
BEGIN
  PERFORM 1 FROM users WHERE id = p_user_id AND status <> 'DELETED' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  IF EXISTS (SELECT 1 FROM reservations
              WHERE user_id = p_user_id AND status IN ('PENDING_PAYMENT','CONFIRMED')
                AND upper(period) > now()) THEN
    RAISE EXCEPTION 'HAS_ACTIVE_RESERVATIONS';
  END IF;
  IF EXISTS (SELECT 1 FROM refunds f JOIN reservations r ON r.id = f.reservation_id
              WHERE r.user_id = p_user_id AND f.status = 'REQUESTED') THEN
    RAISE EXCEPTION 'HAS_PENDING_REFUNDS';
  END IF;

  DELETE FROM posts           WHERE author_id = p_user_id;   -- media, likes, comments CASCADE
  DELETE FROM comments        WHERE author_id = p_user_id;
  DELETE FROM likes           WHERE user_id = p_user_id;
  DELETE FROM saved_posts     WHERE user_id = p_user_id;
  DELETE FROM follows         WHERE follower_id = p_user_id OR followee_id = p_user_id;
  DELETE FROM blocks          WHERE blocker_id = p_user_id OR blocked_id = p_user_id;
  UPDATE videos SET status = 'DELETED' WHERE owner_id = p_user_id AND status <> 'DELETED';
  DELETE FROM device_tokens   WHERE user_id = p_user_id;
  DELETE FROM social_accounts WHERE user_id = p_user_id;
  DELETE FROM one_time_tokens WHERE user_id = p_user_id;
  DELETE FROM notifications   WHERE user_id = p_user_id;
  UPDATE refresh_tokens SET revoked_at = now(), revoke_reason = 'ACCOUNT_DELETED'
   WHERE user_id = p_user_id AND revoked_at IS NULL;
  UPDATE messages SET body = '(삭제된 메시지)', deleted_at = now()
   WHERE sender_id = p_user_id AND deleted_at IS NULL;
  DELETE FROM user_profiles   WHERE user_id = p_user_id;
  DELETE FROM venue_operators WHERE user_id = p_user_id;

  UPDATE users SET email = NULL, password_hash = NULL, status = 'DELETED', deleted_at = now(),
         token_version = token_version + 1
   WHERE id = p_user_id;
  -- 스토리지 원본 파일(영상·이미지) 삭제는 애플리케이션이 videos.status='DELETED' 기준 비동기 작업으로 수행
END $$ LANGUAGE plpgsql;
