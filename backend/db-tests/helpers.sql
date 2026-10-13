-- 테스트 전용 헬퍼 (운영 DB에는 적용하지 않음)
SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS t;

CREATE OR REPLACE FUNCTION t.ok(cond BOOLEAN, msg TEXT) RETURNS VOID AS $$
BEGIN
  IF cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERTION FAILED: %', msg; END IF;
  RAISE NOTICE 'PASS: %', msg;
END $$ LANGUAGE plpgsql;

-- SQL 실행 시 특정 오류(SQLSTATE 또는 메시지 부분일치)가 나야 통과
CREATE OR REPLACE FUNCTION t.raises(sql TEXT, expected TEXT, msg TEXT) RETURNS VOID AS $$
BEGIN
  BEGIN
    EXECUTE sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = expected OR position(expected IN SQLERRM) > 0 THEN
      RAISE NOTICE 'PASS: % (got % %)', msg, SQLSTATE, SQLERRM;
      RETURN;
    END IF;
    RAISE EXCEPTION 'ASSERTION FAILED: % — expected %, got % %', msg, expected, SQLSTATE, SQLERRM;
  END;
  RAISE EXCEPTION 'ASSERTION FAILED: % — expected error %, but statement succeeded', msg, expected;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION t.user(p_email TEXT, p_verified BOOLEAN DEFAULT true) RETURNS BIGINT AS $$
DECLARE uid BIGINT;
BEGIN
  INSERT INTO users (email, password_hash, email_verified_at)
  VALUES (p_email, '$2a$10$testhashtesthashtesthashtesthashtesthashtesthashtesthas',
          CASE WHEN p_verified THEN now() END)
  RETURNING id INTO uid;
  INSERT INTO user_profiles (user_id, nickname)
  VALUES (uid, 'u' || uid || '_' || substr(md5(p_email), 1, 6));
  RETURN uid;
END $$ LANGUAGE plpgsql;

-- 검증 완료 구장 + 코트 1면
CREATE OR REPLACE FUNCTION t.venue(p_name TEXT, p_verified BOOLEAN DEFAULT true) RETURNS BIGINT AS $$
DECLARE vid BIGINT; cid BIGINT;
BEGIN
  INSERT INTO futsal_venues (name, road_address, region_code, latitude, longitude,
                             verification_status, verified_at)
  VALUES (p_name, '테스트시 테스트로 1', '41590', 37.2, 127.0,
          CASE WHEN p_verified THEN 'VERIFIED' ELSE 'PENDING_REVIEW' END,
          CASE WHEN p_verified THEN now() END)
  RETURNING id INTO vid;
  INSERT INTO courts (venue_id, name, is_indoor, surface, size_class)
  VALUES (vid, 'A코트', true, 'ARTIFICIAL_TURF', '5V5') RETURNING id INTO cid;
  RETURN cid;   -- 코트 id 반환
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION t.court2(p_court BIGINT) RETURNS BIGINT AS $$
  INSERT INTO courts (venue_id, name, is_indoor, surface, size_class)
  SELECT venue_id, 'B코트', false, 'ARTIFICIAL_TURF', '6V6' FROM courts WHERE id = p_court
  RETURNING id;
$$ LANGUAGE sql;

-- now() 기준 h시간 뒤(정시 내림)부터 1시간짜리 슬롯 n개 수동 생성
CREATE OR REPLACE FUNCTION t.slots(p_court BIGINT, p_hours_from_now INT, p_n INT, p_price INT DEFAULT 60000)
RETURNS TIMESTAMPTZ AS $$
DECLARE s TIMESTAMPTZ := date_trunc('hour', now()) + make_interval(hours => p_hours_from_now);
BEGIN
  FOR i IN 0 .. p_n - 1 LOOP
    INSERT INTO time_slots (court_id, period, price, source)
    VALUES (p_court, tstzrange(s + make_interval(hours => i), s + make_interval(hours => i + 1), '[)'),
            p_price, 'MANUAL');
  END LOOP;
  RETURN s;
END $$ LANGUAGE plpgsql;

-- 예약 → 주문 → 승인까지 한 번에 (확정 예약 만들기)
CREATE OR REPLACE FUNCTION t.confirmed(p_user BIGINT, p_court BIGINT, p_start TIMESTAMPTZ, p_hours INT)
RETURNS BIGINT AS $$
DECLARE rid BIGINT; amt INT; oid TEXT := 'ord-' || gen_random_uuid();
BEGIN
  rid := fn_create_reservation_hold(p_user, p_court, p_start, p_start + make_interval(hours => p_hours));
  PERFORM fn_create_payment_order(p_user, rid, 'TEST', oid);
  SELECT total_amount INTO amt FROM reservations WHERE id = rid;
  PERFORM fn_payment_confirm_begin(p_user, oid, 'pk-' || oid, amt);
  PERFORM fn_payment_confirm_succeeded(oid, amt, '카드', 'https://receipt.example/x', 'sec', now());
  RETURN rid;
END $$ LANGUAGE plpgsql;
