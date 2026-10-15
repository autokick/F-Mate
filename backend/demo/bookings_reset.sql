-- 전시 전에 깨끗하게 시작하기: 공공데이터 구장(data_source = 'PARTNER_API')에 잡힌 예약·결제 기록만 지운다.
-- 구장·사진·요금·게시물·계정은 그대로 둔다. 지운 시간은 다시 예약 가능해진다.
--   docker compose cp backend/demo/bookings_reset.sql db:/tmp/bookings_reset.sql
--   docker compose exec db psql -U fmate -d fmate -f /tmp/bookings_reset.sql
BEGIN;
CREATE TEMP TABLE _r ON COMMIT DROP AS
  SELECT r.id FROM reservations r JOIN futsal_venues v ON v.id = r.venue_id WHERE v.data_source = 'PARTNER_API';
DELETE FROM refunds WHERE payment_id IN (SELECT id FROM payments WHERE reservation_id IN (SELECT id FROM _r));
DELETE FROM payment_audit_logs WHERE payment_id IN (SELECT id FROM payments WHERE reservation_id IN (SELECT id FROM _r));
DELETE FROM payments WHERE reservation_id IN (SELECT id FROM _r);
DELETE FROM reservation_status_history WHERE reservation_id IN (SELECT id FROM _r);
DELETE FROM reservations WHERE id IN (SELECT id FROM _r);
SELECT count(*) AS deleted_reservations FROM _r;
COMMIT;
