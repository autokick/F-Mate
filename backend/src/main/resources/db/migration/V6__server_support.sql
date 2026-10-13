-- =====================================================================
-- F-Mate V6: 서버 구현을 위한 보강
--  * 이메일 인증·비밀번호 재설정을 6자리 코드 방식으로 (앱 딥링크 설정 없이 동작)
--    → 코드 해시는 사용자 간에 같을 수 있으므로 전역 유일 제약 제거, 시도 횟수 제한 추가
--  * 토스 결제용 고객 키(customerKey) — 사용자 식별자를 외부에 노출하지 않기 위한 무작위 값
--  * 구장 입점 서류, 반려 사유
--  * 서버 오류 기록(관리자 조회용)
--  * 영상 인코딩 재시도 횟수
--  * 이용 종료 예약 자동 완료 처리
-- =====================================================================

ALTER TABLE one_time_tokens DROP CONSTRAINT IF EXISTS one_time_tokens_token_hash_key;
ALTER TABLE one_time_tokens ADD COLUMN attempt_count INT NOT NULL DEFAULT 0;

ALTER TABLE users ADD COLUMN payment_customer_key UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE users ADD CONSTRAINT users_payment_customer_key_key UNIQUE (payment_customer_key);
ALTER TABLE users ADD COLUMN last_login_at TIMESTAMPTZ;

ALTER TABLE futsal_venues ADD COLUMN rejection_reason VARCHAR(500);

CREATE TABLE venue_documents (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  venue_id        BIGINT NOT NULL REFERENCES futsal_venues(id) ON DELETE CASCADE,
  kind            TEXT NOT NULL CHECK (kind IN ('BUSINESS_REGISTRATION','FACILITY_PHOTO','OTHER')),
  object_key      TEXT NOT NULL,
  uploaded_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_venue_documents ON venue_documents (venue_id);

ALTER TABLE videos ADD COLUMN encode_attempts INT NOT NULL DEFAULT 0;

-- 서버 오류 기록: 개인정보·비밀값을 제외한 요약만 저장
CREATE TABLE app_error_logs (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id      VARCHAR(64),
  method          VARCHAR(10),
  path            VARCHAR(300),
  user_id         BIGINT,
  error_class     VARCHAR(200) NOT NULL,
  message         VARCHAR(1000),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_app_error_logs ON app_error_logs (created_at DESC);

-- 이용 시간이 끝난 확정 예약을 COMPLETED 로 (1시간 유예: 노쇼 처리 시간)
CREATE OR REPLACE FUNCTION fn_complete_past_reservations() RETURNS INT AS $$
DECLARE n INT;
BEGIN
  UPDATE reservations SET status = 'COMPLETED'
   WHERE status = 'CONFIRMED' AND upper(period) < now() - interval '1 hour';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$ LANGUAGE plpgsql;

-- 업로드가 끝나지 않고 만료된 영상 정리 대상 표시
CREATE OR REPLACE FUNCTION fn_fail_stale_uploads() RETURNS INT AS $$
DECLARE n INT;
BEGIN
  UPDATE videos SET status = 'FAILED', failure_reason = 'upload expired'
   WHERE status = 'UPLOAD_PENDING' AND upload_expires_at < now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$ LANGUAGE plpgsql;

-- 기간 정지가 끝난 계정 복구
CREATE OR REPLACE FUNCTION fn_lift_expired_suspensions() RETURNS INT AS $$
DECLARE n INT;
BEGIN
  UPDATE users SET status = 'ACTIVE', suspended_until = NULL
   WHERE status = 'SUSPENDED' AND suspended_until IS NOT NULL AND suspended_until < now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$ LANGUAGE plpgsql;

-- 슬롯 변경 보호: 활성 예약이 걸린 슬롯은 닫거나 요금을 바꿀 수 없다
CREATE OR REPLACE FUNCTION protect_booked_slots() RETURNS trigger AS $$
BEGIN
  IF (NEW.status IS DISTINCT FROM OLD.status OR NEW.price IS DISTINCT FROM OLD.price
      OR NEW.period IS DISTINCT FROM OLD.period)
     AND EXISTS (SELECT 1 FROM reservations r
                  WHERE r.court_id = OLD.court_id AND r.period && OLD.period
                    AND r.status IN ('PENDING_PAYMENT','CONFIRMED')) THEN
    RAISE EXCEPTION 'SLOT_HAS_RESERVATION' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_protect_booked_slots BEFORE UPDATE ON time_slots
  FOR EACH ROW EXECUTE FUNCTION protect_booked_slots();

CREATE OR REPLACE FUNCTION protect_booked_slots_delete() RETURNS trigger AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM reservations r
              WHERE r.court_id = OLD.court_id AND r.period && OLD.period
                AND r.status IN ('PENDING_PAYMENT','CONFIRMED')) THEN
    RAISE EXCEPTION 'SLOT_HAS_RESERVATION' USING ERRCODE = 'check_violation';
  END IF;
  RETURN OLD;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_protect_booked_slots_delete BEFORE DELETE ON time_slots
  FOR EACH ROW EXECUTE FUNCTION protect_booked_slots_delete();
