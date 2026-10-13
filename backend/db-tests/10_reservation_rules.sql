-- 예약 규칙 (단일 세션)
DO $$
DECLARE
  u1 BIGINT := t.user('a@test.kr'); u2 BIGINT := t.user('b@test.kr');
  u_unverified BIGINT := t.user('c@test.kr', false);
  c1 BIGINT := t.venue('정상구장'); c2 BIGINT; c_unv BIGINT := t.venue('미검증구장', false);
  s TIMESTAMPTZ; s2 TIMESTAMPTZ; r1 BIGINT; r2 BIGINT; n INT;
BEGIN
  c2 := t.court2(c1);
  s := t.slots(c1, 48, 4);            -- 이틀 뒤 4시간
  PERFORM t.slots(c2, 48, 4);
  PERFORM t.slots(c_unv, 48, 2);

  -- 기본 선점
  r1 := fn_create_reservation_hold(u1, c1, s, s + interval '2 hours');
  PERFORM t.ok((SELECT status = 'PENDING_PAYMENT' AND total_amount = 120000 FROM reservations WHERE id = r1),
               '2시간 선점: PENDING_PAYMENT, 금액은 서버가 슬롯 합으로 계산(120,000)');

  -- 겹치는 시간 (부분 겹침 포함) 거부
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u2, c1, s + interval '1 hour', s + interval '3 hours'),
                   '23P01', '부분 겹침 예약은 배제 제약으로 거부');
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u2, c1, s, s + interval '1 hour'),
                   '23P01', '완전 포함 예약 거부');

  -- 맞닿은 시간과 다른 코트는 허용
  r2 := fn_create_reservation_hold(u2, c1, s + interval '2 hours', s + interval '3 hours');
  PERFORM t.ok(r2 IS NOT NULL, '끝 시각에 맞닿은 다음 시간대 예약은 허용 ([) 구간)');
  PERFORM t.ok(fn_create_reservation_hold(u2, c2, s, s + interval '2 hours') IS NOT NULL,
               '같은 시간이라도 다른 코트는 허용');

  -- 슬롯 경계/운영시간 검증
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u2, c1, s + interval '3 hours 30 minutes', s + interval '4 hours'),
                   'SLOT_UNAVAILABLE', '슬롯 경계에 맞지 않는 시간 거부');
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u2, c1, s + interval '3 hours', s + interval '5 hours'),
                   'SLOT_UNAVAILABLE', '운영 슬롯 밖까지 걸친 예약 거부 (하드코딩 시간 없음)');
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u2, c1, now() - interval '2 hours', now() - interval '1 hour'),
                   'SLOT_UNAVAILABLE', '지난 시간 예약 거부');

  -- 닫힌 슬롯 / 휴무
  UPDATE time_slots SET status = 'CLOSED' WHERE court_id = c1 AND lower(period) = s + interval '3 hours';
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u2, c1, s + interval '3 hours', s + interval '4 hours'),
                   'SLOT_UNAVAILABLE', '운영자가 닫은 슬롯 거부');
  INSERT INTO schedule_closures (venue_id, court_id, period, reason)
    SELECT venue_id, NULL, tstzrange(s + interval '2 hours', s + interval '4 hours'), '대관' FROM courts WHERE id = c2;
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u1, c2, s + interval '2 hours', s + interval '3 hours'),
                   'SLOT_UNAVAILABLE', '구장 전체 휴무 구간 거부');

  -- 계정·구장 상태
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u_unverified, c2, s, s + interval '1 hour'),
                   'ACCOUNT_NOT_ALLOWED', '이메일 미인증 계정 예약 불가');
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u1, c_unv, s, s + interval '1 hour'),
                   'VENUE_NOT_BOOKABLE', '관리자 검증 전 구장 예약 불가');

  -- 사용자당 동시 선점 3건 제한
  s2 := t.slots(c2, 120, 6);
  PERFORM fn_create_reservation_hold(u1, c2, s2, s2 + interval '1 hour');
  PERFORM fn_create_reservation_hold(u1, c2, s2 + interval '1 hour', s2 + interval '2 hours');
  -- u1: c1 1건 + c2 2건 = 3건
  PERFORM t.raises(format('SELECT fn_create_reservation_hold(%s,%s,%L,%L)', u1, c2, s2 + interval '2 hours', s2 + interval '3 hours'),
                   'HOLD_LIMIT', '결제 대기 선점 4번째 거부');

  -- 선점 만료 → 즉시 재예약 가능, 이전 예약은 EXPIRED
  UPDATE reservations SET hold_expires_at = now() - interval '1 second' WHERE id = r1;
  r2 := fn_create_reservation_hold(u2, c1, s, s + interval '1 hour');
  PERFORM t.ok((SELECT status FROM reservations WHERE id = r1) = 'EXPIRED',
               '만료된 선점은 같은 구간 신규 예약 시 EXPIRED 로 정리');
  PERFORM t.ok(r2 IS NOT NULL, '만료 선점 구간에 신규 예약 성공');

  -- 상태 머신 강제
  PERFORM t.raises(format('UPDATE reservations SET status = %L WHERE id = %s', 'CONFIRMED', r2),
                   'without a DONE payment', '결제 없이 CONFIRMED 전환 거부');
  PERFORM t.raises(format('UPDATE reservations SET status = %L WHERE id = %s', 'PENDING_PAYMENT', r1),
                   'illegal reservation transition', 'EXPIRED → PENDING_PAYMENT 역전이 거부');
  PERFORM t.raises(format('UPDATE reservations SET total_amount = 1 WHERE id = %s', r2),
                   'immutable', '예약 금액 사후 변경 거부');
  PERFORM t.raises(format('INSERT INTO reservations (user_id, venue_id, court_id, period, total_amount, status, hold_expires_at, cancel_policy_snapshot) SELECT %s, venue_id, id, tstzrange(%L::timestamptz, %L::timestamptz), 0, %L, now(), %L FROM courts WHERE id = %s',
                          u1, s + interval '10 days', s + interval '10 days 1 hour', 'CONFIRMED', '[]', c1),
                   'must start as PENDING_PAYMENT', '처음부터 CONFIRMED 로 삽입 거부');

  -- 상태 이력 기록
  SELECT count(*) INTO n FROM reservation_status_history WHERE reservation_id = r1;
  PERFORM t.ok(n = 2, '상태 이력: 생성 + 만료 2건 기록');

  -- 예약 가능 시간 조회
  PERFORM t.ok((SELECT NOT available FROM fn_available_slots(c1, (s AT TIME ZONE 'Asia/Seoul')::date)
                 WHERE starts_at = s),
               '조회: 선점된 슬롯은 예약 불가로 표시');
  PERFORM t.ok((SELECT NOT available FROM fn_available_slots(c1, ((s + interval '3 hours') AT TIME ZONE 'Asia/Seoul')::date)
                 WHERE starts_at = s + interval '3 hours'),
               '조회: 닫힌 슬롯은 예약 불가로 표시');
  PERFORM t.ok((SELECT available FROM fn_available_slots(c1, ((s + interval '1 hour') AT TIME ZONE 'Asia/Seoul')::date)
                 WHERE starts_at = s + interval '1 hour'),
               '조회: 만료 선점이 풀린 슬롯은 예약 가능으로 표시');
END $$;

-- 운영시간 템플릿 → 슬롯 생성
DO $$
DECLARE c BIGINT := t.venue('템플릿구장'); n1 INT; n2 INT; d DATE := (now() AT TIME ZONE 'Asia/Seoul')::date + 1;
BEGIN
  -- 매일 06:00~24:00, 2시간 슬롯 / 18시 이후 요금 다름
  INSERT INTO operating_hours (court_id, day_of_week, open_minute, close_minute, slot_minutes, price_per_slot)
  SELECT c, dow, 360, 1080, 120, 80000 FROM generate_series(0,6) dow;
  INSERT INTO operating_hours (court_id, day_of_week, open_minute, close_minute, slot_minutes, price_per_slot)
  SELECT c, dow, 1080, 1440, 120, 110000 FROM generate_series(0,6) dow;

  n1 := generate_time_slots(c, d, 7);
  n2 := generate_time_slots(c, d, 7);
  PERFORM t.ok(n1 = 63, '7일 x 9슬롯 = 63개 생성');
  PERFORM t.ok(n2 = 0, '재실행 시 중복 생성 없음 (멱등)');
  PERFORM t.ok((SELECT lower(period) FROM time_slots WHERE court_id = c ORDER BY lower(period) LIMIT 1)
               = (d::timestamp + interval '6 hours') AT TIME ZONE 'Asia/Seoul',
               '첫 슬롯은 한국시간 06:00');
  PERFORM t.ok((SELECT price FROM time_slots WHERE court_id = c
                 AND lower(period) = (d::timestamp + interval '18 hours') AT TIME ZONE 'Asia/Seoul') = 110000,
               '18시 이후 슬롯은 야간 요금');
  PERFORM t.raises(format('INSERT INTO operating_hours (court_id, day_of_week, open_minute, close_minute, slot_minutes, price_per_slot) VALUES (%s, 1, 1020, 1200, 60, 1)', c),
                   '23P01', '같은 요일 운영시간 구간 겹침 거부');
  PERFORM t.raises(format('INSERT INTO operating_hours (court_id, day_of_week, open_minute, close_minute, slot_minutes, price_per_slot) VALUES (%s, 1, 0, 100, 60, 1)', c),
                   '23514', '슬롯 길이로 나누어 떨어지지 않는 운영시간 거부');
END $$;
