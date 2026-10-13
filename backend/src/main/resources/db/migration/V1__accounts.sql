-- =====================================================================
-- F-Mate V1: 계정, 인증, 프로필
-- 원칙
--  * 사용자 데이터의 단일 소유자는 Spring Boot + PostgreSQL 이다.
--    Firebase는 FCM(푸시) 전송 채널로만 쓰고 사용자/인증 데이터를 두지 않는다.
--  * 비밀번호는 bcrypt/argon2 해시만 저장한다 (애플리케이션 계층에서 해시).
--  * 토큰류(리프레시, 이메일 인증, 비밀번호 재설정)는 원문이 아닌 SHA-256 해시만 저장한다.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- updated_at 자동 갱신
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TABLE users (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email           CITEXT,                       -- 탈퇴 시 NULL 처리 (개인정보 삭제)
  password_hash   TEXT,                         -- 소셜 전용 계정은 NULL
  email_verified_at TIMESTAMPTZ,
  role            TEXT NOT NULL DEFAULT 'USER'
                  CHECK (role IN ('USER','VENUE_OPERATOR','MODERATOR','ADMIN')),
  status          TEXT NOT NULL DEFAULT 'ACTIVE'
                  CHECK (status IN ('ACTIVE','SUSPENDED','DELETED')),
  suspended_until TIMESTAMPTZ,
  token_version   INT NOT NULL DEFAULT 0,       -- 증가 시 발급된 모든 액세스 토큰 무효화
  failed_login_count INT NOT NULL DEFAULT 0,
  locked_until    TIMESTAMPTZ,                  -- 로그인 무차별 대입 방지
  deleted_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT users_deleted_consistency CHECK (
    (status = 'DELETED') = (deleted_at IS NOT NULL)
  ),
  CONSTRAINT users_deleted_has_no_email CHECK (status <> 'DELETED' OR email IS NULL)
);
-- 활성 계정 사이에서만 이메일 유일 (탈퇴 후 같은 이메일로 재가입 가능)
CREATE UNIQUE INDEX ux_users_email ON users (email) WHERE email IS NOT NULL;
CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE user_profiles (
  user_id         BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  nickname        CITEXT NOT NULL,
  bio             VARCHAR(300),
  avatar_object_key TEXT,                       -- 스토리지 키 (URL은 응답 시 CDN 기준으로 조합)
  region_code     VARCHAR(10),                  -- 행정구역 코드 (시군구)
  preferred_position TEXT CHECK (preferred_position IN ('PIVO','ALA','FIXO','GOLEIRO','ANY')),
  is_private      BOOLEAN NOT NULL DEFAULT false,  -- 비공개 계정: 승인된 팔로워만 게시물 열람
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT nickname_format CHECK (nickname ~ '^[A-Za-z0-9가-힣_.]{2,20}$')
);
CREATE UNIQUE INDEX ux_profiles_nickname ON user_profiles (nickname);
CREATE INDEX ix_profiles_nickname_trgm ON user_profiles USING gin ((nickname::text) gin_trgm_ops);
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 소셜 로그인 연결 (카카오 / 구글 / 애플). 공급자 토큰은 서버가 공급자에 직접 검증한 뒤 연결한다.
CREATE TABLE social_accounts (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider        TEXT NOT NULL CHECK (provider IN ('KAKAO','GOOGLE','APPLE')),
  provider_user_id TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_user_id),
  UNIQUE (user_id, provider)
);

-- 리프레시 토큰: 회전(rotation) + 재사용 탐지.
-- 같은 family 에서 이미 회전된 토큰이 다시 제출되면 family 전체를 폐기한다.
CREATE TABLE refresh_tokens (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  family_id       UUID NOT NULL,
  token_hash      BYTEA NOT NULL UNIQUE,        -- SHA-256(원문)
  device_label    VARCHAR(100),
  issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ NOT NULL,
  rotated_at      TIMESTAMPTZ,                  -- 새 토큰으로 교체된 시각
  revoked_at      TIMESTAMPTZ,
  revoke_reason   TEXT CHECK (revoke_reason IN ('LOGOUT','REUSE_DETECTED','PASSWORD_CHANGED','ACCOUNT_DELETED','ADMIN'))
);
CREATE INDEX ix_refresh_user ON refresh_tokens (user_id) WHERE revoked_at IS NULL;
CREATE INDEX ix_refresh_family ON refresh_tokens (family_id);

-- 이메일 인증 / 비밀번호 재설정 일회용 토큰
CREATE TABLE one_time_tokens (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purpose         TEXT NOT NULL CHECK (purpose IN ('EMAIL_VERIFY','PASSWORD_RESET')),
  token_hash      BYTEA NOT NULL UNIQUE,
  expires_at      TIMESTAMPTZ NOT NULL,
  used_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_ott_user_purpose ON one_time_tokens (user_id, purpose) WHERE used_at IS NULL;

-- 약관 동의 이력 (개인정보 처리방침, 이용약관, 위치정보 이용약관, 마케팅)
CREATE TABLE consents (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  consent_type    TEXT NOT NULL CHECK (consent_type IN ('TERMS','PRIVACY','LOCATION','MARKETING','AGE_14')),
  version         VARCHAR(20) NOT NULL,
  agreed          BOOLEAN NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_consents_user ON consents (user_id, consent_type, created_at DESC);

-- FCM 기기 토큰 (Firebase 는 전송만 담당)
CREATE TABLE device_tokens (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token       TEXT NOT NULL UNIQUE,
  platform        TEXT NOT NULL CHECK (platform IN ('ANDROID','IOS')),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_device_tokens_user ON device_tokens (user_id);

-- 멱등성 키 (예약 생성, 결제 승인, 환불 요청, 게시물 생성 등 POST 요청)
CREATE TABLE idempotency_keys (
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  idem_key        VARCHAR(80) NOT NULL,
  endpoint        VARCHAR(120) NOT NULL,
  request_hash    BYTEA NOT NULL,               -- 같은 키 + 다른 본문이면 422
  response_status INT,
  response_body   JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, endpoint, idem_key)
);
CREATE INDEX ix_idem_created ON idempotency_keys (created_at);
