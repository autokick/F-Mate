-- 공공데이터로 넣은 구장(data_source = 'PARTNER_API')에 시연용 편의시설을 붙인다.
-- 실제 시설 정보가 아니며, 앱의 구장 상세에 "시설 정보는 시연용 예시"로 표시된다.
-- 같은 구장에는 항상 같은 결과가 나오도록 이름으로 정한다(실행할 때마다 바뀌지 않음).
--   docker compose cp backend/demo/public_futsal_facilities.sql db:/tmp/f.sql
--   docker compose exec db psql -U fmate -d fmate -f /tmp/f.sql
BEGIN;
DELETE FROM venue_facilities
 WHERE venue_id IN (SELECT id FROM futsal_venues WHERE data_source = 'PARTNER_API');
INSERT INTO venue_facilities (venue_id, facility_code)
SELECT v.id, f.code
  FROM futsal_venues v
  JOIN LATERAL (SELECT coalesce(bool_or(c.is_indoor), false) AS indoor FROM courts c WHERE c.venue_id = v.id) ci ON true
  CROSS JOIN (VALUES
      -- 코드, 실내일 때 확률(%), 실외일 때 확률(%)
      ('PARKING', 80, 70), ('RESTROOM', 95, 90), ('WATER', 60, 50), ('SHOWER', 65, 25),
      ('CHANGING_ROOM', 70, 35), ('LOCKER', 50, 20), ('BALL_RENTAL', 55, 45), ('VEST_RENTAL', 55, 45),
      ('SHOE_RENTAL', 25, 15), ('NIGHT_LIGHTING', 30, 85), ('SPECTATOR_SEATS', 20, 30), ('CAFE', 20, 10),
      ('WIFI', 35, 10)) AS f(code, p_in, p_out)
 WHERE v.data_source = 'PARTNER_API'
   AND abs(hashtext(v.name || '|' || f.code)) % 100 < CASE WHEN ci.indoor THEN f.p_in ELSE f.p_out END;
SELECT count(DISTINCT venue_id) AS venues, count(*) AS facilities
  FROM venue_facilities WHERE venue_id IN (SELECT id FROM futsal_venues WHERE data_source = 'PARTNER_API');
COMMIT;
