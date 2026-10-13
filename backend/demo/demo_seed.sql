-- =====================================================================
-- F-Mate 시연(전시)용 데이터
--   실제 서비스 계정이 아니다. 시연 계정은 @fmate.demo 주소를 쓴다.
--   여러 번 실행해도 한 번만 들어간다 (이미 있으면 건너뜀).
--   지우기: demo_reset.sql
--
-- 실행 (저장소 루트 C:\dev\fmate 에서, 서버가 한 번 이상 켜져 DB 구조가 만들어진 뒤):
--   docker compose cp backend/demo/demo_seed.sql db:/tmp/demo_seed.sql
--   docker compose exec db psql -U fmate -d fmate -f /tmp/demo_seed.sql
--
-- 들어가는 것: 구장 운영자·관리자 계정 2개만.
-- 구장은 공공데이터의 실제 풋살장을 넣는다 → import_public_futsal.py (README 참고)
-- SNS 게시물·영상·팔로우는 넣지 않는다 → 팀원이 직접 만든 계정으로 앱에서 올린다.
--
-- 시연 계정 (비밀번호 모두 demo1234)
--   owner@fmate.demo  구장사장님   구장 운영자 (앱에서 입점 신청 흐름 시연용)
--   admin@fmate.demo  운영관리자   관리자
-- =====================================================================

DO $demo$
DECLARE
  -- 'demo1234' 의 BCrypt 해시 (서버의 BCryptPasswordEncoder 와 같은 형식)
  pw CONSTANT TEXT := '$2a$10$1iCM4EehKmLR3p7Z0h1Bye.i.Y/LOdYoG0ZOGDKXH/VH9bl.yFoMi';
  u_admin BIGINT; u_owner BIGINT;
  c BIGINT;
  r RECORD;
BEGIN

  -- ---------------------------------------------------------------- 계정
  FOR r IN SELECT * FROM (VALUES
      ('admin@fmate.demo', 'ADMIN',          '운영관리자', '시연용 관리자 계정',                        '11680', 'ANY'),
      ('owner@fmate.demo', 'VENUE_OPERATOR', '구장사장님', '시연용 구장 운영자 계정',                   '41590', 'ANY')
    ) AS t(email, role, nick, bio, region, pos)
  LOOP
    -- 관리 기록(감사 로그)이 남아 지워지지 않은 시연 계정은 다시 쓴다
    SELECT id INTO c FROM users WHERE email = r.email;
    IF NOT FOUND THEN
      INSERT INTO users (email, password_hash, email_verified_at, role)
      VALUES (r.email, pw, now(), r.role) RETURNING id INTO c;
      INSERT INTO user_profiles (user_id, nickname, bio, region_code, preferred_position)
      VALUES (c, r.nick, r.bio, r.region, r.pos);
      INSERT INTO consents (user_id, consent_type, version, agreed)
      SELECT c, ct, '2026-10', true FROM unnest(ARRAY['AGE_14','TERMS','PRIVACY','LOCATION']) AS ct;
    END IF;
    CASE r.email
      WHEN 'admin@fmate.demo' THEN u_admin := c;
      ELSE u_owner := c;
    END CASE;
  END LOOP;

  RAISE NOTICE '시연 데이터를 넣었습니다: 시연용 운영자·관리자 계정 (이미 있으면 그대로 둠)';
END
$demo$;
