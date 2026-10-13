import 'package:flutter/foundation.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';

enum SessionStatus { unknown, loggedOut, loggedIn }

/// 로그인 상태. 토큰은 TokenStore(보안 저장소)에, 내 정보(Me)는 메모리에 둔다.
class Session extends ChangeNotifier {
  Session(this.api) {
    api.onSessionExpired = _expired;
  }

  final ApiClient api;
  SessionStatus status = SessionStatus.unknown;
  Me? me;
  bool guest = false;

  /// 로그아웃 직후 등 사용자에게 한 번 보여줄 안내
  String? notice;

  bool get isLoggedIn => status == SessionStatus.loggedIn && me != null;

  Future<void> restore() async {
    await api.tokens.load();
    if (api.tokens.access == null) {
      status = SessionStatus.loggedOut;
      notifyListeners();
      return;
    }
    try {
      me = Me.fromJson(await api.get('/api/v1/me'));
      status = SessionStatus.loggedIn;
    } on ApiError catch (e) {
      if (e.isNetwork) {
        // 오프라인: 토큰은 유지하고 로그아웃 상태로 보여주지 않는다
        status = SessionStatus.loggedOut;
      } else {
        await api.tokens.clear();
        status = SessionStatus.loggedOut;
      }
    }
    notifyListeners();
  }

  Future<void> _applyAuth(dynamic res) async {
    final m = asMap(res);
    await api.tokens.save(asStr(m['accessToken']), asStr(m['refreshToken']));
    me = Me.fromJson(await api.get('/api/v1/me'));
    status = SessionStatus.loggedIn;
    guest = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final res = await api.post('/api/v1/auth/login',
        body: {'email': email.trim(), 'password': password, 'deviceLabel': deviceLabel()});
    await _applyAuth(res);
  }

  Future<void> signup({
    required String email,
    required String password,
    required String nickname,
    required Map<String, bool> consents,
  }) async {
    final res = await api.post('/api/v1/auth/signup', body: {
      'email': email.trim(),
      'password': password,
      'nickname': nickname.trim(),
      'consents': consents.entries.map((e) => {'type': e.key, 'agreed': e.value}).toList(),
      'termsVersion': '2026-10',
      'deviceLabel': deviceLabel(),
    });
    await _applyAuth(res);
  }

  Future<void> socialLogin(String provider, String token) async {
    final res = await api.post('/api/v1/auth/social/${provider.toLowerCase()}',
        body: {'token': token, 'deviceLabel': deviceLabel()});
    await _applyAuth(res);
  }

  Future<void> refreshMe() async {
    if (api.tokens.access == null) return;
    me = Me.fromJson(await api.get('/api/v1/me'));
    notifyListeners();
  }

  void updateMe(Me value) {
    me = value;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      if (api.tokens.access != null) {
        await api.post('/api/v1/auth/logout', body: {'refreshToken': api.tokens.refresh});
      }
    } catch (_) {
      // 서버에 닿지 않아도 기기에서는 로그아웃한다
    }
    await clearLocal();
  }

  Future<void> clearLocal() async {
    await api.tokens.clear();
    me = null;
    status = SessionStatus.loggedOut;
    guest = false;
    notifyListeners();
  }

  void browseAsGuest() {
    guest = true;
    notifyListeners();
  }

  void stopBrowsing() {
    guest = false;
    notifyListeners();
  }

  void _expired() {
    if (status != SessionStatus.loggedIn) return;
    me = null;
    status = SessionStatus.loggedOut;
    notice = '로그인이 만료되었어요. 다시 로그인해 주세요.';
    notifyListeners();
  }

  static String deviceLabel() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      default:
        return 'Other';
    }
  }
}
