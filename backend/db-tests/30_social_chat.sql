-- SNS·영상·채팅 규칙
DO $$
DECLARE
  a BIGINT := t.user('sa@test.kr'); b BIGINT := t.user('sb@test.kr'); c BIGINT := t.user('sc@test.kr');
  p_pub BIGINT; p_fol BIGINT; p_priv BIGINT; vid BIGINT; vpost BIGINT; ch BIGINT; ch2 BIGINT;
  cm BIGINT; mid UUID := gen_random_uuid();
BEGIN
  INSERT INTO posts (author_id, kind, caption, visibility) VALUES (a, 'TEXT', '공개 글', 'PUBLIC') RETURNING id INTO p_pub;
  INSERT INTO posts (author_id, kind, caption, visibility) VALUES (a, 'TEXT', '팔로워 글', 'FOLLOWERS') RETURNING id INTO p_fol;
  INSERT INTO posts (author_id, kind, caption, visibility) VALUES (a, 'TEXT', '나만 보기', 'PRIVATE') RETURNING id INTO p_priv;

  -- 공개 범위
  PERFORM t.ok(can_view_post(b, p_pub), '공개 글은 누구나 열람');
  PERFORM t.ok(NOT can_view_post(b, p_fol), '팔로워 전용 글: 비팔로워 열람 불가');
  INSERT INTO follows (follower_id, followee_id) VALUES (b, a);
  PERFORM t.ok(can_view_post(b, p_fol), '팔로우 후 팔로워 전용 글 열람 가능');
  PERFORM t.ok(NOT can_view_post(b, p_priv), '나만 보기 글은 팔로워도 불가');
  PERFORM t.ok(can_view_post(a, p_priv), '작성자 본인은 열람 가능');
  UPDATE user_profiles SET is_private = true WHERE user_id = a;
  PERFORM t.ok(NOT can_view_post(c, p_pub), '비공개 계정의 공개 글: 비팔로워 열람 불가');
  INSERT INTO follows (follower_id, followee_id, status) VALUES (c, a, 'PENDING');
  PERFORM t.ok(NOT can_view_post(c, p_pub), '팔로우 요청 대기(PENDING) 상태는 열람 불가');
  UPDATE user_profiles SET is_private = false WHERE user_id = a;

  -- 좋아요·댓글 카운터
  INSERT INTO likes (user_id, post_id) VALUES (b, p_pub), (c, p_pub);
  PERFORM t.raises(format('INSERT INTO likes (user_id, post_id) VALUES (%s, %s)', b, p_pub), '23505', '같은 글 중복 좋아요 거부');
  DELETE FROM likes WHERE user_id = c AND post_id = p_pub;
  PERFORM t.ok((SELECT like_count FROM posts WHERE id = p_pub) = 1, '좋아요 카운터: +2 -1 = 1');
  INSERT INTO comments (post_id, author_id, body) VALUES (p_pub, b, '나이스 골') RETURNING id INTO cm;
  INSERT INTO comments (post_id, author_id, body, parent_id) VALUES (p_pub, a, '감사합니다', cm);
  UPDATE comments SET status = 'HIDDEN_BY_MODERATION' WHERE id = cm;
  PERFORM t.ok((SELECT comment_count FROM posts WHERE id = p_pub) = 1, '댓글 카운터: 숨김 처리 시 감소');
  PERFORM t.raises(format('INSERT INTO comments (post_id, author_id, body) VALUES (%s, %s, %L)', p_pub, b, '   '), '23514', '공백 댓글 거부');

  -- 차단
  INSERT INTO follows (follower_id, followee_id) VALUES (a, b);
  INSERT INTO blocks (blocker_id, blocked_id) VALUES (a, b);
  PERFORM t.ok(NOT EXISTS (SELECT 1 FROM follows WHERE (follower_id, followee_id) IN ((a,b),(b,a))), '차단 시 양방향 팔로우 자동 해제');
  PERFORM t.ok(NOT can_view_post(b, p_pub), '차단당한 사용자는 공개 글도 열람 불가');
  PERFORM t.raises(format('INSERT INTO follows (follower_id, followee_id) VALUES (%s, %s)', b, a), 'BLOCKED', '차단 관계 팔로우 거부');
  PERFORM t.raises(format('SELECT fn_open_chat(%s, %s)', b, a), 'BLOCKED', '차단 관계 채팅방 생성 거부');
  PERFORM t.raises(format('INSERT INTO follows (follower_id, followee_id) VALUES (%s, %s)', c, c), '23514', '자기 자신 팔로우 거부');

  -- 채팅
  ch := fn_open_chat(c, b);
  ch2 := fn_open_chat(b, c);
  PERFORM t.ok(ch = ch2, '두 사용자 사이 채팅방은 1개 (순서 무관)');
  INSERT INTO messages (chat_id, sender_id, client_message_id, body) VALUES (ch, c, mid, '내일 풋살 콜?');
  PERFORM t.raises(format('INSERT INTO messages (chat_id, sender_id, client_message_id, body) VALUES (%s, %s, %L, %L)', ch, c, mid, '내일 풋살 콜?'),
                   '23505', '재연결 후 같은 client_message_id 재전송은 중복 저장 안 됨');
  PERFORM t.raises(format('INSERT INTO messages (chat_id, sender_id, client_message_id, body) VALUES (%s, %s, %L, %L)', ch, a, gen_random_uuid(), '끼어들기'),
                   'FORBIDDEN', '채팅방 참여자가 아니면 메시지 전송 불가');
  PERFORM t.ok((SELECT last_read_message_id FROM chat_members WHERE chat_id = ch AND user_id = c)
               = (SELECT max(id) FROM messages WHERE chat_id = ch), '보낸 사람은 자동 읽음 처리');
  PERFORM t.ok((SELECT last_read_message_id FROM chat_members WHERE chat_id = ch AND user_id = b) = 0, '받는 사람은 안읽음');
  INSERT INTO blocks (blocker_id, blocked_id) VALUES (b, c);
  PERFORM t.raises(format('INSERT INTO messages (chat_id, sender_id, client_message_id, body) VALUES (%s, %s, %L, %L)', ch, c, gen_random_uuid(), '왜 답 없어'),
                   'BLOCKED', '차단 후 기존 방에서도 메시지 전송 거부');

  -- 동영상 상태 머신
  INSERT INTO posts (author_id, kind, caption, status) VALUES (c, 'VIDEO', '하이라이트 #풋살', 'PENDING_MEDIA') RETURNING id INTO vpost;
  INSERT INTO videos (owner_id, post_id, source_object_key, content_type, declared_size_bytes, upload_expires_at)
  VALUES (c, vpost, 'uploads/raw/test.mp4', 'video/mp4', 50000000, now() + interval '1 hour') RETURNING id INTO vid;
  PERFORM t.raises(format('INSERT INTO videos (owner_id, source_object_key, content_type, declared_size_bytes, upload_expires_at) VALUES (%s, %L, %L, %s, now())', c, 'k2', 'video/avi', 1),
                   '23514', '지원하지 않는 영상 포맷 거부');
  PERFORM t.raises(format('INSERT INTO videos (owner_id, source_object_key, content_type, declared_size_bytes, upload_expires_at) VALUES (%s, %L, %L, %s, now())', c, 'k3', 'video/mp4', 600000000),
                   '23514', '용량 제한(500MB) 초과 거부');
  PERFORM t.raises(format('UPDATE videos SET status = %L WHERE id = %s', 'READY', vid), 'illegal video transition', '업로드 전 READY 전환 거부');
  PERFORM t.ok(NOT can_view_post(a, vpost), '인코딩 완료 전 영상 게시물은 타인에게 비노출');
  UPDATE videos SET status = 'UPLOADED' WHERE id = vid;
  UPDATE videos SET status = 'PROCESSING' WHERE id = vid;
  PERFORM t.raises(format('UPDATE videos SET status = %L, duration_ms = 120000, hls_manifest_key = %L, thumbnail_key = %L WHERE id = %s', 'READY', 'h', 't', vid),
                   '23514', '길이 제한(90초) 초과 영상 READY 거부');
  PERFORM t.raises(format('UPDATE videos SET status = %L WHERE id = %s', 'READY', vid), '23514', 'HLS·썸네일 없이 READY 거부');
  UPDATE videos SET status = 'READY', duration_ms = 30000, hls_manifest_key = 'hls/1/index.m3u8', thumbnail_key = 'thumb/1.jpg' WHERE id = vid;
  PERFORM t.ok((SELECT status FROM posts WHERE id = vpost) = 'ACTIVE', '영상 READY → 게시물 자동 공개');
  PERFORM t.ok(can_view_post(a, vpost), '공개된 영상 게시물 타 사용자 열람 가능');
  UPDATE videos SET status = 'DELETED' WHERE id = vid;
  PERFORM t.raises(format('UPDATE videos SET status = %L WHERE id = %s', 'PROCESSING', vid), 'illegal video transition', '삭제된 영상 복구 불가');

  -- 신고 중복 방지
  INSERT INTO reports (reporter_id, target_type, target_id, reason) VALUES (b, 'POST', p_pub, 'SPAM');
  PERFORM t.raises(format('INSERT INTO reports (reporter_id, target_type, target_id, reason) VALUES (%s, %L, %s, %L)', b, 'POST', p_pub, 'HATE'),
                   '23505', '처리 대기 중인 같은 대상 중복 신고 거부');
END $$;
