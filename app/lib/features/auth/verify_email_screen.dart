import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/firebase_session.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'login_screen.dart';

/// 이메일 인증 코드(6자리) 입력. 성공하면 true 로 닫힌다.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _error = null);
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _error = '6자리 숫자를 입력해 주세요');
      return;
    }
    final s = AppScope.read(context);
    try {
      await s.account.verifyEmail(_code.text);
      await s.session.refreshMe();
      if (!mounted) return;
      showFmSnack(context, '이메일 인증이 완료되었어요');
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _resend() async {
    try {
      await AppScope.read(context).account.resendVerification();
      if (mounted) showFmSnack(context, '인증 코드를 다시 보냈어요. 메일함(스팸함 포함)을 확인해 주세요');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppConfig.firebaseMode) return const _FirebaseLinkVerifyScreen();
    final email = AppScope.of(context).session.me?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('이메일 인증')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FmSpace.xl),
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 56, color: FmColors.brandDark),
            const SizedBox(height: FmSpace.l),
            Text('$email 로 보낸\n6자리 인증 코드를 입력해 주세요',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
            const SizedBox(height: FmSpace.s),
            const Text('예약·게시물 작성 등은 이메일 인증 후 이용할 수 있어요.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: FmColors.textSecondary)),
            const SizedBox(height: FmSpace.xl),
            TextField(
              key: const Key('verify_code'),
              controller: _code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
              decoration: fmInputDecoration(label: '인증 코드'),
              onSubmitted: (_) => _verify(),
            ),
            if (_error != null) ...[
              const SizedBox(height: FmSpace.s),
              AuthErrorBox(message: _error!),
            ],
            const SizedBox(height: FmSpace.l),
            LoadingButton(label: '인증하기', onPressed: _verify),
            const SizedBox(height: FmSpace.s),
            TextButton(onPressed: _resend, child: const Text('코드 다시 받기')),
          ],
        ),
      ),
    );
  }
}


/// Firebase sends a clickable verification link, not the Spring Boot 6-digit code.
class _FirebaseLinkVerifyScreen extends StatefulWidget {
  const _FirebaseLinkVerifyScreen();

  @override
  State<_FirebaseLinkVerifyScreen> createState() => _FirebaseLinkVerifyScreenState();
}

class _FirebaseLinkVerifyScreenState extends State<_FirebaseLinkVerifyScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function(FirebaseSession session) task) async {
    setState(() { _busy = true; _error = null; });
    try {
      await task(AppScope.read(context).session as FirebaseSession);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '요청 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AppScope.of(context).session.me?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase 이메일 인증')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(FmSpace.xl), children: [
        const Icon(Icons.mark_email_read_outlined, size: 64, color: FmColors.brandDark),
        const SizedBox(height: 18),
        Text('$email 주소로 보낸 인증 메일의 링크를 눌러주세요.',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        const Text('메일 앱에서 링크를 연 뒤 이 화면으로 돌아와 인증 확인을 누르세요. (스팸함도 확인)',
          textAlign: TextAlign.center),
        const SizedBox(height: 18),
        if (_error != null) AuthErrorBox(message: _error!),
        FilledButton(
          onPressed: _busy ? null : () => _run((session) async {
            await session.refreshMe();
            if (!mounted) return;
            if (session.me?.emailVerified == true) {
              Navigator.of(context).pop(true);
            } else {
              setState(() => _error = '아직 인증되지 않았어요. 메일의 인증 링크를 먼저 열어주세요.');
            }
          }),
          child: const Text('이메일 인증 확인'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _run((session) async {
            await session.resendEmailVerification();
            if (mounted) showFmSnack(context, '인증 메일을 다시 보냈어요');
          }),
          child: const Text('인증 링크 다시 보내기'),
        ),
      ])),
    );
  }
}
