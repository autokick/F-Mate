-- =====================================================================
-- F-Mate V3: 결제(토스페이먼츠), 환불, 웹훅, 예약·결제 흐름 함수
-- 흐름 (토스페이먼츠 결제위젯 기준)
--   1) POST /reservations            → fn_create_reservation_hold   (슬롯 선점, 10분)
--   2) POST /payments (주문 생성)      → payments READY, 서버가 금액·orderId 결정
--   3) 앱이 결제위젯으로 인증 → successUrl 로 paymentKey, orderId, amount 수신
--   4) POST /payments/confirm         → fn_payment_confirm_begin (금액 검증·IN_PROGRESS)
--                                       → 토스 승인 API 호출
--                                       → fn_payment_confirm_succeeded / _failed
--   5) 승인 응답이 유실되면 IN_PROGRESS 로 남고, 웹훅 또는 정산 배치가
--      토스 조회 API로 실제 상태를 확인해 4)의 마무리 함수를 호출한다.
-- 카드번호 등 결제수단 원본 정보는 저장하지 않는다 (토스가 보관, 우리는 결제키·영수증 URL만).
-- =====================================================================

CREATE TABLE payments (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reservation_id  BIGINT NOT NULL REFERENCES reservations(id),
  user_id         BIGINT NOT NULL REFERENCES users(id),
  provider        TEXT NOT NULL DEFAULT 'TOSS' CHECK (provider IN ('TOSS')),
  mode            TEXT NOT NULL CHECK (mode IN ('TEST','LIVE')),   -- 테스트/실결제 명확 구분
  order_id        VARCHAR(64) NOT NULL UNIQUE,                     -- 우리가 발급
  payment_key     VARCHAR(200) UNIQUE,                             -- 토스가 발급
  amount          INTEGER NOT NULL CHECK (amount > 0),             -- 결제 요청 금액 (= 예약 금액)
  approved_amount INTEGER CHECK (approved_amount >= 0),
  balance_amount  INTEGER CHECK (balance_amount >= 0),             -- 남은 환불 가능 금액
  status          TEXT NOT NULL DEFAULT 'READY' CHECK (status IN (
                    'READY','IN_PROGRESS','DONE','ABORTED','EXPIRED','PARTIAL_CANCELED','CANCELED')),
  method          VARCHAR(30),
  receipt_url     TEXT,
  webhook_secret  VARCHAR(64),                                     -- 토스 Payment.secret (웹훅 검증용)
  failure_code    VARCHAR(80),
  failure_message VARCHAR(300),
  approved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (status NOT IN ('DONE','PARTIAL_CANCELED','CANCELED')
         OR (approved_amount IS NOT NULL AND balance_amount IS NOT NULL AND payment_key IS NOT NULL))
);
-- 한 예약에 "돈이 실제로 움직였거나 움직이는 중인" 결제는 최대 1건 → 이중 결제 차단
CREATE UNIQUE INDEX ux_payments_one_captured_per_reservation ON payments (reservation_id)
  WHERE status IN ('IN_PROGRESS','DONE','PARTIAL_CANCELED','CANCELED');
CREATE INDEX ix_payments_user ON payments (user_id, created_at DESC);
CREATE INDEX ix_payments_inprogress ON payments (updated_at) WHERE status = 'IN_PROGRESS';
CREATE TRIGGER trg_payments_updated BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 결제 상태 머신
--   READY       → IN_PROGRESS | ABORTED | EXPIRED
--   IN_PROGRESS → DONE | ABORTED
--   DONE        → PARTIAL_CANCELED | CANCELED
--   PARTIAL_CANCELED → PARTIAL_CANCELED | CANCELED
CREATE OR REPLACE FUNCTION enforce_payment_rules() RETURNS trigger AS $$
DECLARE
  r reservations%ROWTYPE;
  ok BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO r FROM reservations WHERE id = NEW.reservation_id;
    IF NEW.status <> 'READY' THEN
      RAISE EXCEPTION 'payment must start as READY' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.amount <> r.total_amount THEN
      RAISE EXCEPTION 'payment amount % does not match reservation amount %', NEW.amount, r.total_amount
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.user_id <> r.user_id THEN
      RAISE EXCEPTION 'payment user does not own reservation' USING ERRCODE = 'check_violation';
    END IF;
    IF r.status <> 'PENDING_PAYMENT' THEN
      RAISE EXCEPTION 'INVALID_STATE: reservation % is %', r.id, r.status USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.amount <> OLD.amount OR NEW.reservation_id <> OLD.reservation_id OR NEW.mode <> OLD.mode
     OR NEW.order_id <> OLD.order_id THEN
    RAISE EXCEPTION 'payment core fields are immutable' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.payment_key IS NOT NULL AND NEW.payment_key IS DISTINCT FROM OLD.payment_key THEN
    RAISE EXCEPTION 'payment_key cannot change once set' USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.status = OLD.status AND NEW.status <> 'PARTIAL_CANCELED' THEN
    RETURN NEW;
  END IF;
  ok := CASE OLD.status
    WHEN 'READY'            THEN NEW.status IN ('IN_PROGRESS','ABORTED','EXPIRED')
    WHEN 'IN_PROGRESS'      THEN NEW.status IN ('DONE','ABORTED')
    WHEN 'DONE'             THEN NEW.status IN ('PARTIAL_CANCELED','CANCELED')
    WHEN 'PARTIAL_CANCELED' THEN NEW.status IN ('PARTIAL_CANCELED','CANCELED')
    ELSE false
  END;
  IF NOT ok THEN
    RAISE EXCEPTION 'illegal payment transition % -> %', OLD.status, NEW.status
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payments_rules BEFORE INSERT OR UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION enforce_payment_rules();

-- 예약 확정은 승인 완료(DONE) 결제가 있을 때만 가능
CREATE OR REPLACE FUNCTION require_paid_for_confirm() RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'CONFIRMED' AND OLD.status <> 'CONFIRMED' THEN
    IF NOT EXISTS (SELECT 1 FROM payments p
                   WHERE p.reservation_id = NEW.id AND p.status = 'DONE'
                     AND p.approved_amount = NEW.total_amount) THEN
      RAISE EXCEPTION 'cannot confirm reservation % without a DONE payment of the full amount', NEW.id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_reservation_requires_payment BEFORE UPDATE ON reservations
  FOR EACH ROW EXECUTE FUNCTION require_paid_for_confirm();

CREATE TABLE refunds (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id      BIGINT NOT NULL REFERENCES payments(id),
  reservation_id  BIGINT NOT NULL REFERENCES reservations(id),
  amount          INTEGER NOT NULL CHECK (amount > 0),
  reason          VARCHAR(200) NOT NULL,
  status          TEXT NOT NULL DEFAULT 'REQUESTED' CHECK (status IN ('REQUESTED','SUCCEEDED','FAILED')),
  idempotency_key UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),  -- 토스 취소 API 헤더로 전송
  provider_transaction_key VARCHAR(200),
  requested_by    TEXT NOT NULL CHECK (requested_by IN ('USER','OPERATOR','ADMIN','SYSTEM')),
  requested_by_user BIGINT REFERENCES users(id),
  failure_code    VARCHAR(80),
  failure_message VARCHAR(300),
  attempt_count   INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at    TIMESTAMPTZ
);
CREATE INDEX ix_refunds_payment ON refunds (payment_id);
CREATE INDEX ix_refunds_pending ON refunds (created_at) WHERE status = 'REQUESTED';

-- 환불 합계는 승인 금액을 넘을 수 없다 (결제 행을 잠가 동시 환불 요청도 직렬화)
CREATE OR REPLACE FUNCTION enforce_refund_limit() RETURNS trigger AS $$
DECLARE
  p payments%ROWTYPE;
  committed INT;
BEGIN
  SELECT * INTO p FROM payments WHERE id = NEW.payment_id FOR UPDATE;
  IF p.status NOT IN ('DONE','PARTIAL_CANCELED') THEN
    RAISE EXCEPTION 'payment % is not refundable in status %', p.id, p.status USING ERRCODE = 'check_violation';
  END IF;
  SELECT COALESCE(sum(amount),0) INTO committed FROM refunds
   WHERE payment_id = NEW.payment_id AND status IN ('REQUESTED','SUCCEEDED')
     AND id IS DISTINCT FROM NEW.id;
  IF committed + NEW.amount > p.approved_amount THEN
    RAISE EXCEPTION 'refund total % exceeds approved amount %', committed + NEW.amount, p.approved_amount
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_refund_limit BEFORE INSERT ON refunds
  FOR EACH ROW EXECUTE FUNCTION enforce_refund_limit();

-- 웹훅 수신 원장 (중복 수신 제거 + 재처리 가능)
CREATE TABLE payment_webhook_events (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider        TEXT NOT NULL DEFAULT 'TOSS',
  event_type      VARCHAR(60) NOT NULL,
  dedupe_key      BYTEA NOT NULL UNIQUE,         -- SHA-256(원문 본문)
  order_id        VARCHAR(64),
  payment_key     VARCHAR(200),
  payload         JSONB NOT NULL,
  verification    TEXT NOT NULL DEFAULT 'PENDING'
                  CHECK (verification IN ('PENDING','VERIFIED','REJECTED')),
  processed_at    TIMESTAMPTZ,
  process_error   VARCHAR(500),
  received_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_webhook_unprocessed ON payment_webhook_events (received_at) WHERE processed_at IS NULL;

-- 결제 관련 작업·오류 추적 로그 (분쟁 대응). 민감정보는 애플리케이션에서 마스킹 후 기록.
CREATE TABLE payment_audit_logs (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id      BIGINT REFERENCES payments(id),
  refund_id       BIGINT REFERENCES refunds(id),
  action          VARCHAR(40) NOT NULL,          -- CONFIRM_REQUEST, CONFIRM_RESPONSE, CANCEL_REQUEST, RECONCILE ...
  outcome         VARCHAR(20) NOT NULL CHECK (outcome IN ('OK','ERROR','TIMEOUT','INFO')),
  http_status     INT,
  provider_code   VARCHAR(80),
  detail          JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_payment_audit ON payment_audit_logs (payment_id, created_at);

-- ---------------------------------------------------------------------
-- 흐름 함수 (Spring 서비스는 이 함수들을 트랜잭션 단위로 호출한다)
-- 오류 코드 규약: 'P0001' + 메시지 접두어로 API 오류 코드를 전달
--   SLOT_UNAVAILABLE, HOLD_LIMIT, VENUE_NOT_BOOKABLE, ACCOUNT_NOT_ALLOWED,
--   HOLD_EXPIRED, AMOUNT_MISMATCH, INVALID_STATE, NOT_CANCELABLE, FORBIDDEN
-- 슬롯 충돌은 배제 제약 위반(SQLSTATE 23P01)으로 올라오며 API에서 409 SLOT_TAKEN 으로 매핑.
-- ---------------------------------------------------------------------

-- 결제 진행 중이 아닌 만료 선점을 해제
CREATE OR REPLACE FUNCTION fn_expire_holds(p_court_id BIGINT DEFAULT NULL, p_range TSTZRANGE DEFAULT NULL)
RETURNS INT AS $$
DECLARE n INT;
BEGIN
  WITH expired AS (
    UPDATE reservations r SET status = 'EXPIRED'
     WHERE r.status = 'PENDING_PAYMENT'
       AND r.hold_expires_at < now()
       AND (p_court_id IS NULL OR r.court_id = p_court_id)
       AND (p_range IS NULL OR r.period && p_range)
       AND NOT EXISTS (SELECT 1 FROM payments p
                       WHERE p.reservation_id = r.id AND p.status = 'IN_PROGRESS')
    RETURNING r.id)
  UPDATE payments p SET status = 'EXPIRED'
    FROM expired e WHERE p.reservation_id = e.id AND p.status = 'READY';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_create_reservation_hold(
  p_user_id BIGINT, p_court_id BIGINT, p_start TIMESTAMPTZ, p_end TIMESTAMPTZ,
  p_hold_minutes INT DEFAULT 10)
RETURNS BIGINT AS $$
DECLARE
  u users%ROWTYPE;
  c courts%ROWTYPE;
  v futsal_venues%ROWTYPE;
  req TSTZRANGE := tstzrange(p_start, p_end, '[)');
  covered INTERVAL;
  price_sum INT;
  partial INT;
  pending INT;
  new_id BIGINT;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user_id;
  IF NOT FOUND OR u.status <> 'ACTIVE' OR u.email_verified_at IS NULL THEN
    RAISE EXCEPTION 'ACCOUNT_NOT_ALLOWED';
  END IF;

  SELECT * INTO c FROM courts WHERE id = p_court_id;
  IF NOT FOUND OR NOT c.is_active THEN RAISE EXCEPTION 'VENUE_NOT_BOOKABLE'; END IF;
  SELECT * INTO v FROM futsal_venues WHERE id = c.venue_id;
  IF v.verification_status <> 'VERIFIED' THEN RAISE EXCEPTION 'VENUE_NOT_BOOKABLE'; END IF;

  IF p_end <= p_start OR p_start <= now() THEN RAISE EXCEPTION 'SLOT_UNAVAILABLE'; END IF;

  -- 같은 코트의 선점 생성을 직렬화 (트랜잭션 종료 시 자동 해제).
  -- 배제 제약만으로도 중복은 막히지만, 서로 다른 구간이 동시에 들어오면 GiST 배제 검사끼리
  -- 교착(deadlock)이 발생함을 동시성 테스트(C2)에서 확인 → 코트 단위 잠금으로 제거.
  PERFORM pg_advisory_xact_lock(7301, (p_court_id % 2147483647)::int);
  -- 사용자 단위 잠금: 같은 사용자의 동시 요청이 선점 3건 제한을 우회하지 못하게 함
  PERFORM pg_advisory_xact_lock(7302, (p_user_id % 2147483647)::int);

  -- 사용자별 동시 선점 수 제한 (슬롯 사재기 방지)
  SELECT count(*) INTO pending FROM reservations
   WHERE user_id = p_user_id AND status = 'PENDING_PAYMENT' AND hold_expires_at >= now();
  IF pending >= 3 THEN RAISE EXCEPTION 'HOLD_LIMIT'; END IF;

  -- 슬롯 경계 정렬 + 전 구간이 OPEN 슬롯으로 빈틈없이 덮이는지 확인
  SELECT count(*) INTO partial FROM time_slots
   WHERE court_id = p_court_id AND period && req AND NOT (period <@ req);
  SELECT COALESCE(sum(upper(period) - lower(period)), interval '0'), COALESCE(sum(price), 0)
    INTO covered, price_sum
    FROM time_slots
   WHERE court_id = p_court_id AND period <@ req AND status = 'OPEN';
  IF partial > 0 OR covered <> (p_end - p_start) THEN RAISE EXCEPTION 'SLOT_UNAVAILABLE'; END IF;

  IF EXISTS (SELECT 1 FROM schedule_closures
              WHERE venue_id = v.id AND (court_id IS NULL OR court_id = p_court_id)
                AND period && req) THEN
    RAISE EXCEPTION 'SLOT_UNAVAILABLE';
  END IF;

  -- 같은 구간의 만료된 선점을 먼저 정리 (스케줄러 지연과 무관하게 즉시 재예약 가능)
  PERFORM fn_expire_holds(p_court_id, req);

  INSERT INTO reservations (user_id, venue_id, court_id, period, total_amount,
                            hold_expires_at, cancel_policy_snapshot)
  VALUES (p_user_id, v.id, p_court_id, req, price_sum,
          now() + make_interval(mins => p_hold_minutes), v.cancel_policy)
  RETURNING id INTO new_id;          -- 겹치는 활성 예약이 있으면 여기서 23P01
  RETURN new_id;
END $$ LANGUAGE plpgsql;

-- 결제 주문 생성 (금액은 서버가 예약에서 가져옴; 클라이언트 금액은 받지 않음)
CREATE OR REPLACE FUNCTION fn_create_payment_order(
  p_user_id BIGINT, p_reservation_id BIGINT, p_mode TEXT, p_order_id VARCHAR)
RETURNS BIGINT AS $$
DECLARE r reservations%ROWTYPE; new_id BIGINT;
BEGIN
  SELECT * INTO r FROM reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND OR r.user_id <> p_user_id THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF r.status <> 'PENDING_PAYMENT' THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  IF r.hold_expires_at < now() THEN RAISE EXCEPTION 'HOLD_EXPIRED'; END IF;
  -- 이전 미완료 주문은 폐기 (재시도 시 새 orderId)
  UPDATE payments SET status = 'ABORTED', failure_code = 'SUPERSEDED'
   WHERE reservation_id = r.id AND status = 'READY';
  INSERT INTO payments (reservation_id, user_id, mode, order_id, amount)
  VALUES (r.id, p_user_id, p_mode, p_order_id, r.total_amount)
  RETURNING id INTO new_id;
  RETURN new_id;
END $$ LANGUAGE plpgsql;

-- 승인 API 호출 직전: 금액·소유자·상태 검증 후 IN_PROGRESS 로 전환 (이중 승인 차단)
CREATE OR REPLACE FUNCTION fn_payment_confirm_begin(
  p_user_id BIGINT, p_order_id VARCHAR, p_payment_key VARCHAR, p_amount INT)
RETURNS BIGINT AS $$
DECLARE p payments%ROWTYPE; r reservations%ROWTYPE;
BEGIN
  SELECT * INTO p FROM payments WHERE order_id = p_order_id FOR UPDATE;
  IF NOT FOUND OR p.user_id <> p_user_id THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT * INTO r FROM reservations WHERE id = p.reservation_id FOR UPDATE;
  IF p.amount <> p_amount THEN
    UPDATE payments SET status = 'ABORTED', failure_code = 'AMOUNT_MISMATCH' WHERE id = p.id;
    INSERT INTO payment_audit_logs (payment_id, action, outcome, detail)
      VALUES (p.id, 'CONFIRM_REJECTED', 'ERROR',
              jsonb_build_object('reason','AMOUNT_MISMATCH','expected',p.amount,'received',p_amount));
    RETURN -1;   -- 호출 측은 AMOUNT_MISMATCH 로 응답 (토스 승인 호출하지 않음 → 결제 미확정)
  END IF;
  IF p.status <> 'READY' THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  IF r.status <> 'PENDING_PAYMENT' OR r.hold_expires_at < now() THEN
    UPDATE payments SET status = 'EXPIRED' WHERE id = p.id;
    RETURN -2;   -- HOLD_EXPIRED (토스 승인 호출하지 않음)
  END IF;
  UPDATE payments SET status = 'IN_PROGRESS', payment_key = p_payment_key WHERE id = p.id;
  INSERT INTO payment_audit_logs (payment_id, action, outcome) VALUES (p.id, 'CONFIRM_REQUEST', 'INFO');
  RETURN p.id;
END $$ LANGUAGE plpgsql;

-- 토스 승인 성공 (응답 또는 조회 API로 확인된 경우에만 호출)
CREATE OR REPLACE FUNCTION fn_payment_confirm_succeeded(
  p_order_id VARCHAR, p_approved_amount INT, p_method VARCHAR, p_receipt_url TEXT,
  p_secret VARCHAR, p_approved_at TIMESTAMPTZ)
RETURNS TEXT AS $$
DECLARE p payments%ROWTYPE; r reservations%ROWTYPE;
BEGIN
  SELECT * INTO p FROM payments WHERE order_id = p_order_id FOR UPDATE;
  IF p.status = 'DONE' THEN RETURN 'ALREADY_DONE'; END IF;   -- 웹훅·응답 중복 처리 멱등
  IF p.status <> 'IN_PROGRESS' THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  SELECT * INTO r FROM reservations WHERE id = p.reservation_id FOR UPDATE;

  UPDATE payments SET status = 'DONE', approved_amount = p_approved_amount,
         balance_amount = p_approved_amount, method = p_method, receipt_url = p_receipt_url,
         webhook_secret = p_secret, approved_at = p_approved_at
   WHERE id = p.id;

  IF p_approved_amount <> r.total_amount OR r.status <> 'PENDING_PAYMENT' THEN
    -- 승인은 되었으나 예약을 확정할 수 없음 → 호출 측이 즉시 전액 취소(보상)해야 함
    INSERT INTO payment_audit_logs (payment_id, action, outcome, detail)
      VALUES (p.id, 'NEEDS_COMPENSATION', 'ERROR',
              jsonb_build_object('reservationStatus', r.status, 'approved', p_approved_amount,
                                 'expected', r.total_amount));
    RETURN 'NEEDS_COMPENSATION';
  END IF;

  UPDATE reservations SET status = 'CONFIRMED' WHERE id = r.id;
  INSERT INTO payment_audit_logs (payment_id, action, outcome) VALUES (p.id, 'CONFIRMED', 'OK');
  RETURN 'CONFIRMED';
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_payment_confirm_failed(
  p_order_id VARCHAR, p_code VARCHAR, p_message VARCHAR)
RETURNS VOID AS $$
BEGIN
  UPDATE payments SET status = 'ABORTED', failure_code = p_code, failure_message = left(p_message, 300)
   WHERE order_id = p_order_id AND status IN ('READY','IN_PROGRESS');
  INSERT INTO payment_audit_logs (payment_id, action, outcome, provider_code)
    SELECT id, 'CONFIRM_FAILED', 'ERROR', p_code FROM payments WHERE order_id = p_order_id;
  -- 예약은 선점 시간 안에서 재결제 가능하도록 PENDING_PAYMENT 유지
END $$ LANGUAGE plpgsql;

-- 취소 정책 스냅샷으로 환불액 계산
CREATE OR REPLACE FUNCTION fn_refund_amount(p_total INT, p_policy JSONB, p_start TIMESTAMPTZ, p_at TIMESTAMPTZ)
RETURNS INT AS $$
  SELECT COALESCE((
    SELECT (p_total * (rule->>'refundPercent')::int) / 100
      FROM jsonb_array_elements(p_policy) rule
     WHERE extract(epoch FROM (p_start - p_at)) / 3600.0 >= (rule->>'hoursBefore')::numeric
     ORDER BY (rule->>'hoursBefore')::numeric DESC
     LIMIT 1), 0);
$$ LANGUAGE sql IMMUTABLE;

-- 예약 취소: 슬롯 즉시 반환 + 환불 요청 행 생성. 반환값 = 환불 요청 id (환불 없음이면 NULL)
--   USER     : 이용 시작 전만 가능, 정책 스냅샷 기준 환불
--   OPERATOR : 구장 사정 취소 → 전액 환불 (해당 구장 운영자만)
--   ADMIN    : 전액 환불
CREATE OR REPLACE FUNCTION fn_cancel_reservation(
  p_reservation_id BIGINT, p_actor TEXT, p_actor_user_id BIGINT, p_reason VARCHAR)
RETURNS BIGINT AS $$
DECLARE
  r reservations%ROWTYPE; p payments%ROWTYPE; amt INT; refund_id BIGINT;
BEGIN
  SELECT * INTO r FROM reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;

  IF p_actor = 'USER' AND r.user_id <> p_actor_user_id THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF p_actor = 'OPERATOR' AND NOT EXISTS (
       SELECT 1 FROM venue_operators WHERE venue_id = r.venue_id AND user_id = p_actor_user_id) THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF r.status = 'PENDING_PAYMENT' THEN
    IF EXISTS (SELECT 1 FROM payments WHERE reservation_id = r.id AND status = 'IN_PROGRESS') THEN
      RAISE EXCEPTION 'INVALID_STATE';   -- 승인 진행 중에는 취소 불가 (결과 확정 후 처리)
    END IF;
    UPDATE payments SET status = 'ABORTED', failure_code = 'RESERVATION_CANCELED'
     WHERE reservation_id = r.id AND status = 'READY';
    UPDATE reservations SET status = 'CANCELED', canceled_by = p_actor, cancel_reason = p_reason
     WHERE id = r.id;
    RETURN NULL;
  END IF;

  IF r.status <> 'CONFIRMED' THEN RAISE EXCEPTION 'INVALID_STATE'; END IF;
  IF p_actor = 'USER' AND lower(r.period) <= now() THEN RAISE EXCEPTION 'NOT_CANCELABLE'; END IF;

  SELECT * INTO p FROM payments WHERE reservation_id = r.id AND status = 'DONE';
  amt := CASE WHEN p_actor = 'USER'
              THEN fn_refund_amount(p.approved_amount, r.cancel_policy_snapshot, lower(r.period), now())
              ELSE p.approved_amount END;

  UPDATE reservations SET status = 'CANCELED', canceled_by = p_actor, cancel_reason = p_reason
   WHERE id = r.id;

  IF amt > 0 THEN
    INSERT INTO refunds (payment_id, reservation_id, amount, reason, requested_by, requested_by_user)
    VALUES (p.id, r.id, amt, COALESCE(p_reason, 'reservation canceled'), p_actor, p_actor_user_id)
    RETURNING id INTO refund_id;
  END IF;
  RETURN refund_id;
END $$ LANGUAGE plpgsql;

-- 보상 취소: 승인됐지만 확정 불가한 결제를 전액 환불 요청
CREATE OR REPLACE FUNCTION fn_request_compensation_refund(p_order_id VARCHAR)
RETURNS BIGINT AS $$
DECLARE p payments%ROWTYPE; refund_id BIGINT;
BEGIN
  SELECT * INTO p FROM payments WHERE order_id = p_order_id FOR UPDATE;
  SELECT id INTO refund_id FROM refunds WHERE payment_id = p.id AND requested_by = 'SYSTEM'
     AND status IN ('REQUESTED','SUCCEEDED');
  IF FOUND THEN RETURN refund_id; END IF;      -- 멱등
  INSERT INTO refunds (payment_id, reservation_id, amount, reason, requested_by)
  VALUES (p.id, p.reservation_id, p.balance_amount, 'auto compensation: reservation not confirmable', 'SYSTEM')
  RETURNING id INTO refund_id;
  RETURN refund_id;
END $$ LANGUAGE plpgsql;

-- 토스 취소 API 결과 반영
CREATE OR REPLACE FUNCTION fn_refund_result(
  p_refund_id BIGINT, p_success BOOLEAN, p_tx_key VARCHAR, p_code VARCHAR, p_message VARCHAR)
RETURNS TEXT AS $$
DECLARE f refunds%ROWTYPE; p payments%ROWTYPE; new_balance INT;
BEGIN
  SELECT * INTO f FROM refunds WHERE id = p_refund_id FOR UPDATE;
  IF f.status = 'SUCCEEDED' THEN RETURN 'ALREADY_SUCCEEDED'; END IF;
  SELECT * INTO p FROM payments WHERE id = f.payment_id FOR UPDATE;

  IF NOT p_success THEN
    -- 실패는 재시도 대상으로 남긴다 (같은 멱등키로 재요청). 운영 알림 대상.
    UPDATE refunds SET attempt_count = attempt_count + 1, failure_code = p_code,
           failure_message = left(p_message,300) WHERE id = f.id;
    RETURN 'RETRY';
  END IF;

  new_balance := p.balance_amount - f.amount;
  UPDATE refunds SET status = 'SUCCEEDED', provider_transaction_key = p_tx_key,
         completed_at = now(), attempt_count = attempt_count + 1 WHERE id = f.id;
  UPDATE payments SET balance_amount = new_balance,
         status = CASE WHEN new_balance = 0 THEN 'CANCELED' ELSE 'PARTIAL_CANCELED' END
   WHERE id = p.id;
  IF NOT EXISTS (SELECT 1 FROM refunds WHERE reservation_id = f.reservation_id AND status = 'REQUESTED') THEN
    UPDATE reservations SET status = 'REFUNDED' WHERE id = f.reservation_id AND status = 'CANCELED';
  END IF;
  RETURN 'SUCCEEDED';
END $$ LANGUAGE plpgsql;

-- 예약 가능 시간 조회 (클라이언트 표시용. 최종 보장은 fn_create_reservation_hold)
CREATE OR REPLACE FUNCTION fn_available_slots(p_court_id BIGINT, p_date DATE)
RETURNS TABLE (slot_id BIGINT, starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ, price INT, available BOOLEAN) AS $$
  SELECT t.id, lower(t.period), upper(t.period), t.price,
         t.status = 'OPEN'
         AND lower(t.period) > now()
         AND NOT EXISTS (SELECT 1 FROM reservations r
                          WHERE r.court_id = t.court_id AND r.period && t.period
                            AND (r.status = 'CONFIRMED'
                                 OR (r.status = 'PENDING_PAYMENT'
                                     AND (r.hold_expires_at >= now()
                                          OR EXISTS (SELECT 1 FROM payments p
                                                      WHERE p.reservation_id = r.id
                                                        AND p.status = 'IN_PROGRESS')))))
         AND NOT EXISTS (SELECT 1 FROM schedule_closures sc JOIN courts c ON c.id = t.court_id
                          WHERE sc.venue_id = c.venue_id
                            AND (sc.court_id IS NULL OR sc.court_id = t.court_id)
                            AND sc.period && t.period)
    FROM time_slots t
   WHERE t.court_id = p_court_id
     AND t.period && tstzrange((p_date::timestamp AT TIME ZONE 'Asia/Seoul'),
                               ((p_date + 1)::timestamp AT TIME ZONE 'Asia/Seoul'), '[)')
   ORDER BY lower(t.period);
$$ LANGUAGE sql STABLE;
