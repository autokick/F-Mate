// F-Mate 위젯 테스트 (가짜 서버 사용). 실행: flutter test
// ignore_for_file: avoid_relative_lib_imports

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app.dart';
import '../lib/core/services.dart';
import '../lib/core/theme.dart';
import '../lib/features/booking/booking_screen.dart';
import '../lib/features/venues/nearby_real_screen.dart';
import '../lib/features/venues/venue_detail_screen.dart';
import '../lib/features/venues/venues_screen.dart';
import 'fake_server.dart';

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

AppServices fakeServices({FakeServer? server}) =>
    AppServices.create(adapter: server ?? FakeServer(defaultRoutes), persistentTokens: false, realtime: false);

Future<void> startApp(WidgetTester tester, {FakeServer? server}) async {
  usePhoneSize(tester);
  await tester.pumpWidget(FMateApp(services: fakeServices(server: server)));
  await tester.pumpAndSettle();
}

Finder navItem(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Widget wrap(AppServices s, Widget child) =>
    AppScope(services: s, child: MaterialApp(theme: buildFmTheme(), home: child));

void main() {
  group('시작·로그인', () {
    testWidgets('서버 연결 확인 후 로그인 화면', (tester) async {
      await startApp(tester);
      expect(find.byKey(const Key('login_submit')), findsOneWidget);
    });

    testWidgets('서버에 연결할 수 없으면 안내와 다시 시도', (tester) async {
      await startApp(tester, server: FakeServer(defaultRoutes, unreachable: true));
      expect(find.text('서버에 연결할 수 없어요'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('빈 값으로 로그인하면 입력 오류', (tester) async {
      await startApp(tester);
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      expect(find.text('이메일을 입력해 주세요'), findsOneWidget);
      expect(find.text('비밀번호를 입력해 주세요'), findsOneWidget);
    });

    testWidgets('틀린 비밀번호는 서버 오류 문구를 그대로 보여준다', (tester) async {
      final server = FakeServer(defaultRoutes);
      await startApp(tester, server: server);
      await tester.enterText(find.byKey(const Key('login_email')), 'player@fmate.app');
      await tester.enterText(find.byKey(const Key('login_password')), 'abc12345');
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pumpAndSettle();
      expect(server.calls, contains('POST /api/v1/auth/login'));
      expect(find.text('이메일 또는 비밀번호가 올바르지 않아요'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('회원가입: 닉네임 형식과 필수 약관 확인', (tester) async {
      await startApp(tester);
      await tester.tap(find.byKey(const Key('go_signup')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('signup_email')), 'new@fmate.app');
      await tester.enterText(find.byKey(const Key('signup_password')), 'abc12345');
      await tester.enterText(find.byKey(const Key('signup_password_confirm')), 'abc12345');
      await tester.enterText(find.byKey(const Key('signup_nickname')), 'a b!');
      final submit = find.byKey(const Key('signup_submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('한글, 영문, 숫자, _ . 만 사용할 수 있어요'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('signup_nickname')), '화성풋살왕');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('필수 약관에 모두 동의해 주세요'), findsOneWidget);
    });
  });

  group('둘러보기', () {
    testWidgets('5개 탭과 비로그인 안내', (tester) async {
      await startApp(tester);
      await tester.tap(find.byKey(const Key('browse_button')));
      await tester.pumpAndSettle();

      for (final label in ['홈', '예약', '풋살장', '채팅', '마이']) {
        expect(navItem(label), findsOneWidget, reason: '$label 탭');
      }
      expect(find.text('로그인하고 풋살 피드를 보세요'), findsOneWidget);

      await tester.tap(navItem('예약'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('date_strip')), findsOneWidget);
      expect(find.text('화성 테스트 풋살장'), findsOneWidget, reason: '서버가 준 구장만 보여준다');

      await tester.tap(navItem('채팅'));
      await tester.pumpAndSettle();
      expect(find.text('로그인이 필요해요'), findsOneWidget);

      await tester.tap(navItem('마이'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my_login_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login_submit')), findsOneWidget);
    });
  });

  group('풋살장 탭 필터', () {
    testWidgets('필터에서 지역·실내를 고르면 적용된 조건이 칩으로 보인다', (tester) async {
      usePhoneSize(tester);
      final s = fakeServices();
      await tester.pumpWidget(wrap(s, const VenuesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('화성 테스트 풋살장'), findsOneWidget);

      await tester.tap(find.byKey(const Key('venue_filter_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '경기'));
      await tester.tap(find.widgetWithText(ChoiceChip, '실내'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('venue_filter_apply')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, '경기'), findsOneWidget);
      expect(find.widgetWithText(InputChip, '실내'), findsOneWidget);
      // 칩의 x 를 누르면 그 조건만 해제
      await tester.tap(find.descendant(of: find.widgetWithText(InputChip, '실내'), matching: find.byType(Icon)).last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, '실내'), findsNothing);
      expect(find.widgetWithText(InputChip, '경기'), findsOneWidget);
    });
  });

  group('실제 풋살장 (카카오)', () {
    testWidgets('지역으로 찾으면 목록·출처·예약 체험 버튼이 보인다', (tester) async {
      usePhoneSize(tester);
      final server = FakeServer((RequestOptions r) =>
          r.path == '/api/v1/config' ? (200, configJson(places: true)) : defaultRoutes(r));
      final s = fakeServices(server: server);
      await tester.pumpWidget(wrap(s, const NearbyRealScreen()));
      await tester.pumpAndSettle();
      // 테스트 환경에는 GPS 가 없으므로 지역 검색으로 찾는다
      await tester.enterText(find.byKey(const Key('nearby_area')), '동탄');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(server.calls, contains('GET /api/v1/places/futsal-nearby'));
      expect(find.text('동탄 실제 풋살장'), findsOneWidget);
      expect(find.text('예약 체험'), findsOneWidget);
      expect(find.text('장소 정보 제공: 카카오'), findsOneWidget);
    });
  });

  group('예약', () {
    testWidgets('날짜를 바꾸면 선택 날짜 문구가 바뀐다', (tester) async {
      usePhoneSize(tester);
      final s = fakeServices();
      await tester.pumpWidget(wrap(s, BookingScreen(today: DateTime(2026, 10, 10))));
      await tester.pumpAndSettle();
      expect(find.text('10월 10일(토)'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const Key('date_strip')), matching: find.text('12')));
      await tester.pumpAndSettle();
      expect(find.text('10월 12일(월)'), findsOneWidget);
    });

    testWidgets('구장 상세: 연속 슬롯을 고르면 합계가 계산되고 마감 슬롯은 못 고른다', (tester) async {
      usePhoneSize(tester);
      final s = fakeServices();
      final day = DateTime.now().add(const Duration(days: 2));
      await tester.pumpWidget(wrap(s, VenueDetailScreen(venueId: 1, initialDate: day)));
      await tester.pumpAndSettle();

      expect(find.text('화성 테스트 풋살장'), findsOneWidget);
      final first = find.text('19:00');
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.text('60,000원').hitTestable(), findsWidgets);

      await tester.tap(find.text('20:00'));
      await tester.pumpAndSettle();
      expect(find.text('120,000원'), findsOneWidget, reason: '19~21시 2시간');

      await tester.tap(find.text('21:00'));
      await tester.pumpAndSettle();
      expect(find.text('120,000원'), findsOneWidget, reason: '마감 슬롯은 선택되지 않는다');
      expect(find.text('마감'), findsOneWidget);
    });
  });
}
