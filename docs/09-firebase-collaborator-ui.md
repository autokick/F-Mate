# F-Mate Spark — 협업자가 수정한 UI 그대로 사용

## 이번 변경

Firebase 빌드에서도 MainShell의 원래 홈(숏폼)·구장·중앙 올리기·채팅·마이 UI를 실행한다.
이전 임시 FirebaseExhibitionHome(별도 4탭)은 이 릴리스에서 사용하지 않는다.
화면을 다시 그리지 않고 기존 Repo 호출을 FirebaseLegacyApi와 FirebaseChatSocket으로 연결했다.

- 홈: 원래 숏폼 피드 UI, Firestore의 공개 텍스트 게시물 표시. 실제 동영상은 아직 없음.
- 구장: 협업자가 만든 구장 카드·검색·상세·시간 선택·예약 확인 UI. 현재 4곳의 가상 시설을 시연 데이터로 제공. 실제 공공시설 수백 곳의 이전은 미완료.
- 중앙 +: 협업자가 만든 게시물 작성 UI. Spark에서는 400자 이하 공개 텍스트 게시물만 실제 저장.
- 채팅: 기존 채팅 목록·대화 말풍선 UI, Firebase 계정 간 Firestore 실시간 메시지 전송·수신.
- 마이: 기존 프로필/게시물/내 예약 화면. 닉네임, 소개, 지역, 포지션 수정 및 예약 내역 저장.
- SNS: 기존 게시물 카드·상세에서 좋아요, 댓글, 답글, 저장을 Firestore로 처리.
- 결제: 원래 예약 확인/동의 화면 다음 토스페이먼츠 공식 TEST SDK 결제창으로 이동. 실청구·실제 결제 승인/확정은 하지 않음.

현재 백엔드는 Firebase Auth + Firestore Spark와 앱에 포함한 가상 시설 예시만 사용한다.
미구현: 실제 구장 데이터 이관, 이미지·동영상 업로드/인코딩, 팔로우·차단·신고, 운영자·관리자, 실제 결제 승인, 계정 자동 삭제, 실제 푸시 발송.
미이관 기능은 EXHIBITION_UNAVAILABLE 오류를 표시하고 가짜 성공을 반환하지 않는다.

## Firebase 콘솔에서 새 규칙 게시 필요

이번 변경에는 개인별 내 예약 기록, 좋아요, 댓글, 개인 저장 목록, 프로필 수정용 추가 Firestore 보안 규칙이 포함된다.
이전 전시용 규칙만으로는 위 작업에 permission-denied 오류가 발생한다.

1. GitHub 저장소의 firestore.rules 파일 전체를 Firebase Console > 프로젝트 f-mate > Cloud Firestore > 규칙에 복사한다.
2. 반드시 새 규칙을 게시한다. 모든 접근을 허용하는 if true 규칙은 사용하지 않는다.
3. Firebase 에뮬레이터 보안 테스트를 통과한 규칙이다. 실제 배포는 별도 Google 계정 권한이 필요하며 이 작업으로 자동 배포되지 않는다.

## 빌드 및 검증

- GitHub Actions는 비밀 설정 F_MATE_GOOGLE_SERVICES_JSON을 빌드 환경에서만 사용한다. JSON은 Git에 넣지 않는다.
- Flutter 빌드 플래그: --dart-define=BACKEND=firebase --dart-define=EXHIBITION_KIOSK=true
- Android 앱 ID app.fmate; 실기기 이메일 인증/채팅/토스 테스트 인증·외부 앱 복귀는 아직 사용자가 직접 검증해야 한다.
- 원래 Spring Boot 버전은 BACKEND 지정 없이 실행되며 기존 코드를 보존한다.

주의: 무료 전시 앱에서 실제 Firebase 계정과 게시글·채팅이 저장되므로 관람객 개인정보 입력에 주의해야 한다. 5분 유휴 자동 로그아웃은 서버 저장 데이터 삭제가 아니다. GitHub 릴리스는 전시용 시험 빌드이지 정식 상용 결제 앱이 아니다.
