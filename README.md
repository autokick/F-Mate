# F-Mate

풋살장 실시간 예약 + 풋살 커뮤니티 SNS 모바일 앱.
Flutter(Android 우선) · Spring Boot 3.5 (Java 21) · PostgreSQL 16 · 토스페이먼츠 · S3 호환 스토리지 · FCM.

> **상태**: 서버·앱·DB 전체 코드 작성 완료. DB 계층은 실제 PostgreSQL에서 테스트 134개 통과.
> 서버·앱은 이 저장소를 만든 환경에서 **컴파일하지 못했으므로 첫 빌드는 사용자 PC에서** 하게 된다.
> 기능별 정직한 상태: [docs/04-status.md](docs/04-status.md)

## 빠른 시작

```bash
# 1) 서버 (Docker Desktop 필요)
cp .env.example .env              # 외부 키는 비워 둬도 실행된다
docker compose up -d --build      # DB + API + 메일 확인함(Mailpit) + 로컬 저장소(SeaweedFS)
curl http://localhost:8080/actuator/health

# 2) 앱 (Android Studio)
#    app/README.md 의 "적용 방법" → app/ANDROID_SETUP.md 1~3번
cd <내 Flutter 프로젝트>
flutter pub get && flutter test && flutter run
```

- 가입 인증 코드: http://localhost:8025 (Mailpit)
- 첫 관리자 계정·구장 등록 방법: [docs/05-deploy.md §1](docs/05-deploy.md)
- **전시·발표용 시연 데이터**(공공데이터 실제 풋살장 가져오기, 운영자·관리자 계정): [backend/demo/README.md](backend/demo/README.md)
- 결제는 토스페이먼츠 테스트 키를 `.env`에 넣어야 켜진다. 그 전에는 앱이 "결제 준비 중"을 표시한다.

## 구성

```
fmate/
  docker-compose.yml, .env.example   로컬 실행 환경, 환경변수 목록
  docs/
    01-architecture.md        아키텍처, 데이터 소유권, 인증, 예약·결제 일관성, 영상·채팅 설계
    02-api-spec.md            API 명세 (코드에서 추출한 119개 엔드포인트, WebSocket, 오류 코드)
    03-external-services.md   결제·지도·스토리지·FCM·구장 데이터·법적 절차, 환경변수
    04-status.md              기능별 완료/부분/미구현/외부 승인 필요 + 테스트 결과
    05-deploy.md              로컬 실행, 외부 서비스 연결 순서, 운영 배포, 출시 체크리스트
  backend/                    Spring Boot 서버
    src/main/java/app/fmate/  auth, user, venue, reservation, payment, social, video, chat, notification, admin, jobs
    src/main/resources/db/migration/   Flyway V1~V6 (테이블·제약·트리거·함수)
    src/test/                 통합 테스트 (Testcontainers)
    db-tests/                 psql 기반 DB 규칙·동시성 테스트, SQL 문장 검사
  app/                        Flutter 앱 (lib/, test/, pubspec.yaml)
    README.md                 적용 방법·구조·체크리스트
    ANDROID_SETUP.md          권한·http 허용·지도·푸시·릴리스 서명
```

## 테스트

```bash
# DB 규칙·동시성 (PostgreSQL 16 + btree_gist·citext·pg_trgm). 운영 DB 서버에서 실행 금지 (fmate_t_* DB를 만들고 지움)
cd backend/db-tests && PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=... ./run.sh

# 서버 통합 테스트 (Docker 필요)
cd backend && ./gradlew test

# 앱
flutter test
```

Windows에서 `run.sh`는 Git Bash 또는 WSL에서 실행한다. `docker compose`의 DB를 쓰려면 사용자 `fmate`/비밀번호 `fmate`로 접속하되,
러너가 DB를 만들고 지우므로 별도의 테스트용 PostgreSQL 컨테이너를 권장한다.

## 원칙

- 가짜 데이터·가짜 결제 성공 없음. 외부 서비스가 연결되지 않은 기능은 "준비 중"으로 표시
- 비밀값은 환경변수로만. 저장소에 키 없음
- 예약 중복·결제 금액·환불 한도는 앱이 아니라 **DB 제약과 서버**가 보장

## Firebase Spark 전시용 빌드 (별도 기능 개발 중)

VPS나 학교 현장 서버 PC 없이 Firebase Auth·Firestore로 실시간 계정/시연 예약/텍스트 SNS/1:1 채팅을 테스트하는 **별도 전시용 MVP**는 [Firebase 전시 모드 안내](docs/07-firebase-spark-exhibition.md)를 참고한다. 기존 Spring Boot 서비스를 대체하는 전체 기능 이관은 아직 완료되지 않았다. Firebase 전시 빌드는 `--dart-define=BACKEND=firebase`를 명시하며, 현재 구장은 **가상 시설 예시**이고 실제 결제 기능은 없다.


### Firebase Spark 최신 협업 UI 보존 개발 브랜치

feature/firebase-collaborator-ui-20261015 브랜치에서는 협업자 Flutter MainShell의 디자인을 보존하고 Firebase 데이터 서비스를 연결한다. 범위와 미구현 항목은 docs/09-firebase-collaborator-ui.md 문서 참고.
