-- 결제·환불 흐름 (단일 세션)
DO $$
DECLARE
  u1 BIGINT := t.user('pay1@test.kr'); u2 BIGINT := t.user('pay2@test.kr');
  op BIGINT := t.user('owner@test.kr');
  c BIGINT := t.venue('결제구장');
  s100 TIMESTAMPTZ; s30 TIMESTAMPTZ; s5 TIMESTAMPTZ;
  r BIGINT; rid BIGINT; pid BIGINT; ref BIGINT; res TEXT; v INT;
BEGIN
  INSERT INTO venue_operators (venue_id, user_id, role) SELECT venue_id, op, 'OWNER' FROM courts WHERE id = c;
  s100 := t.slots(c, 100, 2);    -- 100시간 뒤 → 100% 환불 구간
  s30  := t.slots(c, 30, 1);     -- 30시간 뒤  → 50%
  s5   := t.slots(c, 5, 1);      -- 5시간 뒤   → 0%

  -- 금액 위변조: 승인 API 호출 전 차단
  r := fn_create_reservation_hold(u1, c, s100, s100 + interval '1 hour');
  PERFORM fn_create_payment_order(u1, r, 'TEST', 'ord-tamper');
  v := fn_payment_confirm_begin(u1, 'ord-tamper', 'pk-tamper', 100);
  PERFORM t.ok(v = -1, '클라이언트가 보낸 금액이 다르면 승인 시작 거부 (AMOUNT_MISMATCH)');
  PERFORM t.ok((SELECT status FROM payments WHERE order_id = 'ord-tamper') = 'ABORTED', '변조 주문은 ABORTED');
  PERFORM t.ok((SELECT status FROM reservations WHERE id = r) = 'PENDING_PAYMENT', '예약은 결제 대기 유지 (재시도 가능)');
  PERFORM t.ok(EXISTS (SELECT 1 FROM payment_audit_logs WHERE detail->>'reason' = 'AMOUNT_MISMATCH'), '변조 시도 감사 로그 기록');

  -- 다른 사용자의 예약으로 주문/승인 불가
  PERFORM t.raises(format('SELECT fn_create_payment_order(%s,%s,%L,%L)', u2, r, 'TEST', 'ord-steal'), 'FORBIDDEN', '타인 예약 주문 생성 거부');
  PERFORM t.raises(format('INSERT INTO payments (reservation_id, user_id, mode, order_id, amount) VALUES (%s,%s,%L,%L,%s)', r, u1, 'TEST', 'ord-x', 1),
                   'does not match reservation amount', '예약 금액과 다른 결제 레코드 삽입 거부 (DB 레벨)');

  -- 정상 결제
  PERFORM fn_create_payment_order(u1, r, 'TEST', 'ord-ok');
  v := fn_payment_confirm_begin(u1, 'ord-ok', 'pk-ok', 60000);
  PERFORM t.raises(format('SELECT fn_payment_confirm_begin(%s,%L,%L,%s)', u1, 'ord-ok', 'pk-ok', 60000),
                   'INVALID_STATE', '같은 주문 승인 이중 시작 거부');
  PERFORM t.raises(format('SELECT fn_cancel_reservation(%s,%L,%s,%L)', r, 'USER', u1, 'x'),
                   'INVALID_STATE', '승인 진행 중 취소 거부');
  -- 승인 진행 중에는 선점 만료되어도 슬롯이 풀리지 않음
  UPDATE reservations SET hold_expires_at = now() - interval '1 minute' WHERE id = r;
  PERFORM fn_expire_holds();
  PERFORM t.ok((SELECT status FROM reservations WHERE id = r) = 'PENDING_PAYMENT',
               '승인 진행(IN_PROGRESS) 중인 선점은 만료 배치가 해제하지 않음');
  res := fn_payment_confirm_succeeded('ord-ok', 60000, '카드', 'https://r', 'sec', now());
  PERFORM t.ok(res = 'CONFIRMED', '승인 성공 → 예약 확정');
  res := fn_payment_confirm_succeeded('ord-ok', 60000, '카드', 'https://r', 'sec', now());
  PERFORM t.ok(res = 'ALREADY_DONE', '승인 결과 중복 수신(응답+웹훅) 멱등 처리');
  PERFORM t.raises(format('INSERT INTO payments (reservation_id, user_id, mode, order_id, amount) VALUES (%s,%s,%L,%L,%s)', r, u1, 'TEST', 'ord-dup', 60000),
                   'INVALID_STATE', '확정 예약에 새 결제 레코드 삽입 거부 (DB 트리거)');
  PERFORM t.raises(format('UPDATE payments SET amount = 1 WHERE order_id = %L', 'ord-ok'), 'immutable', '결제 금액 사후 변경 거부');
  PERFORM t.raises(format('UPDATE payments SET status = %L WHERE order_id = %L', 'READY', 'ord-ok'),
                   'illegal payment transition', 'DONE → READY 역전이 거부');

  -- ── 사용자 취소: 100시간 전 → 100% 환불
  ref := fn_cancel_reservation(r, 'USER', u1, '일정 변경');
  PERFORM t.ok((SELECT amount FROM refunds WHERE id = ref) = 60000, '이용 72시간 이전 취소 → 전액(60,000) 환불 요청');
  PERFORM t.ok((SELECT status FROM reservations WHERE id = r) = 'CANCELED', '취소 즉시 CANCELED (슬롯 반환)');
  rid := fn_create_reservation_hold(u2, c, s100, s100 + interval '1 hour');
  PERFORM t.ok(rid IS NOT NULL, '취소된 시간대는 다른 사용자가 바로 예약 가능');
  -- 환불 실패 → 재시도 대상, 성공 → REFUNDED
  res := fn_refund_result(ref, false, NULL, 'PROVIDER_ERROR', '일시 오류');
  PERFORM t.ok(res = 'RETRY' AND (SELECT status FROM refunds WHERE id = ref) = 'REQUESTED', '환불 실패는 REQUESTED 유지(같은 멱등키로 재시도)');
  res := fn_refund_result(ref, true, 'tx-1', NULL, NULL);
  PERFORM t.ok(res = 'SUCCEEDED', '환불 성공 반영');
  PERFORM t.ok((SELECT status FROM payments WHERE order_id = 'ord-ok') = 'CANCELED'
               AND (SELECT balance_amount FROM payments WHERE order_id = 'ord-ok') = 0, '전액 환불 → 결제 CANCELED, 잔액 0');
  PERFORM t.ok((SELECT status FROM reservations WHERE id = r) = 'REFUNDED', '환불 완료 → 예약 REFUNDED');
  PERFORM t.ok(fn_refund_result(ref, true, 'tx-1', NULL, NULL) = 'ALREADY_SUCCEEDED', '환불 결과 중복 수신 멱등');
  PERFORM t.raises(format('INSERT INTO refunds (payment_id, reservation_id, amount, reason, requested_by) SELECT id, reservation_id, 1, %L, %L FROM payments WHERE order_id = %L', 'x', 'ADMIN', 'ord-ok'),
                   'not refundable', '이미 전액 환불된 결제 추가 환불 거부');

  -- ── 30시간 전 취소 → 50% 부분 환불
  r := t.confirmed(u1, c, s30, 1);
  ref := fn_cancel_reservation(r, 'USER', u1, NULL);
  PERFORM t.ok((SELECT amount FROM refunds WHERE id = ref) = 30000, '24~72시간 전 취소 → 50%(30,000) 환불');
  PERFORM fn_refund_result(ref, true, 'tx-2', NULL, NULL);
  PERFORM t.ok((SELECT status FROM payments WHERE reservation_id = r AND status <> 'ABORTED') = 'PARTIAL_CANCELED'
               AND (SELECT balance_amount FROM payments WHERE reservation_id = r AND status <> 'ABORTED') = 30000,
               '부분 환불 → PARTIAL_CANCELED, 잔액 30,000');
  PERFORM t.raises(format('INSERT INTO refunds (payment_id, reservation_id, amount, reason, requested_by) SELECT id, reservation_id, 30001, %L, %L FROM payments WHERE reservation_id = %s AND status = %L', 'x', 'ADMIN', r, 'PARTIAL_CANCELED'),
                   'exceeds approved amount', '환불 합계가 승인 금액 초과 시 거부');
  ref := NULL;
  INSERT INTO refunds (payment_id, reservation_id, amount, reason, requested_by)
    SELECT id, reservation_id, 30000, '관리자 추가 환불', 'ADMIN' FROM payments WHERE reservation_id = r AND status = 'PARTIAL_CANCELED'
    RETURNING id INTO ref;
  PERFORM fn_refund_result(ref, true, 'tx-3', NULL, NULL);
  PERFORM t.ok((SELECT status FROM payments WHERE reservation_id = r AND status <> 'ABORTED') = 'CANCELED', '잔액 추가 환불 → CANCELED');

  -- ── 5시간 전 취소 → 환불 없음
  r := t.confirmed(u1, c, s5, 1);
  ref := fn_cancel_reservation(r, 'USER', u1, NULL);
  PERFORM t.ok(ref IS NULL AND (SELECT status FROM reservations WHERE id = r) = 'CANCELED', '24시간 이내 취소 → 환불 없이 CANCELED');

  -- ── 운영자 취소 → 정책 무관 전액 환불, 타 구장 운영자는 불가
  r := t.confirmed(u1, c, s100 + interval '1 hour', 1);
  PERFORM t.raises(format('SELECT fn_cancel_reservation(%s,%L,%s,%L)', r, 'OPERATOR', u2, 'x'), 'FORBIDDEN', '해당 구장 운영자가 아니면 취소 불가');
  PERFORM t.raises(format('SELECT fn_cancel_reservation(%s,%L,%s,%L)', r, 'USER', u2, 'x'), 'FORBIDDEN', '타인 예약 취소 불가');
  ref := fn_cancel_reservation(r, 'OPERATOR', op, '시설 점검');
  PERFORM t.ok((SELECT amount FROM refunds WHERE id = ref) = 60000, '운영자 사정 취소 → 전액 환불');
END $$;

-- 보상 시나리오는 슬롯이 필요하므로 별도 블록
DO $$
DECLARE u BIGINT := t.user('comp@test.kr'); c BIGINT := t.venue('보상구장'); s TIMESTAMPTZ; r BIGINT; res TEXT; ref BIGINT;
BEGIN
  s := t.slots(c, 200, 1);
  r := fn_create_reservation_hold(u, c, s, s + interval '1 hour');
  PERFORM fn_create_payment_order(u, r, 'TEST', 'ord-comp');
  PERFORM fn_payment_confirm_begin(u, 'ord-comp', 'pk-comp', 60000);
  res := fn_payment_confirm_succeeded('ord-comp', 59000, '카드', NULL, 'sec', now());
  PERFORM t.ok(res = 'NEEDS_COMPENSATION', 'PG 승인 금액 ≠ 예약 금액 → 확정하지 않고 보상 필요 반환');
  PERFORM t.ok((SELECT status FROM reservations WHERE id = r) = 'PENDING_PAYMENT', '예약은 확정되지 않음');
  ref := fn_request_compensation_refund('ord-comp');
  PERFORM t.ok(ref = fn_request_compensation_refund('ord-comp'), '보상 환불 요청 멱등 (중복 생성 없음)');
  PERFORM t.ok((SELECT amount FROM refunds WHERE id = ref) = 59000, '보상 환불 = 승인 금액 전액');
  PERFORM fn_refund_result(ref, true, 'tx-c', NULL, NULL);
  UPDATE reservations SET hold_expires_at = now() - interval '1 second' WHERE id = r;
  PERFORM fn_expire_holds();
  PERFORM t.ok((SELECT status FROM reservations WHERE id = r) = 'EXPIRED', '보상 환불 후 선점은 만료로 정리');

  PERFORM t.ok(fn_refund_amount(10000, '[{"hoursBefore":72,"refundPercent":100},{"hoursBefore":24,"refundPercent":50},{"hoursBefore":0,"refundPercent":0}]',
                                now() + interval '24 hours', now()) = 5000, '경계값: 정확히 24시간 전 → 50%');
  PERFORM t.ok(fn_refund_amount(9999, '[{"hoursBefore":0,"refundPercent":50}]', now() + interval '1 hour', now()) = 4999,
               '환불액은 원 단위 내림');
END $$;
