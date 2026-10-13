-- V6 보강 기능
DO $$
DECLARE
  u1 BIGINT := t.user('v6a@test.kr'); u2 BIGINT := t.user('v6b@test.kr');
  c BIGINT := t.venue('보강구장'); s TIMESTAMPTZ; r BIGINT; slot BIGINT;
BEGIN
  -- 같은 6자리 코드 해시가 서로 다른 사용자에게 동시에 존재할 수 있어야 함
  INSERT INTO one_time_tokens (user_id, purpose, token_hash, expires_at)
    VALUES (u1, 'EMAIL_VERIFY', sha256('123456'::bytea), now() + interval '15 minutes'),
           (u2, 'EMAIL_VERIFY', sha256('123456'::bytea), now() + interval '15 minutes');
  PERFORM t.ok((SELECT count(*) FROM one_time_tokens) = 2, '같은 코드 해시를 여러 사용자가 가질 수 있음');

  PERFORM t.ok((SELECT payment_customer_key IS NOT NULL FROM users WHERE id = u1)
               AND (SELECT payment_customer_key FROM users WHERE id = u1) <> (SELECT payment_customer_key FROM users WHERE id = u2),
               '사용자별 결제 고객키 자동 발급(서로 다름)');

  -- 예약이 걸린 슬롯 보호
  s := t.slots(c, 50, 2);
  r := fn_create_reservation_hold(u1, c, s, s + interval '1 hour');
  SELECT id INTO slot FROM time_slots WHERE court_id = c AND lower(period) = s;
  PERFORM t.raises(format('UPDATE time_slots SET status = %L WHERE id = %s', 'CLOSED', slot), 'SLOT_HAS_RESERVATION', '예약 걸린 슬롯 닫기 거부');
  PERFORM t.raises(format('UPDATE time_slots SET price = 1 WHERE id = %s', slot), 'SLOT_HAS_RESERVATION', '예약 걸린 슬롯 요금 변경 거부');
  PERFORM t.raises(format('DELETE FROM time_slots WHERE id = %s', slot), 'SLOT_HAS_RESERVATION', '예약 걸린 슬롯 삭제 거부');
  UPDATE time_slots SET price = 70000 WHERE court_id = c AND lower(period) = s + interval '1 hour';
  PERFORM t.ok((SELECT price FROM time_slots WHERE court_id = c AND lower(period) = s + interval '1 hour') = 70000, '예약 없는 슬롯은 요금 변경 가능');
  UPDATE reservations SET status = 'CANCELED', canceled_by = 'USER' WHERE id = r;
  UPDATE time_slots SET status = 'CLOSED' WHERE id = slot;
  PERFORM t.ok((SELECT status FROM time_slots WHERE id = slot) = 'CLOSED', '예약 취소 후에는 슬롯 닫기 가능');

  -- 지난 확정 예약 자동 완료: 과거 슬롯 예약은 함수로 직접 못 만드므로 확정 후 기간을 옮길 수 없어
  -- 완료 함수가 미래 예약은 건드리지 않는지만 확인
  r := t.confirmed(u2, c, s + interval '1 hour', 1);
  PERFORM fn_complete_past_reservations();
  PERFORM t.ok((SELECT status FROM reservations WHERE id = r) = 'CONFIRMED', '미래 확정 예약은 완료 처리하지 않음');

  -- 정지 해제
  UPDATE users SET status = 'SUSPENDED', suspended_until = now() - interval '1 minute' WHERE id = u1;
  PERFORM t.ok(fn_lift_expired_suspensions() = 1, '기간 지난 정지 1건 해제');
  PERFORM t.ok((SELECT status FROM users WHERE id = u1) = 'ACTIVE', '해제된 계정은 ACTIVE');

  -- 만료 업로드 정리
  INSERT INTO videos (owner_id, source_object_key, content_type, declared_size_bytes, upload_expires_at)
    VALUES (u1, 'raw/stale.mp4', 'video/mp4', 1000, now() - interval '1 minute');
  PERFORM t.ok(fn_fail_stale_uploads() = 1, '만료된 업로드는 FAILED 처리');
END $$;

-- 지난 확정 예약 완료 처리: 테스트를 위해 트리거를 잠시 끄고 과거 예약을 만든다
DO $$
DECLARE u BIGINT := t.user('past@test.kr'); c BIGINT := t.venue('과거구장'); r BIGINT;
BEGIN
  ALTER TABLE reservations DISABLE TRIGGER trg_reservation_insert;
  ALTER TABLE reservations DISABLE TRIGGER trg_reservation_requires_payment;
  INSERT INTO reservations (user_id, venue_id, court_id, period, total_amount, status, hold_expires_at, cancel_policy_snapshot)
    SELECT u, venue_id, id, tstzrange(now() - interval '5 hours', now() - interval '4 hours'), 1000, 'PENDING_PAYMENT', now(), '[]'
      FROM courts WHERE id = c RETURNING id INTO r;
  UPDATE reservations SET status = 'CONFIRMED' WHERE id = r;
  ALTER TABLE reservations ENABLE TRIGGER trg_reservation_insert;
  ALTER TABLE reservations ENABLE TRIGGER trg_reservation_requires_payment;
  PERFORM t.ok(fn_complete_past_reservations() = 1, '이용 종료 1시간 지난 확정 예약 1건 완료 처리');
  PERFORM t.ok((SELECT status FROM reservations WHERE id = r) = 'COMPLETED', '완료 처리된 예약은 COMPLETED');
END $$;
