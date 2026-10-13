# 03. 외부 서비스·데이터 확보·승인 절차

이 문서는 **아직 아무것도 연결·계약되지 않은 상태**를 기준으로, 기능별로 무엇이 필요한지와 누가 해야 하는지를 정리한다. 모든 키는 환경변수 또는 비밀 관리 서비스로만 주입하며 저장소에 커밋하지 않는다.

## 1. 결제 — 토스페이먼츠

| 단계 | 내용 | 담당 | 상태 |
|---|---|---|---|
| 개발자 가입 | 테스트 클라이언트 키·시크릿 키 발급 (`test_` 접두) | 사업자 | 미진행 |
| 테스트 연동 | 결제창(서버 `/pay/checkout` 페이지, 토스 JS SDK v2) + 승인·취소·조회 API(서버) + 웹훅 + 대사·환불 재시도 작업 | 개발 | **코드 구현됨** — 테스트 키 입력 후 실제 결제창 검증 필요 |
| **정산 구조 결정** | 아래 참고 — 법률·PG 상담 필요 | 사업자 | **결정 필요** |
| 전자결제 계약·심사 | 사업자등록, 통신판매업 신고, 서비스 심사 후 라이브 키 (`live_` 접두) | 사업자 | 외부 승인 필요 |
| 라이브 전환 | `PAYMENT_MODE=LIVE` + 라이브 키. 소액 실결제→취소로 검증 | 개발+사업자 | 대기 |

**정산 구조는 출시 전 반드시 결정해야 하는 사업·법률 사항이다.** F-Mate가 이용자에게서 대금을 받아 구장에 나눠 지급하면 결제대행(전자금융업) 규제 이슈가 생길 수 있다. 일반적인 선택지는 (a) PG사의 지급대행·오픈마켓형 정산 상품을 이용하거나 (b) 구장별로 하위 가맹점을 두는 방식이다. 어느 방식이 적법하고 현실적인지는 토스페이먼츠 영업 담당과 전자금융 전문 법률 검토로 확정한다. 코드에는 이 결정 전까지 정산(구장 지급) 기능을 넣지 않는다.

운영 원칙: 테스트 모드에서는 앱 상단에 "테스트 결제" 배지를 항상 표시하고, 라이브 키가 없으면 결제 버튼 대신 "결제 준비 중"을 표시한다. 카드 정보는 앱·서버 어디에도 입력·저장하지 않는다(토스 결제창에서만 입력).

## 2. 지도·위치

| 항목 | 권장안 | 필요 정보 |
|---|---|---|
| 지도 SDK | 네이버 지도(NCP Maps, Flutter: `flutter_naver_map`) 또는 카카오맵 | 앱 Client ID, Android 패키지명·iOS 번들ID 등록 |
| 주소 → 좌표 | 같은 공급자의 Geocoding API (서버에서 호출) | API 키 (서버 전용) |
| 현재 위치 | `geolocator` (OS 권한 팝업) | 권한 사용 목적 문구 |

**위치정보 관련 법적 절차**: 사용자 위치를 이용해 주변 구장을 보여주는 기능은 「위치정보의 보호 및 이용 등에 관한 법률」의 위치기반서비스에 해당할 수 있어, 방송통신위원회 신고와 위치기반서비스 이용약관·동의 절차가 필요한지 출시 전 확인해야 한다. 확인 전까지는 대안으로 "지역(시군구) 선택" 검색을 기본으로 두고, 현재 위치 기능은 동의(consents.LOCATION) 후에만 동작하도록 설계했다.

## 3. 실제 구장 데이터 확보

| 경로 | 쓰임 | 비고 |
|---|---|---|
| **구장 운영자 직접 입점** (기본) | 예약 가능한 유일한 데이터 | 신청 → 사업자등록증·현장 사진 확인 → 관리자 승인(VERIFIED) → 운영시간·요금 등록 |
| 제휴 API | 기존 예약 시스템을 쓰는 구장과 연동 | 계약 필요. `data_source = PARTNER_API` |
| 공공데이터(체육시설 정보) | 입점 영업 대상 목록 작성용 | 이용 허락 범위 확인. 앱에 예약 가능 구장처럼 노출하지 않음 |

다른 예약 플랫폼의 데이터를 수집(스크래핑)해서 쓰지 않는다. 입점 구장이 없으면 앱은 "아직 등록된 구장이 없습니다" 빈 상태와 "구장 등록 신청" 진입점을 보여준다.

**첫 출시 전 권장 행동**: 출시 지역(예: 화성·수원·용인 등 한 권역)을 정하고 5~10곳을 직접 입점시켜 실제 운영시간·요금으로 예약을 검증한다.

## 4. 인증 관련

| 서비스 | 필요 | 비고 |
|---|---|---|
| 메일 발송 | AWS SES, NHN Cloud Email 등 + 발신 도메인 SPF·DKIM·DMARC | 인증·재설정 메일 도달률 |
| 카카오 로그인 | Kakao Developers 앱 등록, 네이티브 앱 키, 키 해시 | 비즈 앱 전환 시 이메일 동의항목 |
| 구글 로그인 | Google Cloud OAuth 클라이언트(Android SHA-1, iOS) | |
| 애플 로그인 | Apple Developer Program(유료), Sign in with Apple 키 | iOS 출시 시 |

## 5. 스토리지·영상

| 항목 | 선택지 | 필요 |
|---|---|---|
| 오브젝트 스토리지 | AWS S3, Cloudflare R2, NCP Object Storage | 버킷 2개(원본 비공개 / 파생 CDN 공개), CORS, 수명주기(미완료 멀티파트 1일 삭제) |
| CDN | CloudFront, Cloudflare, NCP CDN | 서명 URL 키 (비공개 영상용) |
| 인코딩 | 자체 FFmpeg 워커(컨테이너) 또는 관리형(MediaConvert, NCP VOD Station) | HLS 프로파일, 썸네일 |

## 6. 푸시 — FCM

Firebase 프로젝트 생성 → Android `google-services.json`, iOS `GoogleService-Info.plist` + APNs 인증 키 업로드 → 서버용 서비스 계정 JSON을 비밀 관리 서비스에 저장. Firebase의 다른 기능(Auth, Firestore, Storage)은 사용하지 않는다.

## 7. 운영 인프라

| 항목 | 권장 |
|---|---|
| 서버 | 컨테이너(Docker) + 관리형 PostgreSQL 16 (자동 백업·PITR) |
| HTTPS | 로드밸런서 TLS 종료, HSTS |
| 비밀 관리 | AWS Secrets Manager / NCP Secret Manager / 최소한 배포 환경변수 (저장소 커밋 금지) |
| 오류 추적 | Sentry (서버·Flutter), 개인정보 필드 스크러빙 |
| 모니터링 | Spring Actuator + Prometheus/Grafana 또는 클라우드 모니터링, 결제 실패율·IN_PROGRESS 체류·환불 재시도 알림 |
| 백업 검증 | 월 1회 복구 리허설 (백업에서 임시 DB 복원 → `db-tests/run.sh` 수준 무결성 확인) |

## 8. 환경변수 목록

서버 값은 모두 환경변수로만 넣는다(코드·저장소에 비밀값 없음). 전체 예시는 저장소 루트의 [`.env.example`](../.env.example).
**비워 두면 해당 기능은 꺼지고 앱에 "준비 중"으로 표시**된다 — 가짜로 성공 처리하지 않는다.

| 변수 | 필수 | 비어 있을 때 |
|---|---|---|
| `SPRING_PROFILES_ACTIVE` | 운영 `prod` | 개발 모드(인증 코드 로그 출력, 임시 JWT 키 허용) |
| `JWT_SECRET` | 운영 필수 | 개발: 재시작마다 바뀌는 임시 키 / 운영: 서버 시작 거부 |
| `PUBLIC_BASE_URL` | 필수 | 결제창 리다이렉트 주소. 운영은 https 아니면 시작 거부 |
| `DB_URL` `DB_USERNAME` `DB_PASSWORD` `DB_POOL_SIZE` | 필수 | 로컬 기본값 |
| `MAIL_HOST` `MAIL_PORT` `MAIL_USERNAME` `MAIL_PASSWORD` `MAIL_FROM` `MAIL_SMTP_AUTH` `MAIL_STARTTLS` | 가입에 필요 | 개발: 코드를 서버 로그에 출력 / 운영: 가입·재설정 불가(`EMAIL_NOT_CONFIGURED`) |
| `PAYMENT_MODE` `TOSS_CLIENT_KEY` `TOSS_SECRET_KEY` | 예약에 필요 (테스트 키는 토스페이먼츠 개발자센터 가입 즉시 발급, 무료) | 예약·결제 버튼이 "결제 준비 중"으로 비활성 |
| `STORAGE_ENDPOINT` `STORAGE_PRESIGN_ENDPOINT` `STORAGE_REGION` `STORAGE_ACCESS_KEY` `STORAGE_SECRET_KEY` `STORAGE_BUCKET_RAW` `STORAGE_BUCKET_PUBLIC` `CDN_BASE_URL` `STORAGE_PATH_STYLE` | 사진·영상에 필요 (docker compose 는 로컬 SeaweedFS 자동) | 글은 쓸 수 있지만 사진·프로필 사진·숏폼 업로드 비활성 |
| `ENCODER_ENABLED` `FFMPEG_PATH` `FFPROBE_PATH` | 숏폼에 필요 | 숏폼 업로드 비활성 |
| `FCM_CREDENTIALS_PATH` | 선택 | 푸시 미발송, 앱 내 알림 목록만 |
| `KAKAO_APP_ID` `GOOGLE_CLIENT_IDS` `APPLE_AUDIENCES` | 선택 | 해당 소셜 로그인 버튼 숨김 |
| `MAPS_ENABLED` | 선택 | 앱이 지도 대신 목록만 표시 |
| `KAKAO_REST_API_KEY` | 선택 | "내 주변 실제 풋살장"(카카오 로컬 검색) 숨김. 결과는 실시간 조회만 하고 저장하지 않음(카카오 정책) |
| `FMATE_DEV_MODE` `CORS_ALLOWED_ORIGINS` `PORT` `MAIL_HEALTH_ENABLED` | 선택 | 기본값 |

앱(`--dart-define`): `API_BASE_URL`(기본 `http://10.0.2.2:8080`), `ENV`, `MAPS_ENABLED`, `PUSH_ENABLED`.
토스 **클라이언트** 키는 앱에 넣지 않는다 — 결제창은 서버의 `/pay/checkout` 페이지가 그리므로 시크릿·클라이언트 키 모두 서버에만 있다.
지도 키는 `android/app/src/main/AndroidManifest.xml`, FCM 설정은 `android/app/google-services.json` 에 들어간다([app/ANDROID_SETUP.md](../app/ANDROID_SETUP.md)).

## 9. 법률·정책 문서 (출시 전 필요)

- 서비스 이용약관, 개인정보 처리방침, 위치기반서비스 이용약관(해당 시), 커뮤니티 운영정책(신고·제재·저작권 침해 대응 절차)
- 통신판매업(또는 통신판매중개업) 신고 및 앱 내 사업자 정보 표시
- 만 14세 미만 가입 제한 또는 법정대리인 동의 절차
- 결제·계약 기록 보존 기간 확정 (탈퇴 후에도 결제 기록은 식별정보 없이 보존하도록 DB 설계됨 — 보존 기간은 법률 검토로 확정)

위 문서는 법률 전문가 검토가 필요하며, 이 저장소에는 초안만 둔다.
