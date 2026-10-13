-- =====================================================================
-- F-Mate V2: 구장, 코트, 운영시간, 예약 가능 슬롯, 예약
-- 핵심 보장
--  * 같은 코트의 겹치는 시간대에 "활성 예약"(결제 대기, 확정)은 DB 배제 제약으로 최대 1건.
--    애플리케이션 버그나 동시 요청이 있어도 DB가 거부한다.
--  * 예약 상태 전이는 트리거로 강제한다 (허용되지 않은 전이는 예외).
--  * 예약 가능 시간은 운영자가 등록한 슬롯(time_slots)에서만 나온다. 하드코딩 없음.
-- =====================================================================

-- 구장 (사업장 단위). 운영자 신청 → 관리자 검증(VERIFIED) 이후에만 검색/예약에 노출.
CREATE TABLE futsal_venues (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name            VARCHAR(100) NOT NULL,
  description     TEXT,
  road_address    VARCHAR(200) NOT NULL,
  detail_address  VARCHAR(100),
  region_code     VARCHAR(10) NOT NULL,         -- 시군구 코드 (지역 필터)
  latitude        DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN 33 AND 39.5),   -- 대한민국 범위
  longitude       DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN 124 AND 132),
  phone           VARCHAR(20),
  business_reg_no VARCHAR(12),                  -- 사업자등록번호 (검증 자료)
  rules           TEXT,                         -- 이용 규칙
  verification_status TEXT NOT NULL DEFAULT 'PENDING_REVIEW'
                  CHECK (verification_status IN ('PENDING_REVIEW','VERIFIED','REJECTED','SUSPENDED')),
  verified_at     TIMESTAMPTZ,
  verified_by     BIGINT REFERENCES users(id),
  data_source     TEXT NOT NULL DEFAULT 'OPERATOR'
                  CHECK (data_source IN ('OPERATOR','PARTNER_API','ADMIN')),  -- 출처 추적
  -- 취소 정책: 이용 시작 N시간 전까지 환불율(%). 예약 시점에 예약 레코드로 스냅샷 복사.
  cancel_policy   JSONB NOT NULL DEFAULT
                  '[{"hoursBefore":72,"refundPercent":100},{"hoursBefore":24,"refundPercent":50},{"hoursBefore":0,"refundPercent":0}]',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT venue_verified_consistency CHECK (
    verification_status <> 'VERIFIED' OR verified_at IS NOT NULL)
);
CREATE INDEX ix_venues_geo ON futsal_venues (latitude, longitude) WHERE verification_status = 'VERIFIED';
CREATE INDEX ix_venues_region ON futsal_venues (region_code) WHERE verification_status = 'VERIFIED';
CREATE INDEX ix_venues_name_trgm ON futsal_venues USING gin (name gin_trgm_ops);
CREATE TRIGGER trg_venues_updated BEFORE UPDATE ON futsal_venues
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 구장 운영자 권한 (한 구장에 여러 직원, 한 사람이 여러 구장 가능)
CREATE TABLE venue_operators (
  venue_id        BIGINT NOT NULL REFERENCES futsal_venues(id) ON DELETE CASCADE,
  user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('OWNER','STAFF')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (venue_id, user_id)
);
CREATE INDEX ix_venue_operators_user ON venue_operators (user_id);

-- 편의시설 마스터 + 구장별 보유
CREATE TABLE facilities (
  code            VARCHAR(30) PRIMARY KEY,
  label_ko        VARCHAR(30) NOT NULL
);
INSERT INTO facilities (code, label_ko) VALUES
  ('PARKING','주차'), ('SHOWER','샤워실'), ('LOCKER','락커'), ('CHANGING_ROOM','탈의실'),
  ('BALL_RENTAL','공 대여'), ('VEST_RENTAL','조끼 대여'), ('SHOE_RENTAL','풋살화 대여'),
  ('NIGHT_LIGHTING','야간 조명'), ('RESTROOM','화장실'), ('WATER','정수기'),
  ('SPECTATOR_SEATS','관람석'), ('CAFE','매점·카페'), ('WIFI','와이파이');

CREATE TABLE venue_facilities (
  venue_id        BIGINT NOT NULL REFERENCES futsal_venues(id) ON DELETE CASCADE,
  facility_code   VARCHAR(30) NOT NULL REFERENCES facilities(code),
  note            VARCHAR(100),
  PRIMARY KEY (venue_id, facility_code)
);

CREATE TABLE venue_photos (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  venue_id        BIGINT NOT NULL REFERENCES futsal_venues(id) ON DELETE CASCADE,
  object_key      TEXT NOT NULL,
  sort_order      SMALLINT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_venue_photos ON venue_photos (venue_id, sort_order);

-- 코트 (한 구장에 여러 면). 예약의 실제 단위.
CREATE TABLE courts (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  venue_id        BIGINT NOT NULL REFERENCES futsal_venues(id) ON DELETE CASCADE,
  name            VARCHAR(50) NOT NULL,
  is_indoor       BOOLEAN NOT NULL,
  surface         TEXT NOT NULL CHECK (surface IN ('ARTIFICIAL_TURF','URETHANE','WOOD','OTHER')),
  size_class      TEXT NOT NULL CHECK (size_class IN ('4V4','5V5','6V6','7V7')),
  width_m         NUMERIC(5,1),
  length_m        NUMERIC(5,1),
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (venue_id, name)
);
CREATE INDEX ix_courts_venue ON courts (venue_id) WHERE is_active;

-- 주간 운영시간 템플릿 (요일·시간대별 슬롯 길이와 요금).
-- 같은 코트·요일에서 시간대가 겹치면 거부. 자정을 넘기는 운영은 두 행으로 나눠 등록.
CREATE TABLE operating_hours (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  court_id        BIGINT NOT NULL REFERENCES courts(id) ON DELETE CASCADE,
  day_of_week     SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),  -- 0=일요일
  open_minute     SMALLINT NOT NULL CHECK (open_minute BETWEEN 0 AND 1439),
  close_minute    SMALLINT NOT NULL CHECK (close_minute BETWEEN 1 AND 1440),
  slot_minutes    SMALLINT NOT NULL CHECK (slot_minutes IN (30,60,90,120)),
  price_per_slot  INTEGER NOT NULL CHECK (price_per_slot BETWEEN 0 AND 10000000),  -- 원(KRW)
  CHECK (close_minute > open_minute),
  CHECK ((close_minute - open_minute) % slot_minutes = 0),
  EXCLUDE USING gist (
    court_id WITH =, day_of_week WITH =,
    int4range(open_minute, close_minute) WITH &&)
);

-- 휴무·대관 차단 (코트 단위 또는 구장 전체)
CREATE TABLE schedule_closures (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  venue_id        BIGINT NOT NULL REFERENCES futsal_venues(id) ON DELETE CASCADE,
  court_id        BIGINT REFERENCES courts(id) ON DELETE CASCADE,   -- NULL = 구장 전체
  period          TSTZRANGE NOT NULL CHECK (NOT isempty(period)),
  reason          VARCHAR(100),
  created_by      BIGINT REFERENCES users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_closures ON schedule_closures USING gist (venue_id, period);

-- 실제 예약 가능 슬롯 (운영시간 템플릿에서 앞으로 N일치를 생성, 운영자가 개별 수정 가능).
-- 슬롯끼리 겹칠 수 없음.
CREATE TABLE time_slots (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  court_id        BIGINT NOT NULL REFERENCES courts(id) ON DELETE CASCADE,
  period          TSTZRANGE NOT NULL,
  price           INTEGER NOT NULL CHECK (price BETWEEN 0 AND 10000000),
  status          TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','CLOSED')),
  source          TEXT NOT NULL DEFAULT 'TEMPLATE' CHECK (source IN ('TEMPLATE','MANUAL')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT slot_period_shape CHECK (
    NOT isempty(period) AND lower_inc(period) AND NOT upper_inc(period)
    AND NOT lower_inf(period) AND NOT upper_inf(period)),
  EXCLUDE USING gist (court_id WITH =, period WITH &&)
);
CREATE INDEX ix_slots_lookup ON time_slots USING gist (court_id, period);

-- 예약
CREATE TABLE reservations (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  public_id       UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),   -- 외부 노출용 (순번 노출 방지)
  user_id         BIGINT NOT NULL REFERENCES users(id),
  venue_id        BIGINT NOT NULL REFERENCES futsal_venues(id),
  court_id        BIGINT NOT NULL REFERENCES courts(id),
  period          TSTZRANGE NOT NULL,
  total_amount    INTEGER NOT NULL CHECK (total_amount >= 0),       -- 서버가 슬롯 요금 합으로 계산
  status          TEXT NOT NULL DEFAULT 'PENDING_PAYMENT' CHECK (status IN (
                    'PENDING_PAYMENT','CONFIRMED','CANCELED','REFUNDED','EXPIRED','COMPLETED','NO_SHOW')),
  hold_expires_at TIMESTAMPTZ NOT NULL,         -- 결제 대기 만료 시각
  cancel_policy_snapshot JSONB NOT NULL,
  confirmed_at    TIMESTAMPTZ,
  canceled_at     TIMESTAMPTZ,
  canceled_by     TEXT CHECK (canceled_by IN ('USER','OPERATOR','ADMIN','SYSTEM')),
  cancel_reason   VARCHAR(200),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT reservation_period_shape CHECK (
    NOT isempty(period) AND lower_inc(period) AND NOT upper_inc(period)
    AND NOT lower_inf(period) AND NOT upper_inf(period)
    AND upper(period) - lower(period) <= interval '6 hours'),
  -- ★ 중복 예약 방지의 최종 보장: 활성 예약끼리는 같은 코트에서 시간이 겹칠 수 없다.
  CONSTRAINT no_double_booking EXCLUDE USING gist (
    court_id WITH =, period WITH &&)
    WHERE (status IN ('PENDING_PAYMENT','CONFIRMED'))
);
CREATE INDEX ix_reservations_user ON reservations (user_id, created_at DESC);
CREATE INDEX ix_reservations_venue_period ON reservations USING gist (venue_id, period);
CREATE INDEX ix_reservations_hold ON reservations (hold_expires_at) WHERE status = 'PENDING_PAYMENT';
CREATE TRIGGER trg_reservations_updated BEFORE UPDATE ON reservations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 예약 상태 이력 (분쟁 대응용 감사 기록)
CREATE TABLE reservation_status_history (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reservation_id  BIGINT NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
  from_status     TEXT,
  to_status       TEXT NOT NULL,
  changed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_res_history ON reservation_status_history (reservation_id, changed_at);

-- 예약 상태 머신
--   PENDING_PAYMENT → CONFIRMED | EXPIRED | CANCELED
--   CONFIRMED       → CANCELED | COMPLETED | NO_SHOW
--   CANCELED        → REFUNDED            (환불 완료 시)
--   EXPIRED, REFUNDED, COMPLETED, NO_SHOW : 종료 상태
CREATE OR REPLACE FUNCTION enforce_reservation_transition() RETURNS trigger AS $$
DECLARE
  ok BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'PENDING_PAYMENT' THEN
      RAISE EXCEPTION 'reservation must start as PENDING_PAYMENT' USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO reservation_status_history (reservation_id, from_status, to_status)
      VALUES (NEW.id, NULL, NEW.status);
    RETURN NEW;
  END IF;

  IF NEW.status = OLD.status THEN
    -- 상태 외 필드 변경 시 핵심 필드 변경 금지
    IF NEW.period <> OLD.period OR NEW.court_id <> OLD.court_id OR NEW.total_amount <> OLD.total_amount
       OR NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'reservation core fields are immutable' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  ok := CASE OLD.status
    WHEN 'PENDING_PAYMENT' THEN NEW.status IN ('CONFIRMED','EXPIRED','CANCELED')
    WHEN 'CONFIRMED'       THEN NEW.status IN ('CANCELED','COMPLETED','NO_SHOW')
    WHEN 'CANCELED'        THEN NEW.status IN ('REFUNDED')
    ELSE false
  END;
  IF NOT ok THEN
    RAISE EXCEPTION 'illegal reservation transition % -> %', OLD.status, NEW.status
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.period <> OLD.period OR NEW.court_id <> OLD.court_id OR NEW.total_amount <> OLD.total_amount THEN
    RAISE EXCEPTION 'reservation core fields are immutable' USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.status = 'CONFIRMED' THEN NEW.confirmed_at := now(); END IF;
  IF NEW.status = 'CANCELED'  THEN
    NEW.canceled_at := now();
    IF NEW.canceled_by IS NULL THEN
      RAISE EXCEPTION 'canceled_by is required' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  INSERT INTO reservation_status_history (reservation_id, from_status, to_status)
    VALUES (NEW.id, OLD.status, NEW.status);
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reservation_insert AFTER INSERT ON reservations
  FOR EACH ROW EXECUTE FUNCTION enforce_reservation_transition();
CREATE TRIGGER trg_reservation_transition BEFORE UPDATE ON reservations
  FOR EACH ROW EXECUTE FUNCTION enforce_reservation_transition();

-- 운영시간 템플릿으로 슬롯 생성 (Asia/Seoul 기준, 이미 있는 슬롯과 겹치면 건너뜀).
-- 운영자가 템플릿을 저장할 때, 그리고 매일 배치로 앞으로 N일치를 채운다.
CREATE OR REPLACE FUNCTION generate_time_slots(p_court_id BIGINT, p_from DATE, p_days INT)
RETURNS INT AS $$
DECLARE
  d DATE;
  oh RECORD;
  m INT;
  s TIMESTAMPTZ;
  inserted INT := 0;
  n INT;
BEGIN
  IF p_days < 1 OR p_days > 90 THEN
    RAISE EXCEPTION 'p_days must be 1..90' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  FOR i IN 0 .. p_days - 1 LOOP
    d := p_from + i;
    FOR oh IN SELECT * FROM operating_hours
              WHERE court_id = p_court_id AND day_of_week = EXTRACT(DOW FROM d) LOOP
      m := oh.open_minute;
      WHILE m < oh.close_minute LOOP
        s := (d::timestamp + make_interval(mins => m)) AT TIME ZONE 'Asia/Seoul';
        INSERT INTO time_slots (court_id, period, price, source)
        SELECT p_court_id, tstzrange(s, s + make_interval(mins => oh.slot_minutes), '[)'),
               oh.price_per_slot, 'TEMPLATE'
        WHERE NOT EXISTS (
          SELECT 1 FROM time_slots t
          WHERE t.court_id = p_court_id
            AND t.period && tstzrange(s, s + make_interval(mins => oh.slot_minutes), '[)'));
        GET DIAGNOSTICS n = ROW_COUNT;
        inserted := inserted + n;
        m := m + oh.slot_minutes;
      END LOOP;
    END LOOP;
  END LOOP;
  RETURN inserted;
END $$ LANGUAGE plpgsql;
