# DB 테스트 실행 기록

- 실행 시각: 2026-10-10 21:45 KST
- 환경: PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1) on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0, 64-bit
- 명령: `VERBOSE=true CONCURRENCY=30 ./run.sh`

```
▶ 마이그레이션 적용 (빈 DB → V1..V5)
  ✔ V1__accounts.sql
  ✔ V2__venues_reservations.sql
  ✔ V3__payments.sql
  ✔ V4__social_video.sql
  ✔ V5__chat_notifications_moderation.sql
▶ 규칙 테스트 (단일 세션)
  ✔ 10_reservation_rules.sql (29개 단언 통과)
      · 2시간 선점: PENDING_PAYMENT, 금액은 서버가 슬롯 합으로 계산(120,000)
      · 부분 겹침 예약은 배제 제약으로 거부 (got 23P01 conflicting key value violates exclusion constraint "no_double_booking")
      · 완전 포함 예약 거부 (got 23P01 conflicting key value violates exclusion constraint "no_double_booking")
      · 끝 시각에 맞닿은 다음 시간대 예약은 허용 ([) 구간)
      · 같은 시간이라도 다른 코트는 허용
      · 슬롯 경계에 맞지 않는 시간 거부 (got P0001 SLOT_UNAVAILABLE)
      · 운영 슬롯 밖까지 걸친 예약 거부 (하드코딩 시간 없음) (got P0001 SLOT_UNAVAILABLE)
      · 지난 시간 예약 거부 (got P0001 SLOT_UNAVAILABLE)
      · 운영자가 닫은 슬롯 거부 (got P0001 SLOT_UNAVAILABLE)
      · 구장 전체 휴무 구간 거부 (got P0001 SLOT_UNAVAILABLE)
      · 이메일 미인증 계정 예약 불가 (got P0001 ACCOUNT_NOT_ALLOWED)
      · 관리자 검증 전 구장 예약 불가 (got P0001 VENUE_NOT_BOOKABLE)
      · 결제 대기 선점 4번째 거부 (got P0001 HOLD_LIMIT)
      · 만료된 선점은 같은 구간 신규 예약 시 EXPIRED 로 정리
      · 만료 선점 구간에 신규 예약 성공
      · 결제 없이 CONFIRMED 전환 거부 (got 23514 cannot confirm reservation 8 without a DONE payment of the full amount)
      · EXPIRED → PENDING_PAYMENT 역전이 거부 (got 23514 illegal reservation transition EXPIRED -> PENDING_PAYMENT)
      · 예약 금액 사후 변경 거부 (got 23514 reservation core fields are immutable)
      · 처음부터 CONFIRMED 로 삽입 거부 (got 23514 reservation must start as PENDING_PAYMENT)
      · 상태 이력: 생성 + 만료 2건 기록
      · 조회: 선점된 슬롯은 예약 불가로 표시
      · 조회: 닫힌 슬롯은 예약 불가로 표시
      · 조회: 만료 선점이 풀린 슬롯은 예약 가능으로 표시
      · 7일 x 9슬롯 = 63개 생성
      · 재실행 시 중복 생성 없음 (멱등)
      · 첫 슬롯은 한국시간 06:00
      · 18시 이후 슬롯은 야간 요금
      · 같은 요일 운영시간 구간 겹침 거부 (got 23P01 conflicting key value violates exclusion constraint "operating_hours_court_id_day_of_week_int4range_excl")
      · 슬롯 길이로 나누어 떨어지지 않는 운영시간 거부 (got 23514 new row for relation "operating_hours" violates check constraint "operating_hours_check1")
  ✔ 20_payment_refund.sql (38개 단언 통과)
      · 클라이언트가 보낸 금액이 다르면 승인 시작 거부 (AMOUNT_MISMATCH)
      · 변조 주문은 ABORTED
      · 예약은 결제 대기 유지 (재시도 가능)
      · 변조 시도 감사 로그 기록
      · 타인 예약 주문 생성 거부 (got P0001 FORBIDDEN)
      · 예약 금액과 다른 결제 레코드 삽입 거부 (DB 레벨) (got 23514 payment amount 1 does not match reservation amount 60000)
      · 같은 주문 승인 이중 시작 거부 (got P0001 INVALID_STATE)
      · 승인 진행 중 취소 거부 (got P0001 INVALID_STATE)
      · 승인 진행(IN_PROGRESS) 중인 선점은 만료 배치가 해제하지 않음
      · 승인 성공 → 예약 확정
      · 승인 결과 중복 수신(응답+웹훅) 멱등 처리
      · 확정 예약에 새 결제 레코드 삽입 거부 (DB 트리거) (got 23514 INVALID_STATE: reservation 1 is CONFIRMED)
      · 결제 금액 사후 변경 거부 (got 23514 payment core fields are immutable)
      · DONE → READY 역전이 거부 (got 23514 illegal payment transition DONE -> READY)
      · 이용 72시간 이전 취소 → 전액(60,000) 환불 요청
      · 취소 즉시 CANCELED (슬롯 반환)
      · 취소된 시간대는 다른 사용자가 바로 예약 가능
      · 환불 실패는 REQUESTED 유지(같은 멱등키로 재시도)
      · 환불 성공 반영
      · 전액 환불 → 결제 CANCELED, 잔액 0
      · 환불 완료 → 예약 REFUNDED
      · 환불 결과 중복 수신 멱등
      · 이미 전액 환불된 결제 추가 환불 거부 (got 23514 payment 3 is not refundable in status CANCELED)
      · 24~72시간 전 취소 → 50%(30,000) 환불
      · 부분 환불 → PARTIAL_CANCELED, 잔액 30,000
      · 환불 합계가 승인 금액 초과 시 거부 (got 23514 refund total 60001 exceeds approved amount 60000)
      · 잔액 추가 환불 → CANCELED
      · 24시간 이내 취소 → 환불 없이 CANCELED
      · 해당 구장 운영자가 아니면 취소 불가 (got P0001 FORBIDDEN)
      · 타인 예약 취소 불가 (got P0001 FORBIDDEN)
      · 운영자 사정 취소 → 전액 환불
      · PG 승인 금액 ≠ 예약 금액 → 확정하지 않고 보상 필요 반환
      · 예약은 확정되지 않음
      · 보상 환불 요청 멱등 (중복 생성 없음)
      · 보상 환불 = 승인 금액 전액
      · 보상 환불 후 선점은 만료로 정리
      · 경계값: 정확히 24시간 전 → 50%
      · 환불액은 원 단위 내림
  ✔ 30_social_chat.sql (32개 단언 통과)
      · 공개 글은 누구나 열람
      · 팔로워 전용 글: 비팔로워 열람 불가
      · 팔로우 후 팔로워 전용 글 열람 가능
      · 나만 보기 글은 팔로워도 불가
      · 작성자 본인은 열람 가능
      · 비공개 계정의 공개 글: 비팔로워 열람 불가
      · 팔로우 요청 대기(PENDING) 상태는 열람 불가
      · 같은 글 중복 좋아요 거부 (got 23505 duplicate key value violates unique constraint "likes_pkey")
      · 좋아요 카운터: +2 -1 = 1
      · 댓글 카운터: 숨김 처리 시 감소
      · 공백 댓글 거부 (got 23514 new row for relation "comments" violates check constraint "comments_body_check")
      · 차단 시 양방향 팔로우 자동 해제
      · 차단당한 사용자는 공개 글도 열람 불가
      · 차단 관계 팔로우 거부 (got 23514 BLOCKED)
      · 차단 관계 채팅방 생성 거부 (got P0001 BLOCKED)
      · 자기 자신 팔로우 거부 (got 23514 new row for relation "follows" violates check constraint "follows_check")
      · 두 사용자 사이 채팅방은 1개 (순서 무관)
      · 재연결 후 같은 client_message_id 재전송은 중복 저장 안 됨 (got 23505 duplicate key value violates unique constraint "messages_sender_id_client_message_id_key")
      · 채팅방 참여자가 아니면 메시지 전송 불가 (got 23514 FORBIDDEN)
      · 보낸 사람은 자동 읽음 처리
      · 받는 사람은 안읽음
      · 차단 후 기존 방에서도 메시지 전송 거부 (got 23514 BLOCKED)
      · 지원하지 않는 영상 포맷 거부 (got 23514 new row for relation "videos" violates check constraint "videos_content_type_check")
      · 용량 제한(500MB) 초과 거부 (got 23514 new row for relation "videos" violates check constraint "videos_declared_size_bytes_check")
      · 업로드 전 READY 전환 거부 (got 23514 illegal video transition UPLOAD_PENDING -> READY)
      · 인코딩 완료 전 영상 게시물은 타인에게 비노출
      · 길이 제한(90초) 초과 영상 READY 거부 (got 23514 new row for relation "videos" violates check constraint "videos_duration_ms_check")
      · HLS·썸네일 없이 READY 거부 (got 23514 new row for relation "videos" violates check constraint "videos_check")
      · 영상 READY → 게시물 자동 공개
      · 공개된 영상 게시물 타 사용자 열람 가능
      · 삭제된 영상 복구 불가 (got 23514 illegal video transition DELETED -> PROCESSING)
      · 처리 대기 중인 같은 대상 중복 신고 거부 (got 23505 duplicate key value violates unique constraint "ux_reports_open")
  ✔ 40_account_admin.sql (15개 단언 통과)
      · 이메일 대소문자만 다른 중복 가입 거부 (got 23505 duplicate key value violates unique constraint "ux_users_email")
      · 닉네임 형식 검증 (got 23514 new row for relation "user_profiles" violates check constraint "nickname_format")
      · 진행 중 예약이 있으면 탈퇴 거부 (got P0001 HAS_ACTIVE_RESERVATIONS)
      · 환불 처리 중이면 탈퇴 거부 (got P0001 HAS_PENDING_REFUNDS)
      · 탈퇴: 이메일·비밀번호 해시 삭제
      · 탈퇴: 프로필 삭제
      · 탈퇴: 게시물 삭제
      · 탈퇴: 팔로우 관계 삭제
      · 탈퇴: 푸시 토큰 삭제
      · 탈퇴: 모든 세션 폐기
      · 탈퇴 후에도 결제 기록은 보존 (법정 보존 대상)
      · 탈퇴한 이메일로 재가입 가능 (새 계정)
      · 이미 탈퇴한 계정 재탈퇴 거부 (got P0001 INVALID_STATE)
      · 감사 로그 수정 불가 (got 42501 admin_audit_logs is append-only)
      · 감사 로그 삭제 불가 (got 42501 admin_audit_logs is append-only)
▶ 동시성 테스트 (동시 요청 30건)
    성공 1 / 배제제약 거부 29 / DB 활성 예약 1
  ✔ C1 같은 슬롯 동시 예약 30건 → 1건만 성공
    성공 5 / 겹치는 활성 예약 쌍 0 / 예상 밖 오류 0
  ✔ C2 부분 겹침 동시 예약 → 겹침 0
    승인 시작 1 / INVALID_STATE 29
  ✔ C3 같은 주문 동시 승인 30건 → 1건만 진행
    IN_PROGRESS 1 / 유일 인덱스 거부 29
  ✔ C4 한 예약에 다른 주문 30건 동시 승인 → 1건만 진행
    환불 요청 6건 / 합계 60000원
  ✔ C5 동시 환불 30건 → 승인 금액(60,000) 초과 없음
    채팅방 1개 / 응답된 방 id 종류 1 / 멤버 2 / 오류 0
  ✔ C6 채팅방 동시 생성 30건 → 1개
    선점 3건 / HOLD_LIMIT 27 / 기타 오류 0
  ✔ C7 한 사용자 동시 선점 30건 → 3건 제한 유지

결과: 통과 121 / 실패 0
```
