import 'dart:async';

import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api.dart';
import 'chat_socket.dart';
import 'config.dart';
import 'models.dart';
import 'repos.dart';
import 'session.dart';
import 'firebase_session.dart';

/// 앱 전역 서비스. AppScope.of(context) 로 꺼내 쓴다.
class AppServices {
  AppServices._(this.api, this.session, this.chatSocket, this.realtime)
      : venues = VenueRepo(api),
        reservations = ReservationRepo(api),
        media = MediaRepo(api),
        social = SocialRepo(api),
        chats = ChatRepo(api),
        notifications = NotificationRepo(api),
        account = AccountRepo(api),
        operator = OperatorRepo(api),
        admin = AdminRepo(api);

  /// adapter / persistentTokens / realtime 는 테스트용 (가짜 서버, 메모리 토큰, 소켓 끄기)
  factory AppServices.create({HttpClientAdapter? adapter, bool persistentTokens = true, bool realtime = true}) {
    final api = ApiClient(TokenStore(persistent: persistentTokens), adapter: adapter);
    return AppServices._(api, AppConfig.firebaseMode ? FirebaseSession(api) : Session(api),
        ChatSocket(api.tokens), realtime && !AppConfig.firebaseMode);
  }

  final bool realtime;

  final ApiClient api;
  final Session session;
  final ChatSocket chatSocket;
  final VenueRepo venues;
  final ReservationRepo reservations;
  final MediaRepo media;
  final SocialRepo social;
  final ChatRepo chats;
  final NotificationRepo notifications;
  final AccountRepo account;
  final OperatorRepo operator;
  final AdminRepo admin;

  /// 서버 기능 상태 (외부 키가 없는 기능은 꺼져 있음)
  final ValueNotifier<FeatureConfig> features = ValueNotifier(FeatureConfig.offline());
  /// 읽지 않은 알림 수 (홈 상단 배지)
  final ValueNotifier<int> unreadNotifications = ValueNotifier(0);

  /// '초기화면' 버튼을 누를 때마다 1씩 늘어난다 (아래 탭을 홈으로 되돌림)
  final ValueNotifier<int> goHome = ValueNotifier(0);

  /// 앱을 쓰는 중에 새로 도착한 알림 (화면 위에 잠깐 띄운다)
  final ValueNotifier<AppNotification?> incomingNotification = ValueNotifier(null);
  Timer? _unreadTimer;
  bool serverReachable = false;
  bool pushReady = false;
  String? _pushToken;

  Future<void> loadFeatures() async {
    if (AppConfig.firebaseMode) {
      // No REST server exists for the exhibition build. Feature-specific
      // capabilities are surfaced within FirebaseExhibitionHome.
      features.value = FeatureConfig.offline();
      serverReachable = true;
      return;
    }
    try {
      features.value = FeatureConfig.fromJson(await api.get('/api/v1/config'));
      serverReachable = true;
    } on ApiError {
      serverReachable = false;
    }
  }

  Future<void> refreshUnread() async {
    if (!session.isLoggedIn) {
      unreadNotifications.value = 0;
      return;
    }
    try {
      final before = unreadNotifications.value;
      final now = await notifications.unreadCount();
      unreadNotifications.value = now;
      // 새 알림이 생겼으면 가장 최근 것을 화면 위에 띄운다
      if (now > before && _unreadTimer != null) {
        final latest = await notifications.list();
        if (latest.isNotEmpty && !latest.first.read) incomingNotification.value = latest.first;
      }
    } catch (_) {
      // 배지 갱신 실패는 무시
    }
  }

  /// 로그인 후 호출: 채팅 소켓 연결 + 푸시 등록
  Future<void> onLoggedIn() async {
    if (AppConfig.firebaseMode) return;
    if (realtime) chatSocket.start();
    await refreshUnread();
    // 좋아요·댓글·팔로우 알림을 몇 초 안에 보여주기 위해 주기적으로 확인 (푸시가 없어도 동작)
    _unreadTimer?.cancel();
    if (realtime) _unreadTimer = Timer.periodic(const Duration(seconds: 8), (_) => refreshUnread());
    await _setupPush();
  }

  /// 로그아웃: 푸시 토큰을 먼저 해제한 뒤(로그인 상태여야 호출 가능) 세션을 지운다
  Future<void> logout() async {
    final token = _pushToken;
    if (token != null && session.isLoggedIn) {
      try {
        await notifications.removeDevice(token);
      } catch (_) {
        // 실패해도 로그아웃은 진행 (서버의 만료 토큰 정리 작업이 나중에 지운다)
      }
    }
    _pushToken = null;
    await session.logout();
  }

  void onLoggedOut() {
    chatSocket.stop();
    _unreadTimer?.cancel();
    _unreadTimer = null;
    unreadNotifications.value = 0;
    incomingNotification.value = null;
  }

  /// FCM: PUSH_ENABLED 빌드 + google-services.json 이 있을 때만. 실패해도 앱은 계속 동작(앱 내 알림 목록 사용).
  Future<void> _setupPush() async {
    if (!AppConfig.pushEnabled || !features.value.push) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final perm = await messaging.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';
      final token = await messaging.getToken();
      if (token == null) return;
      await notifications.registerDevice(token, platform);
      _pushToken = token;
      if (!pushReady) {
        // 리스너는 앱 실행 중 한 번만 등록 (다시 로그인해도 중복 등록하지 않음)
        messaging.onTokenRefresh.listen((t) {
          if (!session.isLoggedIn) return;
          _pushToken = t;
          notifications.registerDevice(t, platform).catchError((_) {});
        });
        FirebaseMessaging.onMessage.listen((_) => refreshUnread());
      }
      pushReady = true;
    } catch (e) {
      debugPrint('푸시 초기화 실패(앱 내 알림만 사용): $e');
    }
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 가 위젯 트리에 없습니다');
    return scope!.services;
  }

  /// build 밖(콜백 등)에서 의존성 등록 없이 꺼낼 때
  static AppServices read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
