# 02. API 명세 v1.0

> 아래 엔드포인트 표는 **서버 코드(`*Controller.java`)에서 자동 추출**했다 (총 120개). 오류 코드 표도 `ErrorMessages.java`에서 뽑았다.
> 앱(`app/lib/core/repos.dart`)이 호출하는 경로 95개를 서버 경로와 대조해 **불일치 0건**, 앱이 읽는 JSON 필드 195개가 서버 코드에 모두 존재함을 스크립트로 확인했다(2026-10-10).

## 공통 규격

- **기본 주소**: `https://<서버>` (개발: `http://localhost:8080`, 안드로이드 에뮬레이터에서 `http://10.0.2.2:8080`)
- **인증**: `Authorization: Bearer <액세스 토큰>` (HS256 JWT, 15분). 만료 시 `POST /api/v1/auth/refresh` 로 리프레시 토큰(30일, 1회용 회전) 교환. 이미 쓴 리프레시 토큰이 다시 오면 그 계열 전체를 폐기(`TOKEN_REUSED`).
  비밀번호 변경·탈퇴·제재 시 토큰 버전이 올라가 기존 액세스 토큰도 즉시 무효.
- **권한**: `공개` 비로그인 허용 · `회원` 로그인 필요(일부는 서비스에서 이메일 인증·운영자·작성자 여부를 추가 확인) · `MOD+` 모더레이터 이상(결제·구장 승인·권한 변경은 ADMIN만)
- **멱등키(★)**: `Idempotency-Key: <uuid>` 헤더 필수. 같은 사용자·엔드포인트·키로 다시 보내면 첫 결과를 그대로 돌려준다. 같은 키에 다른 본문 → 422 `IDEMPOTENCY_CONFLICT`, 처리 중 재요청 → 409 `IDEMPOTENCY_IN_PROGRESS`.
- **오류 형식** (RFC 9457 기반):
  ```json
  {"type":"https://fmate.app/errors/slot-taken","title":"방금 다른 분이 예약한 시간이에요","status":409,"code":"SLOT_TAKEN","requestId":"a1b2…","fieldErrors":null}
  ```
  앱은 `code`로 분기하고 `title`은 그대로 보여줘도 된다. `requestId`는 응답 헤더 `X-Request-Id`와 같고, 관리자 화면의 오류 로그에서 찾을 수 있다.
- **페이지**: 구장 검색은 `?page=0&size=20` → `{items, page, hasNext}`. 피드·댓글·알림·채팅은 커서 방식 `?cursor=<id>&limit=20` → `{items, nextCursor}` (`nextCursor`가 없으면 끝).
- **시간**: ISO-8601 (`2026-10-12T19:00:00+09:00`). 예약 날짜 파라미터는 한국시간 기준 `YYYY-MM-DD`.
- **금액**: 원 단위 정수. 결제 금액은 항상 서버가 슬롯 가격으로 계산하며 앱이 보낸 금액은 쓰지 않는다.
- **기능 상태**: `GET /api/v1/config` 의 `features`(payment·media·video·push·maps·email·socialProviders)로 외부 키가 설정된 기능만 켠다. 키가 없으면 앱은 "준비 중"을 표시한다.

## 핵심 흐름

**예약 → 결제**
1. `GET /api/v1/venues/{id}/availability?date=` → 슬롯 목록
2. `POST /api/v1/reservations` ★ `{courtId, startsAt, endsAt}` (연속 슬롯 구간) → `PENDING_PAYMENT` 상태 예약 (결제 대기 선점, 사용자당 동시 3건). 이미 잡힌 시간은 DB 배제 제약으로 거부 → 409 `SLOT_TAKEN`
3. `POST /api/v1/payments/orders` ★ `{reservationId}` → `{orderId, amount, orderName, checkoutUrl, …}`
4. 앱이 `checkoutUrl`(서버의 `/pay/checkout/{orderId}`)을 WebView로 열고(Authorization 헤더 포함), 토스 결제창 → `/pay/success` 에서 **서버가 금액 대조 후 토스 승인 API 호출** → 예약 `CONFIRMED`
5. 앱은 `GET /api/v1/payments/orders/{orderId}` 로 최종 상태 확인. 승인 응답이 끊긴 경우 서버 대사 작업이 토스 조회 API로 확정/보상취소한다.

**취소·환불**: `POST /api/v1/reservations/{publicId}/cancel` ★ → 구장 취소 정책(시간대별 환불율)으로 금액 계산 → 환불 요청 생성 → 백그라운드에서 토스 취소 API 호출(재시도·백오프), 결과는 알림으로.

**업로드**: `POST /api/v1/media/upload-urls` `{purpose, files:[{contentType,sizeBytes}]}` → presigned PUT URL → 앱이 스토리지로 직접 업로드 → 게시물/숏폼 생성 시 받은 `key`를 전달. 서버가 객체 존재·크기를 다시 확인한다.

**숏폼**: `POST /api/v1/videos/uploads` → 받은 URL로 업로드 → `POST /api/v1/videos/{id}/complete` → 인코더(ffmpeg)가 HLS·썸네일 생성 → `READY`.

## WebSocket — `/ws/chat`

연결 후 10초 안에 인증 메시지를 보내야 한다 (URL 쿼리에 토큰을 싣지 않아 로그에 남지 않음).

| 방향 | 메시지 |
|---|---|
| 앱 → 서버 | `{"type":"auth","token":"<액세스 토큰>"}` |
| 앱 → 서버 | `{"type":"send","chatId":1,"clientMessageId":"<uuid>","body":"..."}` (clientMessageId로 중복 전송 방지) |
| 앱 → 서버 | `{"type":"read","chatId":1,"messageId":10}` / `{"type":"ping"}` |
| 서버 → 앱 | `{"type":"ready"}` / `{"type":"ack","clientMessageId":"..","message":{..}}` / `{"type":"error","code":"..","clientMessageId":".."}` |
| 서버 → 앱 | `{"type":"message","message":{..}}` / `{"type":"read","chatId":..,"userId":..,"messageId":..}` / `{"type":"pong"}` |

소켓이 끊겨도 `GET /api/v1/chats/{id}/messages` 와 `POST /api/v1/chats/{id}/messages`(REST)로 같은 기능을 쓸 수 있고, 상대가 오프라인이면 FCM 푸시(설정 시)와 앱 내 알림으로 전달된다.

## 엔드포인트 전체 목록

### 실제 풋살장 검색 — `PlaceController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| GET | `/api/v1/places/futsal-nearby` | 공개 |  |

`?lat=&lng=&radiusM=10000&page=1` 또는 `?area=강남`. 카카오 로컬 API를 요청마다 실시간 조회해 그대로 전달하며 저장하지 않는다(카카오 정책).
응답 `{items:[{id,name,category,phone,roadAddress,address,lat,lng,distanceM,placeUrl}], page, hasNext, attribution}`. 앱은 `attribution`("장소 정보 제공: 카카오")을 목록 아래 표시한다.
키 미설정 503 `PLACES_NOT_CONFIGURED`, 카카오 오류 503 `PLACES_UNAVAILABLE`. IP당 분당 60회.

### 관리자 — `AdminController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| GET | `/api/v1/admin/dashboard` | MOD+ |  |
| GET | `/api/v1/admin/users` | MOD+ |  |
| GET | `/api/v1/admin/users/{id}` | MOD+ |  |
| POST | `/api/v1/admin/users/{id}/sanctions` | MOD+ |  |
| POST | `/api/v1/admin/users/{id}/sanctions/lift` | MOD+ |  |
| POST | `/api/v1/admin/users/{id}/role` | MOD+ |  |
| GET | `/api/v1/admin/venues` | MOD+ |  |
| GET | `/api/v1/admin/venues/{id}` | MOD+ |  |
| POST | `/api/v1/admin/venues/{id}/decision` | MOD+ |  |
| GET | `/api/v1/admin/reservations` | MOD+ |  |
| POST | `/api/v1/admin/reservations/{publicId}/cancel` | MOD+ |  |
| GET | `/api/v1/admin/payments` | MOD+ |  |
| GET | `/api/v1/admin/payments/{orderId}` | MOD+ |  |
| POST | `/api/v1/admin/payments/{orderId}/reconcile` | MOD+ |  |
| POST | `/api/v1/admin/refunds/{id}/retry` | MOD+ |  |
| GET | `/api/v1/admin/reports` | MOD+ |  |
| POST | `/api/v1/admin/reports/{targetType}/{targetId}/resolve` | MOD+ |  |
| GET | `/api/v1/admin/audit-logs` | MOD+ |  |
| GET | `/api/v1/admin/error-logs` | MOD+ |  |

### 인증·계정 — `AuthController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| POST | `/api/v1/auth/signup` | 공개 |  |
| POST | `/api/v1/auth/login` | 공개 |  |
| POST | `/api/v1/auth/refresh` | 공개 |  |
| POST | `/api/v1/auth/logout` | 회원 |  |
| POST | `/api/v1/auth/email/verify` | 회원 |  |
| POST | `/api/v1/auth/email/resend` | 회원 |  |
| POST | `/api/v1/auth/password/reset-request` | 공개 |  |
| POST | `/api/v1/auth/password/reset` | 공개 |  |
| PUT | `/api/v1/auth/password` | 회원 |  |
| POST | `/api/v1/auth/social/{provider}` | 공개 |  |

### 채팅 — `ChatController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| POST | `/api/v1/chats` | 회원 |  |
| GET | `/api/v1/chats` | 회원 |  |
| GET | `/api/v1/chats/{id}` | 회원 |  |
| GET | `/api/v1/chats/{id}/messages` | 회원 |  |
| POST | `/api/v1/chats/{id}/messages` | 회원 |  |
| POST | `/api/v1/chats/{id}/read` | 회원 |  |
| POST | `/api/v1/chats/{id}/hide` | 회원 |  |
| POST | `/api/v1/chats/{id}/mute` | 회원 |  |

### 앱 설정 — `PublicConfigController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| GET | `/api/v1/config` | 공개 |  |

### 업로드 — `MediaController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| POST | `/api/v1/media/upload-urls` | 회원 |  |

### 알림 — `NotificationController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| GET | `/api/v1/notifications` | 회원 |  |
| GET | `/api/v1/notifications/unread-count` | 회원 |  |
| POST | `/api/v1/notifications/read` | 회원 |  |

### 결제창 페이지 (서버 렌더링) — `PayPageController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| GET | `/pay/checkout/{orderId}` | 회원 |  |
| GET | `/pay/success` | 공개(서버 재검증) |  |
| GET | `/pay/fail` | 공개(서버 재검증) |  |

### 결제 — `PaymentController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| POST | `/api/v1/payments/orders` | 회원 | ★ |
| POST | `/api/v1/payments/confirm` | 회원 | ★ |
| GET | `/api/v1/payments/{orderId}` | 회원 |  |
| POST | `/api/v1/payments/{orderId}/reconcile` | 회원 |  |
| POST | `/api/v1/webhooks/toss` | 공개(서버 재검증) |  |

### 예약 — `ReservationController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| POST | `/api/v1/reservations` | 회원 | ★ |
| GET | `/api/v1/reservations` | 회원 |  |
| GET | `/api/v1/reservations/{publicId}` | 회원 |  |
| POST | `/api/v1/reservations/{publicId}/cancel` | 회원 | ★ |

### SNS — `SocialController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| GET | `/api/v1/feed` | 회원 |  |
| GET | `/api/v1/shorts` | 회원 |  |
| GET | `/api/v1/users/{id}/posts` | 회원 |  |
| GET | `/api/v1/me/saved` | 회원 |  |
| GET | `/api/v1/hashtags/{tag}/posts` | 회원 |  |
| POST | `/api/v1/posts` | 회원 | ★ |
| GET | `/api/v1/posts/{id}` | 회원 |  |
| PATCH | `/api/v1/posts/{id}` | 회원 |  |
| DELETE | `/api/v1/posts/{id}` | 회원 |  |
| PUT | `/api/v1/posts/{id}/like` | 회원 |  |
| DELETE | `/api/v1/posts/{id}/like` | 회원 |  |
| PUT | `/api/v1/posts/{id}/save` | 회원 |  |
| DELETE | `/api/v1/posts/{id}/save` | 회원 |  |
| GET | `/api/v1/posts/{id}/comments` | 회원 |  |
| POST | `/api/v1/posts/{id}/comments` | 회원 |  |
| DELETE | `/api/v1/comments/{id}` | 회원 |  |
| PUT | `/api/v1/users/{id}/follow` | 회원 |  |
| DELETE | `/api/v1/users/{id}/follow` | 회원 |  |
| GET | `/api/v1/users/{id}/followers` | 회원 |  |
| GET | `/api/v1/users/{id}/following` | 회원 |  |
| GET | `/api/v1/me/follow-requests` | 회원 |  |
| POST | `/api/v1/me/follow-requests/{userId}/accept` | 회원 |  |
| POST | `/api/v1/me/follow-requests/{userId}/reject` | 회원 |  |
| DELETE | `/api/v1/me/followers/{userId}` | 회원 |  |
| PUT | `/api/v1/users/{id}/block` | 회원 |  |
| DELETE | `/api/v1/users/{id}/block` | 회원 |  |
| GET | `/api/v1/me/blocks` | 회원 |  |
| POST | `/api/v1/reports` | 회원 |  |

### 내 정보·설정 — `MeController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| GET | `/api/v1/me` | 회원 |  |
| PATCH | `/api/v1/me/profile` | 회원 |  |
| PUT | `/api/v1/me/avatar` | 회원 |  |
| POST | `/api/v1/me/consents` | 회원 |  |
| GET | `/api/v1/me/notification-settings` | 회원 |  |
| PUT | `/api/v1/me/notification-settings` | 회원 |  |
| POST | `/api/v1/me/devices` | 회원 |  |
| POST | `/api/v1/me/devices/remove` | 회원 |  |
| POST | `/api/v1/me/delete` | 회원 |  |
| GET | `/api/v1/users/{id}` | 회원 |  |
| GET | `/api/v1/users/search` | 회원 |  |

### 구장 운영자 — `OperatorController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| POST | `/api/v1/operator/venue-applications` | 회원 |  |
| GET | `/api/v1/operator/venues` | 회원 |  |
| GET | `/api/v1/operator/venues/{venueId}` | 회원 |  |
| PATCH | `/api/v1/operator/venues/{venueId}` | 회원 |  |
| POST | `/api/v1/operator/venues/{venueId}/courts` | 회원 |  |
| PATCH | `/api/v1/operator/courts/{courtId}` | 회원 |  |
| GET | `/api/v1/operator/courts/{courtId}/operating-hours` | 회원 |  |
| PUT | `/api/v1/operator/courts/{courtId}/operating-hours` | 회원 |  |
| GET | `/api/v1/operator/courts/{courtId}/slots` | 회원 |  |
| PATCH | `/api/v1/operator/slots/{slotId}` | 회원 |  |
| GET | `/api/v1/operator/venues/{venueId}/closures` | 회원 |  |
| POST | `/api/v1/operator/venues/{venueId}/closures` | 회원 |  |
| DELETE | `/api/v1/operator/venues/{venueId}/closures/{closureId}` | 회원 |  |
| GET | `/api/v1/operator/venues/{venueId}/reservations` | 회원 |  |
| POST | `/api/v1/operator/reservations/{publicId}/cancel` | 회원 | ★ |
| GET | `/api/v1/operator/venues/{venueId}/staff` | 회원 |  |
| POST | `/api/v1/operator/venues/{venueId}/staff` | 회원 |  |
| DELETE | `/api/v1/operator/venues/{venueId}/staff/{userId}` | 회원 |  |

### 구장 검색·상세 (공개) — `VenueController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| GET | `/api/v1/venues` | 공개 |  |
| GET | `/api/v1/venues/{id}` | 공개 |  |
| GET | `/api/v1/venues/{id}/availability` | 공개 |  |
| GET | `/api/v1/facilities` | 공개 |  |

### 숏폼 — `VideoController`

| 메서드 | 경로 | 권한 | 멱등키 |
|---|---|---|---|
| POST | `/api/v1/videos/uploads` | 회원 |  |
| POST | `/api/v1/videos/{id}/complete` | 회원 |  |
| POST | `/api/v1/videos/{id}/abort` | 회원 |  |
| GET | `/api/v1/videos/{id}` | 회원 |  |

## 오류 코드

`409`·`400` 등 HTTP 상태와 함께 아래 `code`가 온다. "결제 결과 상태값"은 HTTP 오류가 아니라 결제 상태 조회 응답의 `failureCode`로 전달된다.

| 코드 | HTTP | 사용자 문구 |
|---|---|---|
| VALIDATION_FAILED | 400 | 입력값을 확인해 주세요 |
| BAD_REQUEST | 400 | 잘못된 요청이에요 |
| UNAUTHENTICATED | 401 | 로그인이 필요해요 |
| TOKEN_EXPIRED | 401 | 로그인이 만료되었어요 |
| TOKEN_INVALID | 401 | 로그인 정보가 올바르지 않아요 |
| TOKEN_REUSED | 401 | 보안을 위해 다시 로그인해 주세요 |
| INVALID_CREDENTIALS | 400, 401 | 이메일 또는 비밀번호가 올바르지 않아요 |
| ACCOUNT_LOCKED | 423 | 로그인 시도가 많아 잠시 잠겼어요. 15분 뒤 다시 시도해 주세요 |
| ACCOUNT_SUSPENDED | 401, 403 | 이용이 제한된 계정이에요 |
| ACCOUNT_NOT_ALLOWED | 403 | 이메일 인증을 마친 계정만 이용할 수 있어요 |
| EMAIL_NOT_VERIFIED | 403 | 이메일 인증을 먼저 완료해 주세요 |
| EMAIL_TAKEN | 409 (DB 유일 제약) | 이미 가입된 이메일이에요 |
| NICKNAME_TAKEN | 409 (DB 유일 제약) | 이미 사용 중인 닉네임이에요 |
| WEAK_PASSWORD | 400 | 비밀번호는 영문과 숫자를 포함해 8자 이상이어야 해요 |
| CONSENT_REQUIRED | 400 | 필수 약관에 동의해 주세요 |
| CODE_INVALID | 400 | 인증 코드가 올바르지 않아요 |
| CODE_EXPIRED | 400 | 인증 코드가 만료되었어요. 다시 받아 주세요 |
| CODE_ATTEMPTS_EXCEEDED | 400 | 시도 횟수를 넘었어요. 코드를 다시 받아 주세요 |
| EMAIL_NOT_CONFIGURED | 503 | 메일 발송이 아직 설정되지 않았어요 |
| SOCIAL_NOT_CONFIGURED | 503 | 이 로그인 방식은 아직 준비 중이에요 |
| SOCIAL_TOKEN_INVALID | 401 | 소셜 로그인 정보를 확인할 수 없어요 |
| FORBIDDEN | 403 | 권한이 없어요 |
| BLOCKED | 403 | 차단 관계인 사용자와는 할 수 없어요 |
| NOT_FOUND | 404 | 찾을 수 없어요 |
| SLOT_TAKEN | 409 | 방금 다른 분이 예약한 시간이에요 |
| SLOT_UNAVAILABLE | 409 | 예약할 수 없는 시간이에요 |
| SLOT_HAS_RESERVATION | 409 | 예약이 있는 시간은 변경할 수 없어요 |
| HOLD_LIMIT | 409 | 결제 대기 중인 예약이 너무 많아요. 먼저 결제하거나 취소해 주세요 |
| HOLD_EXPIRED | 409 | 결제 시간이 지나 예약이 만료되었어요 |
| VENUE_NOT_BOOKABLE | 409 | 지금은 예약을 받지 않는 구장이에요 |
| INVALID_STATE | 409 | 지금 상태에서는 할 수 없는 작업이에요 |
| NOT_CANCELABLE | 409 | 이용 시작 이후에는 취소할 수 없어요 |
| HAS_ACTIVE_RESERVATIONS | 409 | 진행 중인 예약이 있어 탈퇴할 수 없어요. 먼저 예약을 취소해 주세요 |
| HAS_PENDING_REFUNDS | 409 | 환불이 진행 중이에요. 환불 완료 후 탈퇴할 수 있어요 |
| AMOUNT_MISMATCH | 결제 결과 상태값 | 결제 금액이 올바르지 않아요 |
| PAYMENT_NOT_CONFIGURED | 503 | 결제 기능이 아직 준비 중이에요 |
| PAYMENT_FAILED | 결제 결과 상태값 | 결제에 실패했어요 |
| PAYMENT_PENDING | 결제 결과 상태값 | 결제 결과를 확인하고 있어요 |
| MEDIA_NOT_CONFIGURED | 503 | 사진·영상 업로드가 아직 준비 중이에요 |
| UPLOAD_NOT_FOUND | 400 | 업로드된 파일을 찾을 수 없어요 |
| UNSUPPORTED_MEDIA | 400 | 지원하지 않는 파일 형식이에요 |
| FILE_TOO_LARGE | 400 | 파일 용량이 너무 커요 |
| ALREADY_REPORTED | 409 (DB 유일 제약) | 이미 신고한 내용이에요 |
| DUPLICATE | 409 | 이미 처리된 요청이에요 |
| IDEMPOTENCY_KEY_REQUIRED | 400 | 요청 식별 키가 필요해요 |
| IDEMPOTENCY_CONFLICT | 422 | 같은 요청 키로 다른 내용을 보낼 수 없어요 |
| IDEMPOTENCY_IN_PROGRESS | 409 | 같은 요청을 처리하고 있어요 |
| RATE_LIMITED | 429 | 요청이 너무 많아요. 잠시 후 다시 시도해 주세요 |
| RETRY | 503 | 잠시 후 다시 시도해 주세요 |
| INVALID_TARGET | 400 | 대상이 올바르지 않아요 |
| INTERNAL | 500 | 일시적인 오류가 발생했어요 |
