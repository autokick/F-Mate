#!/usr/bin/env bash
# F-Mate DB 테스트 러너
#   필요: PostgreSQL 16+ (btree_gist, citext, pg_trgm 확장 포함 = postgresql-contrib), psql
#   사용: PGHOST=localhost PGPORT=5432 PGUSER=postgres ./run.sh
#   주의: fmate_t_* 이름의 데이터베이스를 만들고 지운다. 운영 DB 서버에서 실행하지 말 것.
set -uo pipefail
cd "$(dirname "$0")"
MIG=../src/main/resources/db/migration
PSQL="psql -X -q -v ON_ERROR_STOP=1"
PASS=0; FAIL=0; FAILED_NAMES=()

fresh_db() {  # $1 = db name
  $PSQL -d postgres -c "DROP DATABASE IF EXISTS $1" -c "CREATE DATABASE $1 TEMPLATE fmate_t_tpl" >/dev/null
  $PSQL -d "$1" -f helpers.sql >/dev/null
}
record() {  # $1 = name, $2 = 0 ok
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ✔ $1"; else FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ✘ $1"; fi
}

echo "▶ 마이그레이션 적용 (빈 DB → V1..V5)"
$PSQL -d postgres -c "DROP DATABASE IF EXISTS fmate_t_tpl" -c "CREATE DATABASE fmate_t_tpl" >/dev/null
for f in $(ls $MIG/V*__*.sql | sort -V); do
  if ! $PSQL -d fmate_t_tpl -f "$f" >/dev/null; then echo "  ✘ 마이그레이션 실패: $f"; exit 1; fi
  echo "  ✔ $(basename "$f")"
done

echo "▶ 규칙 테스트 (단일 세션)"
for f in [0-9][0-9]_*.sql; do
  db=fmate_t_$(basename "$f" .sql | tr -c 'a-z0-9_\n' '_')
  fresh_db "$db"
  out=$($PSQL -d "$db" -f "$f" 2>&1); rc=$?
  n=$(grep -c 'PASS:' <<<"$out")
  if [ $rc -eq 0 ]; then
    echo "  ✔ $f ($n개 단언 통과)"; PASS=$((PASS+n))
  else
    echo "  ✘ $f ($n개 통과 후 실패)"; grep -E 'ASSERTION FAILED|ERROR' <<<"$out" | head -5 | sed 's/^/      /'
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$f")
  fi
  ${VERBOSE:-false} && grep 'PASS:' <<<"$out" | sed 's/^.*PASS: /      · /'
done

# ---------------------------------------------------------------------
# 동시성 테스트: N개 psql 프로세스가 같은 시각(start_at)에 동시에 요청
# ---------------------------------------------------------------------
N=${CONCURRENCY:-30}
sync_sql() { echo "SELECT pg_sleep(greatest(0, extract(epoch FROM ('$1'::timestamptz - clock_timestamp()))));"; }
run_parallel() {  # $1 db, $2 start_at, $3 outdir, then SQL per worker via function worker_sql i
  local db=$1 at=$2 dir=$3; mkdir -p "$dir"
  for i in $(seq 1 $N); do
    ( { sync_sql "$at"; worker_sql "$i"; } | psql -X -q -t -A -d "$db" >"$dir/$i.out" 2>"$dir/$i.err" ) &
  done
  wait
}
TMP=$(mktemp -d)

echo "▶ 동시성 테스트 (동시 요청 ${N}건)"

# C1. 같은 코트·같은 시간에 N명 동시 예약 → 정확히 1건만 성공
db=fmate_t_c1; fresh_db $db
SETUP=$($PSQL -d $db -t -A -c "
  CREATE TABLE t.ctx AS SELECT t.venue('동시구장') AS court;
  SELECT t.user('c1_' || g || '@test.kr') FROM generate_series(1, $N) g;
  SELECT t.slots(court, 48, 2) FROM t.ctx;" | tail -1)
COURT=$($PSQL -d $db -t -A -c "SELECT court FROM t.ctx")
worker_sql() { echo "SELECT fn_create_reservation_hold((SELECT id FROM users WHERE email = 'c1_$1@test.kr'), $COURT, '$SETUP', '$SETUP'::timestamptz + interval '1 hour');"; }
AT=$($PSQL -d $db -t -A -c "SELECT clock_timestamp() + interval '2 seconds'")
run_parallel $db "$AT" $TMP/c1
ok=$(cat $TMP/c1/*.out | grep -cE '^[0-9]+$'); excl=$(cat $TMP/c1/*.err | grep -c 'no_double_booking')
rows=$($PSQL -d $db -t -A -c "SELECT count(*) FROM reservations WHERE status IN ('PENDING_PAYMENT','CONFIRMED')")
echo "    성공 $ok / 배제제약 거부 $excl / DB 활성 예약 $rows"
[ "$ok" -eq 1 ] && [ "$excl" -eq $((N-1)) ] && [ "$rows" -eq 1 ]; record "C1 같은 슬롯 동시 예약 ${N}건 → 1건만 성공" $?

# C2. 서로 다른 길이·시작으로 부분 겹치게 동시 예약 → 활성 예약끼리 겹침 0
db=fmate_t_c2; fresh_db $db
SETUP=$($PSQL -d $db -t -A -c "
  CREATE TABLE t.ctx AS SELECT t.venue('겹침구장') AS court;
  SELECT t.user('c2_' || g || '@test.kr') FROM generate_series(1, $N) g;
  SELECT t.slots(court, 48, 6) FROM t.ctx;" | tail -1)
COURT=$($PSQL -d $db -t -A -c "SELECT court FROM t.ctx")
worker_sql() { local st=$(( $1 % 5 )); local len=$(( ($1 % 2) + 1 )); [ $((st+len)) -gt 6 ] && len=1
  echo "SELECT fn_create_reservation_hold((SELECT id FROM users WHERE email = 'c2_$1@test.kr'), $COURT, '$SETUP'::timestamptz + interval '$st hours', '$SETUP'::timestamptz + interval '$((st+len)) hours');"; }
AT=$($PSQL -d $db -t -A -c "SELECT clock_timestamp() + interval '2 seconds'")
run_parallel $db "$AT" $TMP/c2
overlaps=$($PSQL -d $db -t -A -c "SELECT count(*) FROM reservations a JOIN reservations b ON a.id < b.id AND a.court_id = b.court_id AND a.period && b.period WHERE a.status IN ('PENDING_PAYMENT','CONFIRMED') AND b.status IN ('PENDING_PAYMENT','CONFIRMED')")
ok=$(cat $TMP/c2/*.out | grep -cE '^[0-9]+$'); unexpected=$(cat $TMP/c2/*.err | grep ERROR | grep -vc 'no_double_booking')
echo "    성공 $ok / 겹치는 활성 예약 쌍 $overlaps / 예상 밖 오류 $unexpected"
cat $TMP/c2/*.err | grep ERROR | grep -v 'no_double_booking' | sort | uniq -c | head -3 | sed 's/^/      /'
[ "$overlaps" -eq 0 ] && [ "$ok" -ge 1 ] && [ "$unexpected" -eq 0 ]; record "C2 부분 겹침 동시 예약 → 겹침 0" $?

# C3. 같은 주문 승인 요청 N건 동시 (앱 더블탭·재시도) → 승인 시작 1건
db=fmate_t_c3; fresh_db $db
$PSQL -d $db -c "
  CREATE TABLE t.ctx AS SELECT t.venue('승인구장') AS court, t.user('c3@test.kr') AS uid;
  SELECT t.slots(court, 48, 1) FROM t.ctx;
  SELECT fn_create_payment_order(uid, fn_create_reservation_hold(uid, court, date_trunc('hour', now()) + interval '48 hours', date_trunc('hour', now()) + interval '49 hours'), 'TEST', 'ord-c3') FROM t.ctx;" >/dev/null
UID3=$($PSQL -d $db -t -A -c "SELECT uid FROM t.ctx")
worker_sql() { echo "SELECT fn_payment_confirm_begin($UID3, 'ord-c3', 'pk-c3', 60000);"; }
AT=$($PSQL -d $db -t -A -c "SELECT clock_timestamp() + interval '2 seconds'")
run_parallel $db "$AT" $TMP/c3
ok=$(cat $TMP/c3/*.out | grep -cE '^[1-9][0-9]*$'); inv=$(cat $TMP/c3/*.err | grep -c 'INVALID_STATE')
echo "    승인 시작 $ok / INVALID_STATE $inv"
[ "$ok" -eq 1 ] && [ "$inv" -eq $((N-1)) ]; record "C3 같은 주문 동시 승인 ${N}건 → 1건만 진행" $?

# C4. 같은 예약의 서로 다른 주문 N건 동시 승인 → 돈이 움직이는 결제 1건
db=fmate_t_c4; fresh_db $db
$PSQL -d $db -c "
  CREATE TABLE t.ctx AS SELECT t.venue('이중결제구장') AS court, t.user('c4@test.kr') AS uid;
  SELECT t.slots(court, 48, 1) FROM t.ctx;
  CREATE TABLE t.res AS SELECT fn_create_reservation_hold(uid, court, date_trunc('hour', now()) + interval '48 hours', date_trunc('hour', now()) + interval '49 hours') AS rid FROM t.ctx;
  INSERT INTO payments (reservation_id, user_id, mode, order_id, amount)
    SELECT rid, uid, 'TEST', 'ord-c4-' || g, 60000 FROM t.res, t.ctx, generate_series(1, $N) g;" >/dev/null
UID4=$($PSQL -d $db -t -A -c "SELECT uid FROM t.ctx")
worker_sql() { echo "SELECT fn_payment_confirm_begin($UID4, 'ord-c4-$1', 'pk-c4-$1', 60000);"; }
AT=$($PSQL -d $db -t -A -c "SELECT clock_timestamp() + interval '2 seconds'")
run_parallel $db "$AT" $TMP/c4
inprog=$($PSQL -d $db -t -A -c "SELECT count(*) FROM payments WHERE status = 'IN_PROGRESS'")
dup=$(cat $TMP/c4/*.err | grep -c 'ux_payments_one_captured_per_reservation')
echo "    IN_PROGRESS $inprog / 유일 인덱스 거부 $dup"
[ "$inprog" -eq 1 ] && [ "$dup" -eq $((N-1)) ]; record "C4 한 예약에 다른 주문 ${N}건 동시 승인 → 1건만 진행" $?

# C5. 동시 환불 요청 N건 x 10,000원 (승인 60,000원) → 합계 60,000 초과 금지
db=fmate_t_c5; fresh_db $db
$PSQL -d $db -c "
  CREATE TABLE t.ctx AS SELECT t.venue('환불구장') AS court, t.user('c5@test.kr') AS uid;
  SELECT t.slots(court, 48, 1) FROM t.ctx;
  CREATE TABLE t.res AS SELECT t.confirmed(uid, court, date_trunc('hour', now()) + interval '48 hours', 1) AS rid FROM t.ctx;" >/dev/null
PAY5=$($PSQL -d $db -t -A -c "SELECT p.id FROM payments p JOIN t.res ON p.reservation_id = t.res.rid WHERE p.status = 'DONE'")
worker_sql() { echo "INSERT INTO refunds (payment_id, reservation_id, amount, reason, requested_by) SELECT id, reservation_id, 10000, 'c5', 'ADMIN' FROM payments WHERE id = $PAY5 RETURNING id;"; }
AT=$($PSQL -d $db -t -A -c "SELECT clock_timestamp() + interval '2 seconds'")
run_parallel $db "$AT" $TMP/c5
total=$($PSQL -d $db -t -A -c "SELECT COALESCE(sum(amount),0) FROM refunds WHERE payment_id = $PAY5")
cnt=$($PSQL -d $db -t -A -c "SELECT count(*) FROM refunds WHERE payment_id = $PAY5")
echo "    환불 요청 $cnt건 / 합계 $total원"
[ "$total" -eq 60000 ] && [ "$cnt" -eq 6 ]; record "C5 동시 환불 ${N}건 → 승인 금액(60,000) 초과 없음" $?

# C6. 같은 두 사용자의 채팅방 동시 생성 → 1개
db=fmate_t_c6; fresh_db $db
$PSQL -d $db -c "CREATE TABLE t.ctx AS SELECT t.user('c6a@test.kr') AS a, t.user('c6b@test.kr') AS b;" >/dev/null
A6=$($PSQL -d $db -t -A -c "SELECT a FROM t.ctx"); B6=$($PSQL -d $db -t -A -c "SELECT b FROM t.ctx")
worker_sql() { if [ $(( $1 % 2 )) -eq 0 ]; then echo "SELECT fn_open_chat($A6, $B6);"; else echo "SELECT fn_open_chat($B6, $A6);"; fi; }
AT=$($PSQL -d $db -t -A -c "SELECT clock_timestamp() + interval '2 seconds'")
run_parallel $db "$AT" $TMP/c6
rooms=$($PSQL -d $db -t -A -c "SELECT count(*) FROM chats"); distinct=$(cat $TMP/c6/*.out | grep -E '^[0-9]+$' | sort -u | wc -l)
members=$($PSQL -d $db -t -A -c "SELECT count(*) FROM chat_members")
errs=$(cat $TMP/c6/*.err | grep -c ERROR)
echo "    채팅방 $rooms개 / 응답된 방 id 종류 $distinct / 멤버 $members / 오류 $errs"
[ "$rooms" -eq 1 ] && [ "$distinct" -eq 1 ] && [ "$members" -eq 2 ] && [ "$errs" -eq 0 ]; record "C6 채팅방 동시 생성 ${N}건 → 1개" $?

# C7. 같은 사용자가 서로 다른 슬롯 N건 동시 선점 → 사용자당 3건 제한 유지
db=fmate_t_c7; fresh_db $db
SETUP=$($PSQL -d $db -t -A -c "
  CREATE TABLE t.ctx AS SELECT t.venue('사재기구장') AS court, t.user('c7@test.kr') AS uid;
  SELECT t.slots(court, 48, $N) FROM t.ctx;" | tail -1)
COURT=$($PSQL -d $db -t -A -c "SELECT court FROM t.ctx"); UID7=$($PSQL -d $db -t -A -c "SELECT uid FROM t.ctx")
worker_sql() { echo "SELECT fn_create_reservation_hold($UID7, $COURT, '$SETUP'::timestamptz + interval '$(( $1 - 1 )) hours', '$SETUP'::timestamptz + interval '$1 hours');"; }
AT=$($PSQL -d $db -t -A -c "SELECT clock_timestamp() + interval '2 seconds'")
run_parallel $db "$AT" $TMP/c7
held=$($PSQL -d $db -t -A -c "SELECT count(*) FROM reservations WHERE status = 'PENDING_PAYMENT'")
lim=$(cat $TMP/c7/*.err | grep -c 'HOLD_LIMIT'); other=$(cat $TMP/c7/*.err | grep ERROR | grep -vc 'HOLD_LIMIT')
echo "    선점 $held건 / HOLD_LIMIT $lim / 기타 오류 $other"
[ "$held" -eq 3 ] && [ "$lim" -eq $((N-3)) ] && [ "$other" -eq 0 ]; record "C7 한 사용자 동시 선점 ${N}건 → 3건 제한 유지" $?

# 정리
for d in $($PSQL -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datname LIKE 'fmate_t_%'"); do
  $PSQL -d postgres -c "DROP DATABASE $d" >/dev/null 2>&1
done
rm -rf "$TMP"

echo
echo "결과: 통과 $PASS / 실패 $FAIL"
[ $FAIL -eq 0 ] || { printf '실패 항목: %s\n' "${FAILED_NAMES[@]}"; exit 1; }
