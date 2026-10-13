# F-Mate 앱 (Flutter)

## 새 PC에서 fmate_app 한 번에 만들기 (추천)

Flutter와 안드로이드 스튜디오만 설치돼 있으면, 아래 한 줄로 `C:\dev\fmate_app` 프로젝트를 만들고
앱 코드 복사 + 안드로이드 설정(minSdk 24, 권한, 결제 앱 queries, 개발용 http 허용)까지 자동으로 해요.

```
cd C:\dev\fmate\app
powershell -ExecutionPolicy Bypass -File .\setup_fmate_app.ps1
```

- 다른 위치에 만들려면 `-Target D:\work\fmate_app`, Flutter 위치를 지정하려면 `-Flutter C:\src\flutter\bin\flutter.bat`
- 이미 있는 프로젝트의 앱 코드를 이 폴더 것으로 덮어쓰려면 `-Force`
- 끝나면 안드로이드 스튜디오에서 `C:\dev\fmate_app` 을 열고 에뮬레이터를 골라 ▶ Run

## 적용 방법 (이미 만든 Flutter 프로젝트에 덮어쓰기)

1. 내 프로젝트의 `lib/` 폴더를 지우고 이 폴더의 `lib/`를 통째로 복사
2. 내 프로젝트의 `test/` 폴더를 지우고 이 폴더의 `test/`를 복사
3. `pubspec.yaml`을 이 파일로 교체 (내 프로젝트 이름이 다르면 첫 줄 `name:`만 원래 값으로 되돌려도 된다 — 코드는 상대 경로 import만 쓴다)
4. **[ANDROID_SETUP.md](ANDROID_SETUP.md)의 1~3번** (minSdk 24, 권한, 디버그 http 허용) 적용
5. 터미널: `flutter pub get` → `flutter analyze` → `flutter test` → ▶ Run
6. 서버는 저장소 루트에서 `docker compose up -d --build` (자세한 건 [../docs/05-deploy.md](../docs/05-deploy.md))

서버가 꺼져 있으면 앱은 "서버에 연결할 수 없어요 / 다시 시도"를 보여준다 — 정상 동작이다.

## 구조

```
lib/
  main.dart, app.dart          시작, 서버 연결 확인, 로그인 상태에 따른 화면 분기(AuthGate)
  core/
    config.dart                API_BASE_URL 등 --dart-define 값
    api.dart                   Dio 클라이언트, 토큰 보안 저장, 401 시 토큰 자동 갱신(동시 요청 1회만)
    models.dart                서버 응답 모델 (누락·null 에 견고하게 파싱)
    repos.dart                 API 호출 모음 (구장·예약·결제·SNS·채팅·알림·계정·운영자·관리자)
    session.dart               로그인 상태
    chat_socket.dart           채팅 WebSocket (자동 재연결)
    services.dart              앱 전역 서비스 (AppScope)
    theme.dart, format.dart, validators.dart
  shared/                      공통 위젯 (빈 상태·오류·로딩, 페이지 목록, 신고 시트)
  features/
    auth/                      로그인, 가입(약관 동의), 이메일 인증, 비밀번호 재설정, 프로필 설정
    home/                      피드 (팔로잉/추천), 이메일 미인증 안내
    booking/                   예약 탭: 날짜·지역·시간대로 빈 시간 있는 구장 찾기
    venues/                    풋살장 탭: 검색·시설 필터·지도, 구장 상세·슬롯 선택
    reservations/              예약 확인 → 토스 결제창(WebView) → 결과, 내 예약·취소
    social/ shorts/            게시물·댓글·해시태그·작성, 숏폼 재생·업로드
    chat/ notifications/       1:1 채팅, 알림 목록
    profile/ settings/         마이페이지, 프로필 편집, 팔로우, 차단, 비밀번호, 탈퇴, 약관
    operator/                  구장 운영자: 입점 신청, 코트·운영시간·슬롯·휴무·예약 관리
    admin/                     운영 관리: 대시보드, 구장 심사, 신고, 사용자 제재, 예약·결제, 로그
test/
  fake_server.dart             가짜 서버 (실제 네트워크 사용 안 함)
  widget_test.dart             시작·로그인·가입·둘러보기·예약 화면 테스트
  format_test.dart, validators_test.dart
```

## 외부 서비스가 없을 때의 동작

앱은 시작할 때 서버의 `/api/v1/config`를 읽어 켜진 기능만 보여준다. 가짜 데이터나 가짜 성공은 없다.

| 서버에 키가 없으면 | 앱 표시 |
|---|---|
| 토스 결제 | 구장 상세에서 예약 시 "결제 기능이 아직 준비 중이라 예약할 수 없어요" |
| 스토리지 (docker compose 사용 시 로컬 SeaweedFS가 자동 연결) | 사진 첨부·프로필 사진·구장 입점 서류 업로드 "준비 중" |
| 인코더 (docker compose 기본 켜짐) | 숏폼 업로드 "준비 중" |
| FCM | 푸시 없음, 앱 안 알림 목록은 동작 |
| 지도 | 목록 보기만 |
| 카카오 REST 키 | 풋살장 탭의 "내 주변 실제 풋살장 보기" 숨김 |
| 소셜 로그인 | "카카오·구글·애플 로그인은 준비 중이에요" |
| 구장 데이터 없음 | "아직 등록된 풋살장이 없어요" 빈 상태 |

토스 **테스트 키**로 결제하면 화면에 "테스트 결제" 배지가 항상 보인다.

## 확인 체크리스트 (서버 실행 + 에뮬레이터)

- [ ] 가입 → Mailpit(http://localhost:8025)에서 6자리 코드 확인 → 인증 완료
- [ ] 로그아웃 → 로그인 → 앱을 껐다 켜도 로그인 유지
- [ ] 마이 → 구장 운영자 입점 안내 → 입점 신청 (첫 관리자 만들기: docs/05 §1)
- [ ] 관리자 "운영 관리" → 구장 승인 → 운영자가 운영시간 등록 → 예약 탭·풋살장 탭에 구장 표시
- [ ] 토스 테스트 키 입력 후: 슬롯 선택 → 결제 → 예약 확정 → 취소 → 환불 상태 확인
- [ ] 다른 계정으로 같은 시간 예약 시도 → "방금 다른 분이 예약한 시간이에요"
- [ ] 글 작성·좋아요·댓글·팔로우·차단·신고, 1:1 채팅(두 에뮬레이터 또는 기기)
- [ ] `flutter test` 전부 통과
