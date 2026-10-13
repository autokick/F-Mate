import 'package:flutter/material.dart';

import 'core/config.dart';
import 'core/services.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/profile_setup_screen.dart';
import 'features/auth/verify_email_screen.dart';
import 'features/shell/main_shell.dart';
import 'shared/widgets.dart';

class FMateApp extends StatefulWidget {
  const FMateApp({super.key, this.services});

  /// 테스트에서 주입 가능
  final AppServices? services;

  @override
  State<FMateApp> createState() => _FMateAppState();
}

class _FMateAppState extends State<FMateApp> {
  late final AppServices services = widget.services ?? AppServices.create();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'F-Mate',
        debugShowCheckedModeBanner: false,
        theme: buildFmTheme(),
        home: const AuthGate(),
      ),
    );
  }
}

/// 시작 화면 → (서버 연결 확인 · 저장된 로그인 복원) → 로그인 / 프로필 설정 / 메인
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;
  SessionStatus _last = SessionStatus.unknown;
  late AppServices _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() => _ready = false);
    await _services.loadFeatures();
    if (_services.serverReachable) await _services.session.restore();
    _services.session.removeListener(_onSession);   // 다시 시도 시 중복 등록 방지
    _services.session.addListener(_onSession);
    _onSession();
    if (mounted) setState(() => _ready = true);
  }

  void _onSession() {
    final s = _services.session.status;
    if (s == _last) return;
    _last = s;
    if (s == SessionStatus.loggedIn) {
      _services.onLoggedIn();
    } else if (s == SessionStatus.loggedOut) {
      _services.onLoggedOut();
    }
  }

  @override
  void dispose() {
    _services.session.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const _Splash();
    if (!_services.serverReachable) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ErrorState(
              title: '서버에 연결할 수 없어요',
              message: '네트워크 상태를 확인해 주세요.\n(개발 중이라면 서버 실행 여부와 API_BASE_URL=${AppConfig.apiBaseUrl} 를 확인하세요)',
              onRetry: _start,
            ),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: _services.session,
      builder: (context, _) {
        final session = _services.session;
        // 사용자가 바뀌면(게스트→로그인, 계정 전환) 탭 화면 상태를 새로 만든다
        if (session.isLoggedIn) {
          if (session.me!.needsProfile) return const ProfileSetupScreen();
          return MainShell(key: ValueKey('user-${session.me!.id}'));
        }
        if (session.guest) return const MainShell(key: ValueKey('guest'));
        return const LoginScreen();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: FmColors.brand, borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.sports_soccer, color: Colors.white, size: 44),
            ),
            const SizedBox(height: FmSpace.l),
            const Text('F-Mate', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: FmSpace.xl),
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
          ],
        ),
      ),
    );
  }
}

/// 로그인이 필요한 동작 전에 호출. 비로그인이면 로그인 화면으로 보낸다.
bool requireLogin(BuildContext context) {
  final s = AppScope.read(context).session;
  if (s.isLoggedIn) return true;
  Navigator.of(context).popUntil((r) => r.isFirst);
  s.stopBrowsing();
  return false;
}

/// 예약·글쓰기 등 이메일 인증이 필요한 동작 전에 호출
Future<bool> requireVerified(BuildContext context) async {
  if (!requireLogin(context)) return false;
  final services = AppScope.read(context);
  if (services.session.me?.emailVerified == true) return true;
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const VerifyEmailScreen()));
  return ok == true;
}
