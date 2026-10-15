import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../shared/widgets.dart';
import 'password_reset_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = AppScope.read(context).session;
      final notice = session.notice;
      if (notice != null && mounted) {
        session.notice = null;
        showFmSnack(context, notice);
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await AppScope.read(context).session.login(_email.text, _password.text);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(FmSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: FmSpace.xxl),
                      TextFormField(
                        key: const Key('login_email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: fmInputDecoration(label: '이메일', hint: 'name@example.com'),
                        validator: Validators.email,
                      ),
                      const SizedBox(height: FmSpace.m),
                      TextFormField(
                        key: const Key('login_password'),
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: fmInputDecoration(
                          label: '비밀번호',
                          suffixIcon: IconButton(
                            tooltip: _obscure ? '비밀번호 보기' : '비밀번호 숨기기',
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: Validators.loginPassword,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: FmSpace.m),
                        AuthErrorBox(message: _error!),
                      ],
                      const SizedBox(height: FmSpace.xl),
                      LoadingButton(key: const Key('login_submit'), label: '로그인', onPressed: _submit),
                      const SizedBox(height: FmSpace.s),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const PasswordResetScreen())),
                            child: const Text('비밀번호 찾기'),
                          ),
                          const Text('·', style: TextStyle(color: FmColors.textSecondary)),
                          TextButton(
                            key: const Key('go_signup'),
                            onPressed: () =>
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignupScreen())),
                            child: const Text('회원가입'),
                          ),
                        ],
                      ),
                      // 소셜 로그인: 서버 검증은 구현되어 있고, 앱 SDK 연결은 각 공급자 키 발급 후 진행 (docs/03)
                      const SizedBox(height: FmSpace.xl),
                      OutlinedButton(
                        key: const Key('browse_button'),
                        onPressed: services.session.browseAsGuest,
                        child: const Text('로그인 없이 둘러보기'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: FmColors.brand, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.sports_soccer, color: Colors.white, size: 40),
        ),
        const SizedBox(height: FmSpace.l),
        Semantics(
          header: true,
          child: const Text('F-Mate',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: FmColors.textPrimary)),
        ),
        const SizedBox(height: FmSpace.xs),
        const Text('풋살장 예약부터 팀원 찾기까지', style: TextStyle(fontSize: 15, color: FmColors.textSecondary)),
      ],
    );
  }
}

/// 인증 화면 공통 오류 상자
class AuthErrorBox extends StatelessWidget {
  const AuthErrorBox({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(FmSpace.m),
        decoration: BoxDecoration(color: FmColors.dangerSoft, borderRadius: BorderRadius.circular(FmRadius.control)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: FmColors.danger, size: 20),
            const SizedBox(width: FmSpace.s),
            Expanded(
              child: Text(message,
                  key: const Key('auth_error'),
                  style: const TextStyle(fontSize: 13, height: 1.4, color: FmColors.danger)),
            ),
          ],
        ),
      ),
    );
  }
}
