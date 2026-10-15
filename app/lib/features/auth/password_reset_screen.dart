import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../shared/widgets.dart';
import 'login_screen.dart';

/// 비밀번호 재설정: 이메일로 코드 받기 → 코드 + 새 비밀번호
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    setState(() => _error = null);
    final emailError = Validators.email(_email.text);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }
    try {
      await AppScope.read(context).account.requestPasswordReset(_email.text);
      if (mounted) setState(() => _codeSent = true);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _reset() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await AppScope.read(context).account.resetPassword(_email.text, _code.text, _password.text);
      if (!mounted) return;
      showFmSnack(context, '비밀번호가 바뀌었어요. 새 비밀번호로 로그인해 주세요');
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppConfig.firebaseMode) return const _FirebasePasswordResetScreen();
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 찾기')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(FmSpace.xl),
            children: [
              TextFormField(
                controller: _email,
                enabled: !_codeSent,
                keyboardType: TextInputType.emailAddress,
                decoration: fmInputDecoration(label: '가입한 이메일'),
                validator: Validators.email,
              ),
              if (!_codeSent) ...[
                const SizedBox(height: FmSpace.l),
                LoadingButton(label: '재설정 코드 받기', onPressed: _request),
              ] else ...[
                const SizedBox(height: FmSpace.m),
                const Text('가입된 이메일이라면 재설정 코드를 보냈어요. 15분 안에 입력해 주세요.',
                    style: TextStyle(fontSize: 13, color: FmColors.textSecondary)),
                const SizedBox(height: FmSpace.m),
                TextFormField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: fmInputDecoration(label: '6자리 코드'),
                  validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : '6자리 숫자를 입력해 주세요',
                ),
                const SizedBox(height: FmSpace.s),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: fmInputDecoration(label: '새 비밀번호', hint: '영문+숫자 8자 이상'),
                  validator: Validators.newPassword,
                ),
                const SizedBox(height: FmSpace.l),
                LoadingButton(label: '비밀번호 바꾸기', onPressed: _reset),
                TextButton(onPressed: () => setState(() => _codeSent = false), child: const Text('코드 다시 받기')),
              ],
              if (_error != null) ...[
                const SizedBox(height: FmSpace.m),
                AuthErrorBox(message: _error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _FirebasePasswordResetScreen extends StatefulWidget {
  const _FirebasePasswordResetScreen();

  @override
  State<_FirebasePasswordResetScreen> createState() => _FirebasePasswordResetScreenState();
}

class _FirebasePasswordResetScreenState extends State<_FirebasePasswordResetScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (Validators.email(_email.text) != null) {
      setState(() => _message = '올바른 이메일을 입력하세요');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _email.text.trim());
      if (mounted) setState(() => _message = '재설정 링크를 보냈어요. 메일함을 확인해 주세요.');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _message = '재설정 요청 실패: ${e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 재설정')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(FmSpace.xl), children: [
        const Text('Firebase에서는 이메일의 링크에서 새 비밀번호를 설정합니다.'),
        const SizedBox(height: 16),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress,
          decoration: fmInputDecoration(label: '가입 이메일')),
        if (_message != null) Padding(
          padding: const EdgeInsets.symmetric(vertical: 10), child: Text(_message!)),
        const SizedBox(height: 14),
        FilledButton(onPressed: _busy ? null : _request, child: const Text('비밀번호 재설정 링크 보내기')),
      ])),
    );
  }
}
