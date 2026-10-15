import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'api.dart';
import 'models.dart';
import 'session.dart';

/// Firebase-specific authentication; the existing Spring/JWT Session is left
/// intact for the default build. Firestore authorization uses Firebase UID,
/// never this app-only numeric display ID.
class FirebaseSession extends Session {
  FirebaseSession(super.api);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Future<void> restore() async {
    final user = _auth.currentUser;
    if (user == null) {
      _loggedOut();
      return;
    }
    try {
      await _loadUser(user);
    } on ApiError catch (e) {
      _loggedOut();
      notice = 'Firebase 로그인 복원에 실패했어요: ${e.message}';
    }
  }

  @override
  Future<void> login(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (result.user == null) throw ApiError('AUTH_FAILED', '로그인에 실패했어요');
      await _loadUser(result.user!);
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    } on FirebaseException catch (e) {
      throw _firestoreError(e);
    }
  }

  @override
  Future<void> signup({
    required String email,
    required String password,
    required String nickname,
    required Map<String, bool> consents,
  }) async {
    if (consents['AGE_14'] != true ||
        consents['TERMS'] != true ||
        consents['PRIVACY'] != true) {
      throw ApiError('CONSENT_REQUIRED', '필수 약관에 동의해야 가입할 수 있어요');
    }
    final cleanNick = nickname.trim();
    if (cleanNick.length < 2 || cleanNick.length > 20) {
      throw ApiError('INVALID_NICKNAME', '닉네임은 2~20자여야 해요');
    }
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) throw ApiError('AUTH_FAILED', '계정 생성에 실패했어요');
      // Private consent records and public nickname live in different docs.
      // Neither contains passwords or API credentials.
      await user.updateDisplayName(cleanNick);
      final batch = _db.batch();
      batch.set(_db.collection('profiles').doc(user.uid), {
        'nickname': cleanNick,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(_db.collection('private_users').doc(user.uid), {
        'consents': consents,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      await user.sendEmailVerification();
      await _loadUser(_auth.currentUser ?? user);
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    } on FirebaseException catch (e) {
      throw _firestoreError(e);
    }
  }

  @override
  Future<void> socialLogin(String provider, String token) async {
    throw ApiError('NOT_IMPLEMENTED', 'Firebase 전시 버전은 이메일 로그인을 우선 지원합니다');
  }

  @override
  Future<void> refreshMe() async {
    final user = _auth.currentUser;
    if (user == null) {
      _loggedOut();
      return;
    }
    try {
      await user.reload();
      final latest = _auth.currentUser ?? user;
      await latest.getIdToken(true);
      await _loadUser(latest);
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    } on FirebaseException catch (e) {
      throw _firestoreError(e);
    }
  }

  @override
  Future<void> logout() async {
    await _auth.signOut();
    _loggedOut();
  }

  @override
  Future<void> clearLocal() => logout();

  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw ApiError('UNAUTHENTICATED', '로그인이 필요합니다');
    if (user.emailVerified) return;
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    }
  }

  Future<void> _loadUser(User user) async {
    try {
      final profile = await _db.collection('profiles').doc(user.uid).get();
      final nickname = (profile.data()?['nickname'] as String?)?.trim();
      me = Me(
        // Stable UI-only compatibility ID. Security rules use the full UID.
        id: _numericUiId(user.uid),
        email: user.email,
        emailVerified: user.emailVerified,
        role: 'USER',
        nickname: nickname?.isNotEmpty == true
            ? nickname!
            : (user.displayName ?? '체험 회원'),
        isPrivate: false,
        counts: Counts(0, 0, 0),
        hasPassword: true,
        socialProviders: const [],
        consents: const {},
        operatorVenueIds: const [],
        needsProfile: false,
      );
      status = SessionStatus.loggedIn;
      guest = false;
      notifyListeners();
    } on FirebaseException catch (e) {
      throw _firestoreError(e);
    }
  }

  void _loggedOut() {
    me = null;
    status = SessionStatus.loggedOut;
    guest = false;
    notifyListeners();
  }

  static int _numericUiId(String uid) {
    // This is NOT an authorization identifier; only used by legacy UI keys.
    var number = 0;
    for (final rune in uid.runes) {
      number = ((number * 31) + rune) & 0x7fffffff;
    }
    return number;
  }

  static ApiError _authError(FirebaseAuthException e) {
    final message = switch (e.code) {
      'invalid-email' => '이메일 형식을 확인해 주세요',
      'email-already-in-use' => '이미 가입된 이메일이에요',
      'weak-password' => '비밀번호가 너무 약해요',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => '이메일 또는 비밀번호가 맞지 않아요',
      'too-many-requests' => '요청이 너무 많아요. 잠시 후 다시 시도해 주세요',
      'network-request-failed' => '인터넷 연결을 확인해 주세요',
      'user-disabled' => '이용이 중지된 계정이에요',
      _ => '인증에 실패했어요 (${e.code})',
    };
    return ApiError('FIREBASE_AUTH', message);
  }

  static ApiError _firestoreError(FirebaseException e) {
    if (e.code == 'permission-denied') {
      return ApiError(
        'FIRESTORE_RULES',
        'Firestore 접근이 차단됐어요. 전시용 보안 규칙을 게시했는지 확인해 주세요',
      );
    }
    return ApiError('FIRESTORE', 'Firebase 데이터 처리에 실패했어요 (${e.code})');
  }
}
