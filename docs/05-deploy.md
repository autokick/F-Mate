# 05. 실행·배포 가이드

## 1. 로컬 개발 (PC 한 대)

필요: Docker Desktop, Android Studio + Flutter SDK.

```bash
cp .env.example .env          # 외부 키는 비워 둬도 된다
docker compose up -d --build  # PostgreSQL + API 서버 + Mailpit + SeaweedFS
curl http://localhost:8080/actuator/health   # {"status":"UP"}
docker compose logs -f api    # 시작 로그에 "외부 서비스 설정 상태" 표가 나온다
```

- 가입 인증 코드 메일은 **http://localhost:8025** (Mailpit)에서 확인한다.
- 사진·영상·구장 서류는 로컬 **SeaweedFS**(S3 호환)에 저장된다. 그래서 외부 키 없이도 구장 입점 신청(사업자등록증 첨부), 게시물 사진, 숏폼 업로드·인코딩까지 PC에서 실제로 동작한다.
  실제 휴대폰으로 테스트하면 `.env`에 `STORAGE_PRESIGN_ENDPOINT=http://<PC IP>:9000`, `CDN_BASE_URL=http://<PC IP>:9000/fmate-public`을 넣는다.
- 앱은 에뮬레이터에서 `http://10.0.2.2:8080` 으로 접속한다(기본값). 실제 휴대폰은 PC와 같은 Wi-Fi에서
  `flutter run --dart-define=API_BASE_URL=http://<PC의 IP>:8080` 으로 실행하고, `.env`의 `PUBLIC_BASE_URL`도 같은 주소로 맞춘다.
- DB 스키마는 서버가 시작할 때 Flyway가 `V1`~`V6`을 자동 적용한다.

Docker 없이 서버만 실행하려면 (JDK 21 필요):
```bash
cd backend
./gradlew bootRun          # PostgreSQL 이 localhost:5432 에 fmate/fmate 로 있어야 함
./gradlew test             # Testcontainers 로 PostgreSQL 을 띄우므로 Docker 필요
```

### 첫 관리자 계정 만들기

관리자 승격 API는 관리자만 호출할 수 있으므로 첫 관리자는 DB에서 직접 지정한다.
앱에서 가입·이메일 인증을 마친 뒤:

```bash
docker compose exec db psql -U fmate -d fmate \
  -c "UPDATE users SET role='ADMIN', token_version = token_version + 1 WHERE email='나의이메일@example.com';"
```
다시 로그인하면 마이 탭 프로필 아래에 "운영 관리" 버튼이 생긴다. 이후 관리자 추가·해제는 앱의 관리자 화면에서 한다(감사 로그에 기록됨).

### 구장 등록 흐름 (실제 데이터 확보)

1. 구장 운영자가 앱에서 가입·이메일 인증 → 마이 → "구장 운영자 입점 안내" → 입점 신청 (사업자 정보, 주소, 코트, 증빙)
2. 관리자가 "운영 관리" → 구장 심사에서 승인
3. 운영자가 코트별 운영시간·가격을 등록하면 예약 가능한 시간이 생성된다

가짜 구장은 넣지 않는다. 구장이 하나도 없으면 앱은 빈 상태 안내를 보여준다.

## 2. 외부 서비스 연결 순서 (키를 받은 뒤)

각 항목은 `.env`에 값을 넣고 `docker compose up -d` 로 재시작하면 켜진다. 앱은 `/api/v1/config`를 보고 자동으로 버튼을 활성화한다.

| 순서 | 서비스 | 할 일 | 확인 방법 |
|---|---|---|---|
| 1 | 메일 (SMTP) | `MAIL_*` 입력 (예: AWS SES, 네이버 웍스, Gmail 앱 비밀번호) | 가입 시 실제 메일 수신 |
| 2 | 토스페이먼츠 테스트 키 | `TOSS_CLIENT_KEY`, `TOSS_SECRET_KEY` (`test_` 로 시작), 토스 개발자센터에 웹훅 URL `https://<서버>/api/v1/webhooks/toss` 등록 | 앱에서 예약 → 테스트 결제 → "예약 확정", 취소 → 환불 |
| 3 | S3 호환 스토리지 (운영) | 로컬은 SeaweedFS가 자동으로 대신한다. 운영은 버킷 2개(원본 비공개 `RAW`, 공개 `PUBLIC`) + CDN 주소 + 접근 키 + `STORAGE_ENDPOINT` | 게시물 사진 업로드 |
| 4 | 영상 인코더 | docker compose는 기본 켜짐. 그 외 `ENCODER_ENABLED=true` (서버에 ffmpeg 필요) | 숏폼 업로드 후 1~2분 내 재생 |
| 5 | Firebase (FCM) | 서비스 계정 JSON을 서버에 두고 `FCM_CREDENTIALS_PATH`, 앱에 `google-services.json` + `--dart-define=PUSH_ENABLED=true` | 채팅 메시지 푸시 수신 |
| 6 | Google Maps | 앱 `AndroidManifest.xml`에 API 키, 서버 `MAPS_ENABLED=true`, 앱 `--dart-define=MAPS_ENABLED=true` | 풋살장 탭 지도 보기 |
| 7 | 소셜 로그인 | `KAKAO_APP_ID` / `GOOGLE_CLIENT_IDS` / `APPLE_AUDIENCES` + 앱 쪽 SDK 연동 | — (앱 SDK 연동은 미구현, docs/04 참고) |

S3 호환이면 AWS S3, Cloudflare R2, NCP Object Storage 모두 된다. R2·MinIO는 `STORAGE_PATH_STYLE=true`가 필요할 수 있다.

## 3. 운영 배포 (서버 1대 기준)

권장 최소 구성: 리눅스 서버 1대(2 vCPU / 4GB, 영상 인코딩을 하면 4 vCPU) + 관리형 PostgreSQL 16 + S3 호환 스토리지/CDN.

1. **DB**: 관리형 PostgreSQL 16 (AWS RDS, NCP Cloud DB 등). 확장 `btree_gist`, `citext`, `pg_trgm` 사용 가능해야 한다. 자동 백업·PITR 켜기.
2. **서버**: `backend/Dockerfile`로 이미지 빌드
   ```bash
   docker build -t fmate-api ./backend
   docker run -d --name fmate-api --restart=always -p 127.0.0.1:8080:8080 --env-file /etc/fmate/.env fmate-api
   ```
   `/etc/fmate/.env` 필수 값: `SPRING_PROFILES_ACTIVE=prod`, `JWT_SECRET`(`openssl rand -base64 48`), `PUBLIC_BASE_URL=https://api.도메인`, `DB_*`, `MAIL_*`.
   운영 모드는 JWT_SECRET이 없거나 PUBLIC_BASE_URL이 https가 아니거나 결제 모드와 키 종류(test/live)가 섞이면 **시작을 거부**한다.
3. **HTTPS 리버스 프록시**: Caddy 또는 Nginx로 443 → 127.0.0.1:8080. WebSocket(`/ws/chat`) 업그레이드 헤더를 넘겨야 한다.
   ```
   # Caddyfile 예시
   api.도메인 {
     reverse_proxy 127.0.0.1:8080
   }
   ```
   서버는 `X-Forwarded-*` 헤더를 신뢰하도록 설정되어 있다(`forward-headers-strategy: framework`). 프록시 없이 8080을 외부에 직접 열지 않는다.
4. **헬스체크**: `GET /actuator/health` (liveness `/actuator/health/liveness`, readiness `/actuator/health/readiness`).
5. **로그**: 표준 출력. 모든 로그 줄에 `requestId`가 붙고, 앱 오류 응답의 `requestId`로 추적한다. 서버 오류(500)는 `app_error_logs` 테이블에도 남아 관리자 화면에서 볼 수 있다.
6. **앱 빌드**: `flutter build appbundle --release --dart-define=API_BASE_URL=https://api.도메인 --dart-define=ENV=prod` (서명 설정은 [app/ANDROID_SETUP.md](../app/ANDROID_SETUP.md)).

### 백그라운드 작업 (서버 안에서 자동 실행)

| 작업 | 주기 | 내용 |
|---|---|---|
| 결제 대기 만료 | 30초 | 10분 안에 결제하지 않은 예약을 만료시켜 슬롯 반환 |
| 결제 대사 | 1분 | 승인 결과가 불확실한 결제를 토스 조회 API로 확정 또는 보상 취소 |
| 환불 처리 | 1분 | 환불 요청을 토스 취소 API로 처리, 실패 시 지수 백오프 재시도 |
| 푸시 발송 | 5초 | 알림 → FCM 발송 (설정 시), 만료 토큰 정리 |
| 영상 인코딩 | 10초 | 업로드 완료 영상 → HLS·썸네일 |
| 지난 예약 완료 처리 | 10분 | 이용 시간이 끝난 확정 예약 → 이용 완료 |
| 슬롯 생성 | 매일 03:05 | 운영시간 템플릿으로 앞으로의 예약 가능 시간 생성 |
| 정리 작업 | 매일 04시대 | 만료 토큰·멱등키 삭제, 기간 지난 제재 해제, 실패 업로드·삭제 영상 파일 정리 |

작업들은 DB 잠금(`FOR UPDATE SKIP LOCKED`/조건부 갱신)으로 처리 대상을 잡으므로 같은 행을 두 번 처리하지 않는다.

## 4. 서버를 여러 대로 늘릴 때 (지금은 불필요)

현재 구조는 **서버 1대**를 기준으로 한다. 2대 이상으로 늘리기 전에 다음을 바꿔야 한다.

| 항목 | 현재 | 바꿀 것 |
|---|---|---|
| 요청 제한 (`RateLimiter`) | 서버 메모리 | Redis 기반(Bucket4j 등) — 서버마다 따로 세면 제한이 N배로 느슨해진다 |
| 채팅 실시간 전달 (`ChatSocketHandler`) | 서버 메모리의 연결 목록 | Redis Pub/Sub 으로 다른 서버의 연결에 중계. 메시지 저장은 이미 DB라 유실은 없음 |
| 영상 인코딩 | API 서버 안에서 ffmpeg | 별도 워커 서버(같은 이미지, 인코더만 켜고 API 트래픽 제외) |
| 예약 중복 방지·결제 일관성 | DB 제약·잠금 | 변경 불필요 (서버 수와 무관하게 DB가 보장) |

## 5. 출시 전 체크리스트

- [ ] 사업자등록·통신판매업 신고, 토스페이먼츠 가맹 계약·심사 → 라이브 키 (`PAYMENT_MODE=LIVE`)
- [ ] 정산(구장 지급) 구조 결정 — docs/03 §1. 결정 전에는 정산 기능 없음
- [ ] 이용약관·개인정보처리방침·위치기반서비스 약관 **법률 검토본**으로 교체 (앱의 약관은 초안)
- [ ] 위치기반서비스사업 신고 (위치 정보를 쓰는 경우)
- [ ] 운영 DB 백업·복구 리허설
- [ ] 관리자 계정 2단계 인증 운영 정책(현재 미구현 — 관리자 계정 수를 최소화)
- [ ] 실제 기기 테스트: 결제(테스트 키) 전 과정, 취소·환불, 사진·영상 업로드, 푸시
- [ ] Play Console: 앱 서명, 개인정보 처리 항목(데이터 보안 섹션), 콘텐츠 등급, 스크린샷
