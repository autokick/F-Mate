-- F-Mate 시연 데이터 지우기 (demo_seed.sql 로 넣은 것만)
--   docker compose cp backend/demo/demo_reset.sql db:/tmp/demo_reset.sql
--   docker compose exec db psql -U fmate -d fmate -f /tmp/demo_reset.sql
-- 시연 중 생긴 예약·결제가 있으면 함께 지워진다. 실제 사용자 데이터는 건드리지 않는다.

BEGIN;

-- 시연 구장의 예약·결제 기록 (구장보다 먼저)
DELETE FROM refunds WHERE payment_id IN (
  SELECT p.id FROM payments p JOIN reservations r ON r.id = p.reservation_id
   JOIN futsal_venues v ON v.id = r.venue_id WHERE v.name LIKE '(시연용)%');
DELETE FROM payment_audit_logs WHERE payment_id IN (
  SELECT p.id FROM payments p JOIN reservations r ON r.id = p.reservation_id
   JOIN futsal_venues v ON v.id = r.venue_id WHERE v.name LIKE '(시연용)%');
DELETE FROM payments WHERE reservation_id IN (
  SELECT r.id FROM reservations r JOIN futsal_venues v ON v.id = r.venue_id WHERE v.name LIKE '(시연용)%');
DELETE FROM reservation_status_history WHERE reservation_id IN (
  SELECT r.id FROM reservations r JOIN futsal_venues v ON v.id = r.venue_id WHERE v.name LIKE '(시연용)%');
DELETE FROM reservations WHERE venue_id IN (SELECT id FROM futsal_venues WHERE name LIKE '(시연용)%');

DELETE FROM futsal_venues WHERE name LIKE '(시연용)%';
-- 관리 기록(감사 로그)은 수정·삭제할 수 없게 설계되어 있어서, 그 기록을 남긴 시연 계정은 남겨 둔다.
-- (다시 demo_seed.sql 을 실행하면 남은 계정을 그대로 다시 쓴다)
DELETE FROM users WHERE email LIKE '%@fmate.demo'
   AND id NOT IN (SELECT actor_id FROM admin_audit_logs);

COMMIT;
