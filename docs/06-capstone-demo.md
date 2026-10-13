# F-Mate 캡스톤 발표용 로컬 시연 가이드

이 브랜치는 발표 준비용입니다. 기존 GitHub `main`과 무관한 Git 이력에서 만든
2026-10-13 소스 스냅샷(`7ab7e1b`)을 `main`의 새 브랜치에 가져왔습니다.
**첫 실제 통합 빌드 및 단말 시연은 아직 검증되지 않았습니다.**
발표 당일에 처음 설치하지 말고 같은 구성에서 미리 리허설하세요.

## 필요한 환경

- Windows 11 x64, 가급적 RAM 32GB와 SSD 여유 50GB 이상
- 관리자 권한, BIOS/UEFI CPU 가상화 및 Windows WSL2 사용 가능 여부 확인
- Docker Desktop(WSL2 백엔드), Android Studio + Android Emulator, Flutter SDK
- 첫 설치·의존성 다운로드·지도/결제 등의 외부 연동에는 인터넷 필요
- 발표용 PC에 설치가 불가능하면 Android 실기기 + 사전 빌드한 APK를 예비안으로 확보

## 1. 서버 실행

PowerShell에서 저장소 최상위 폴더로 이동:

```powershell
Copy-Item .env.example .env
docker compose config --quiet
docker compose up -d --build
docker compose ps
Invoke-RestMethod http://localhost:8080/actuator/health
```

헬스체크에서 `UP`이 보여야 다음 단계로 진행합니다.
가입 이메일 인증 코드는 `http://localhost:8025`(Mailpit)에서 확인합니다.
DB는 PostgreSQL, 파일은 로컬 SeaweedFS에 저장됩니다.
도커 컨테이너를 지워도 볼륨을 삭제하지 않는 한 데이터가 유지되지만,
대여 PC 초기화에는 대비해 별도로 백업해야 합니다.

## 2. 에뮬레이터용 플러터 앱

`app/setup_fmate_app.ps1`는 안드로이드 프로젝트 생성과 기초 설정을 돕습니다.
실행 전에 `flutter doctor -v`로 환경을 점검하세요.

```powershell
cd app
powershell -ExecutionPolicy Bypass -File .\setup_fmate_app.ps1 -Target C:\dev\fmate_app
cd C:\dev\fmate_app
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2`는 Android Emulator에서 호스트 PC에 접속하는 주소입니다.
실제 스마트폰 시연으로 전환하려면 PC와 같은 네트워크를 이용하고
`API_BASE_URL`, `PUBLIC_BASE_URL`, `STORAGE_PRESIGN_ENDPOINT`,
`CDN_BASE_URL`을 기기에서 접근 가능한 PC 주소로 맞춥니다.
자세한 플랫폼 설정은 `app/ANDROID_SETUP.md`를 참조하세요.

## 3. 발표용 데이터 준비

- `backend/demo/README.md`의 SQL/공공데이터 임포트 절차를 사용합니다.
- 발표 전날까지 실제 풋살장 목록/시연용 시간표를 준비해야 예약 화면이 비지 않습니다.
- 공공데이터 체육시설의 예약·가격은 **실제 예약이 아닌 데모**라는 사실을 표기합니다.
- 데모 계정과 비밀번호는 개발 전용이며 인터넷에 공개된 서버에는 사용하지 않습니다.
- SNS 게시물, 사진·영상, 테스트 채팅 2개 계정을 미리 준비합니다.
- 결제는 **토스 테스트 키로 실제 동작을 확인한 경우에만** 시연합니다.
- FCM/지도/소셜 로그인은 키가 없으면 건너뛰어도 핵심 시연이 가능합니다.

## 4. 리허설 체크리스트

- [ ] `docker compose up -d --build` 오류 없이 완료
- [ ] API 헬스체크 `UP`, 이메일 인증 수신
- [ ] 에뮬레이터에서 앱 실행·회원가입·로그인 확인
- [ ] 실제/시연용 풋살장 검색과 시간 선택 가능
- [ ] 게시물 조회·작성·좋아요 가능
- [ ] 두 계정 사이에 채팅 송수신 가능
- [ ] 테스트 키를 넣은 경우에만 결제·취소 검증
- [ ] 앱 화면 녹화, 데이터 백업, 재시작 복구를 별도 리허설
- [ ] 발표 직전에는 업데이트나 코드 수정을 하지 않기

권장 발표 흐름(약 5분): 로그인 → 풋살장 검색·예약 과정 → SNS →
채팅 → 기술 구조 설명. 기능이 아직 실제로 검증되지 않은 부분을
완료된 기능이라고 설명하지 마세요.

## 5. 주의

- `.env`, 서비스 계정 JSON, Google API 키, DB 덤프를 Git에 커밋하지 않습니다.
- `docker compose down -v`는 **볼륨의 시연 데이터까지 삭제**하므로 사용하지 마세요.
- 이 브랜치는 소스 백업과 작업 시작점입니다. 컴파일·실행 성공 또는 발표 준비
  완료를 의미하지 않습니다.
