-- 계정·탈퇴·관리자 감사 로그
DO $$
DECLARE
  u BIGINT := t.user('Leaver@Test.kr'); f BIGINT := t.user('friend@test.kr'); adm BIGINT := t.user('admin@test.kr');
  c BIGINT := t.venue('탈퇴구장'); s TIMESTAMPTZ; r BIGINT; p BIGINT; ref BIGINT; u_new BIGINT;
BEGIN
  -- 이메일 대소문자 무시 유일
  PERFORM t.raises('SELECT t.user(''leaver@test.kr'')', '23505', '이메일 대소문자만 다른 중복 가입 거부');
  PERFORM t.raises(format('UPDATE user_profiles SET nickname = %L WHERE user_id = %s', 'a b!', u), '23514', '닉네임 형식 검증');

  INSERT INTO posts (author_id, kind, caption) VALUES (u, 'TEXT', '탈퇴 예정') RETURNING id INTO p;
  INSERT INTO follows (follower_id, followee_id) VALUES (f, u);
  INSERT INTO likes (user_id, post_id) VALUES (f, p);
  INSERT INTO device_tokens (user_id, fcm_token, platform) VALUES (u, 'fcm-xyz', 'ANDROID');
  INSERT INTO refresh_tokens (user_id, family_id, token_hash, expires_at)
    VALUES (u, gen_random_uuid(), sha256('rt'::bytea), now() + interval '30 days');

  -- 확정된 미래 예약이 있으면 탈퇴 불가
  s := t.slots(c, 100, 1);
  r := t.confirmed(u, c, s, 1);
  PERFORM t.raises(format('SELECT fn_delete_account(%s)', u), 'HAS_ACTIVE_RESERVATIONS', '진행 중 예약이 있으면 탈퇴 거부');
  ref := fn_cancel_reservation(r, 'USER', u, '탈퇴');
  PERFORM t.raises(format('SELECT fn_delete_account(%s)', u), 'HAS_PENDING_REFUNDS', '환불 처리 중이면 탈퇴 거부');
  PERFORM fn_refund_result(ref, true, 'tx', NULL, NULL);

  PERFORM fn_delete_account(u);
  PERFORM t.ok((SELECT email IS NULL AND password_hash IS NULL AND status = 'DELETED' FROM users WHERE id = u), '탈퇴: 이메일·비밀번호 해시 삭제');
  PERFORM t.ok(NOT EXISTS (SELECT 1 FROM user_profiles WHERE user_id = u), '탈퇴: 프로필 삭제');
  PERFORM t.ok(NOT EXISTS (SELECT 1 FROM posts WHERE author_id = u), '탈퇴: 게시물 삭제');
  PERFORM t.ok(NOT EXISTS (SELECT 1 FROM follows WHERE followee_id = u), '탈퇴: 팔로우 관계 삭제');
  PERFORM t.ok(NOT EXISTS (SELECT 1 FROM device_tokens WHERE user_id = u), '탈퇴: 푸시 토큰 삭제');
  PERFORM t.ok(NOT EXISTS (SELECT 1 FROM refresh_tokens WHERE user_id = u AND revoked_at IS NULL), '탈퇴: 모든 세션 폐기');
  PERFORM t.ok(EXISTS (SELECT 1 FROM payments WHERE reservation_id = r), '탈퇴 후에도 결제 기록은 보존 (법정 보존 대상)');
  u_new := t.user('leaver@test.kr');
  PERFORM t.ok(u_new <> u, '탈퇴한 이메일로 재가입 가능 (새 계정)');
  PERFORM t.raises(format('SELECT fn_delete_account(%s)', u), 'INVALID_STATE', '이미 탈퇴한 계정 재탈퇴 거부');

  -- 관리자 감사 로그: 추가 전용
  INSERT INTO admin_audit_logs (actor_id, actor_role, action, target_type, target_id, reason)
    VALUES (adm, 'ADMIN', 'VENUE_VERIFY', 'VENUE', 1, '사업자등록증 확인');
  PERFORM t.raises('UPDATE admin_audit_logs SET reason = ''조작''', 'append-only', '감사 로그 수정 불가');
  PERFORM t.raises('DELETE FROM admin_audit_logs', 'append-only', '감사 로그 삭제 불가');
END $$;
