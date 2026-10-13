import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../shared/widgets.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

/// 소셜 로그인으로 처음 가입했거나 필수 약관 동의가 없는 계정: 닉네임·약관 동의를 받는다.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  Map<ConsentItem, bool> _consents = {for (final c in ConsentItem.values) c: false};
  String? _error;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_nickname.text.isEmpty) _nickname.text = AppScope.of(context).session.me?.nickname ?? '';
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!ConsentItem.values.where((c) => c.isRequired).every((c) => _consents[c] == true)) {
      setState(() => _error = '필수 약관에 모두 동의해 주세요');
      return;
    }
    final s = AppScope.read(context);
    try {
      await s.account.updateProfile({'nickname': _nickname.text.trim()});
      final me = await s.account.saveConsents({for (final e in _consents.entries) e.key.code: e.value});
      s.session.updateMe(me);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필 설정'),
        actions: [
          TextButton(onPressed: () => AppScope.read(context).logout(), child: const Text('로그아웃')),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(FmSpace.xl),
            children: [
              const Text('F-Mate 에서 쓸 닉네임을 정하고\n약관에 동의해 주세요',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4)),
              const SizedBox(height: FmSpace.xl),
              TextFormField(
                controller: _nickname,
                maxLength: 20,
                decoration: fmInputDecoration(label: '닉네임', hint: '한글·영문·숫자 2~20자'),
                validator: Validators.nickname,
              ),
              const SizedBox(height: FmSpace.m),
              ConsentList(values: _consents, onChanged: (v) => setState(() => _consents = v)),
              if (_error != null) ...[
                const SizedBox(height: FmSpace.m),
                AuthErrorBox(message: _error!),
              ],
              const SizedBox(height: FmSpace.xl),
              LoadingButton(label: '시작하기', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
