-- 공공데이터로 넣은 실제 풋살장(data_source = 'PARTNER_API')과 그 구장에서 생긴 시연 예약·결제를 지운다.
--   docker compose cp backend/demo/public_futsal_reset.sql db:/tmp/public_futsal_reset.sql
--   docker compose exec db psql -U fmate -d fmate -f /tmp/public_futsal_reset.sql
BEGIN;
DELETE FROM refunds WHERE payment_id IN (SELECT id FROM payments WHERE reservation_id IN (SELECT id FROM reservations WHERE venue_id IN (SELECT id FROM futsal_venues WHERE data_source = 'PARTNER_API')));
DELETE FROM payment_audit_logs WHERE payment_id IN (SELECT id FROM payments WHERE reservation_id IN (SELECT id FROM reservations WHERE venue_id IN (SELECT id FROM futsal_venues WHERE data_source = 'PARTNER_API')));
DELETE FROM payments WHERE reservation_id IN (SELECT id FROM reservations WHERE venue_id IN (SELECT id FROM futsal_venues WHERE data_source = 'PARTNER_API'));
DELETE FROM reservation_status_history WHERE reservation_id IN (SELECT id FROM reservations WHERE venue_id IN (SELECT id FROM futsal_venues WHERE data_source = 'PARTNER_API'));
DELETE FROM reservations WHERE venue_id IN (SELECT id FROM futsal_venues WHERE data_source = 'PARTNER_API');
DELETE FROM futsal_venues WHERE data_source = 'PARTNER_API';
COMMIT;
