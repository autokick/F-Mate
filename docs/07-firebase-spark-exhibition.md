# F-Mate Firebase Spark 전시 모드 (구현 1단계)

> 이 문서는 `collab/update-20261015` 기반의 **별도 Firebase 빌드**를 설명한다. 기존 Spring Boot/PostgreSQL/Docker 서비스는 변경하거나 삭제하지 않았다.

## 1. 적용 범위 — 실제 구현과 미구현을 구분

| 기능 | 1단계 현황 | 서버/실데이터 여부 |
|---|---|---|
| 기존 디자인 로그인·회원가입 | Firebase Authentication 이메일/비밀번호 연동 | 실제 Firebase 계정 |
| 이메일 인증·비밀번호 재설정 | Firebase 이메일 링크 방식 | 실제 Firebase Auth |
| 프로필/약관 | Firestore `profiles/{uid}` + `private_users/{uid}` | 실제 DB 저장 |
| 풋살장 보기 | **가상 시설 4곳** 내장 | 로컬 예시 데이터. 실제 시설 아님 |
| 예약·취소 | 전시용 3개 시간대/구장, Firestore 트랜잭션 | 실제 DB 쓰기·동시 선점 검증. **실제 예약 아님** |
| SNS 텍스트 글 | 공개 게시판에 작성·읽기·삭제 | 실제 Firestore 동기화 |
| 실시간 1:1 채팅 | 두 Firebase 계정이 대화 | 실제 Firestore 동기화 |
| 자동응답 | 시간·예약·준비물에 대한 키워드 답변 | 기기 로컬 시뮬레이션. AI/실제 회원 아님 |
| 동영상·사진 업로드·결제·관리자 | **미구현** | 저장소·Cloud Functions/상용 API가 필요할 수 있음 |
| 기존 Flutter 38화면 완전 이관 | **미구현** | 현재는 독립된 전시용 탭 화면 사용 |
| 방문자 자동 로그아웃 | 구현 | Firebase 빌드 기본: 재시작 시 로그아웃, 5분 무조작 후 확인창 30초 → 로그아웃 |
| 방문자 서버 데이터 자동 삭제 | **미구현** | 로그아웃해도 서버 기록은 남음 |

- 실서비스로 출시 가능한 전체 기능 이관이나 성능/개인정보 심사를 마친 상태가 아니다.
- **Firebase Spark 무료** 범위를 사용하며 Cloud Storage, Cloud Functions, 결제수단 등록은 필수가 아니다.
- FCM은 `BACKEND=firebase` 빌드에서 초기화하지 않는다. 비밀번호/계정 API 키, 서비스 계정 JSON을 APK나 Git에 넣지 말 것.

## 2. Firebase 콘솔에서 해야 할 일

1. 프로젝트 ID: `f-mate`. 기존 프로젝트 그대로 사용하고 요금제 **Spark** 유지.
2. Authentication: 이메일/비밀번호 활성화 확인 (사용자 수행 완료).
3. Firestore: `(default)` / `asia-northeast3` (사용자 수행 완료).
4. 현재 규칙 `if false`는 안전한 준비 상태다. **테스트 후** 저장소 루트 `firestore.rules`의 내용을 콘솔 **Firestore > 규칙**에 복사해 게시해야 1단계 쓰기 기능이 작동한다. `if true`로 절대 열지 말 것.
5. 프로젝트 설정 > 내 앱 > Android 추가: **패키지명 `app.fmate`**. 기존 `com.yangpa.fmate`는 구형 Kotlin 앱이므로 재사용하지 않는다.
6. 위 새 Android 앱에서 `google-services.json` 다운로드. 생성된 Flutter Android 프로젝트의 **`android/app/google-services.json`** 에 놓고 Git에 커밋하지 말 것.

`google-services.json`은 안드로이드에 포함되는 클라이언트용 설정이지만, 다른 종류의 Firebase 서비스 계정(JSON 비밀키)이나 결제 시크릿을 공개 저장소에 올려서는 안 된다.

## 3. Android 프로젝트 생성 (Windows PowerShell)

`app/`은 플랫폼별 `android/` 폴더를 Git에 보관하지 않는다. 최신 Flutter/Android Studio를 설치한 PC에서:

```powershell
# 이 브랜치의 app/ 폴더로 이동
cd C:\dev\fmate\app
powershell -ExecutionPolicy Bypass -File .\setup_fmate_app.ps1 -Firebase
```

- `-Firebase`는 **앱의 applicationId를 `app.fmate`로 고정하고 Google Services Gradle 플러그인을 추가**한다. 기존 Spring 빌드만 만들 때는 해당 옵션 없이 실행한다.
- `C:\dev\fmate_app\android\app\google-services.json`에 다운로드한 파일을 놓는다.
- 이미 만든 Android 프로젝트의 앱 코드를 교체해야 한다면 **백업 후** `-Force -Firebase`를 사용한다. `-Force`는 대상의 `lib/`, `test/`, `assets/`를 덮어쓴다.
- Flutter SDK가 현재 연결된 Linux Mint PC에 없어 여기에서는 APK 실제 빌드를 검증하지 못했다.

```powershell
cd C:\dev\fmate_app
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=BACKEND=firebase --dart-define=EXHIBITION_KIOSK=true
# 전시용 릴리스 APK (서명 등 정상 설정 후)
flutter build apk --release --dart-define=BACKEND=firebase --dart-define=EXHIBITION_KIOSK=true
```

보통 빌드: `flutter run` (기존 Spring API를 사용). Firebase 빌드: 반드시 `--dart-define=BACKEND=firebase`.

## 4. 보안 규칙과 테스트

소스: `firestore.rules`. 처음 사용자 등록 시 `profiles/{uid}`에는 공개 닉네임만, `private_users/{uid}`에는 약관 동의만 보관한다. 이메일/비밀번호는 Firestore에 직접 저장하지 않는다.

- 게시글은 **공개**이며, 이메일 인증된 작성자만 쓸 수 있다.
- 채팅방 및 메시지는 인증된 2명만 읽고 작성할 수 있다.
- 예약은 4개 **가상 구장**의 지정 날짜/시간 `demo_slots/{venueId_date_hour}` 문서 하나로 선점해 동시 중복을 방지한다. 실제 영업 예약에는 사용할 수 없다.
- `payments`, 기존 `users`, `venues` 등의 이관하지 않은 컬렉션은 **모두 접근 거부**한다.

**로컬 보안 규칙 테스트(프로덕션 프로젝트 미접속):**

```bash
cd firebase-tests
npm install
npm test
```

Firebase Emulator CLI와 Java가 필요하다. 성공한 경우에만 콘솔에 Firestore 규칙을 게시한다. 콘솔 게시를 직접 하기 어렵다면 Firebase CLI에서 본인 Google 계정으로 로그인하여 **규칙만** 배포할 수 있다(`firebase deploy --only firestore:rules --project f-mate`). 서비스 계정 키나 로그인 코드를 누구에게도 보내지 않는다.

## 5. 전시 실사용 전에 남은 작업

1. 실제 공공데이터 시설 정보 대량 가져오기 (현재 가상 4곳만 노출됨).
2. 협업자가 만든 Flutter 홈/예약/SNS/프로필 UI에 Firebase 리포지토리 연결하기. 현재 전시 모드는 임시 별도 UI다.
3. 서버에 남는 방문자 작성 글·예약·채팅 데이터 정리 정책과 운영자용 테스트 계정 정리 절차. 기기 재시작/무조작 자동 로그아웃은 구현했지만 **클라우드 데이터 자동 삭제는 미구현**.
4. 결제 테스트 연동: **서버에 시크릿 키를 보관하고 승인하는 별도 백엔드**가 필요하다. 단순 결제창 재현은 테스트 모드라고 명시. 이 1단계에 실결제/테스트 PG 호출은 없다.
5. 실제 Android 기기에서 인터넷 끊김·지연·다중 계정·이메일 인증 반복·오류 복구 검증.

현재 Firestore에 배포된 `if false` 규칙을 유지하는 동안 가입 후 프로필 저장과 글/예약/채팅 쓰기는 **권한 거부가 정상**이다. 규칙을 안전하게 검증하고 게시한 후 사용한다.
