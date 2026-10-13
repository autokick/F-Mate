import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../shared/widgets.dart';
import '../settings/policy_screen.dart';
import 'login_screen.dart';

/// 약관 항목. 서버 consents.consent_type 과 이름을 맞춘다.
enum ConsentItem {
  age14('AGE_14', '만 14세 이상입니다', true, null),
  terms('TERMS', '서비스 이용약관 동의', true, PolicyKind.terms),
  privacy('PRIVACY', '개인정보 수집·이용 동의', true, PolicyKind.privacy),
  location('LOCATION', '위치기반서비스 이용약관 동의', false, PolicyKind.location),
  marketing('MARKETING', '마케팅 정보 수신 동의', false, null);

  const ConsentItem(this.code, this.label, this.isRequired, this.policy);

  final String code;
  final String label;
  final bool isRequired;
  final PolicyKind? policy;
}

/// 약관 동의 체크 목록 (가입 화면·소셜 가입 후 프로필 설정에서 공용)
class ConsentList extends StatelessWidget {
  const ConsentList({super.key, required this.values, required this.onChanged});

  final Map<ConsentItem, bool> values;
  final void Function(Map<ConsentItem, bool>) onChanged;

  bool get _all => values.values.every((v) => v);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: FmColors.border), borderRadius: BorderRadius.circular(FmRadius.card)),
      child: Column(
        children: [
          CheckboxListTile(
            key: const Key('consent_all'),
            value: _all,
            onChanged: (v) => onChanged({for (final c in ConsentItem.values) c: v ?? false}),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('전체 동의', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 1),
          for (final c in ConsentItem.values)
            CheckboxListTile(
              key: Key('consent_${c.code}'),
              value: values[c],
              onChanged: (v) => onChanged({...values, c: v ?? false}),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text('${c.isRequired ? '[필수]' : '[선택]'} ${c.label}', style: const TextStyle(fontSize: 14)),
              secondary: c.policy == null
                  ? null
                  : IconButton(
                      tooltip: '${c.label} 전문 보기',
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => PolicyScreen(kind: c.policy!))),
                    ),
            ),
        ],
      ),
    );
  }
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _nickname = TextEditingController();
  Map<ConsentItem, bool> _consents = {for (final c in ConsentItem.values) c: false};
  bool _obscure = true;
  String? _error;

  bool get _requiredChecked => ConsentItem.values.where((c) => c.isRequired).every((c) => _consents[c] == true);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_requiredChecked) {
      setState(() => _error = '필수 약관에 모두 동의해 주세요');
      return;
    }
    final services = AppScope.read(context);
    try {
      await services.session.signup(
        email: _email.text,
        password: _password.text,
        nickname: _nickname.text,
        consents: {for (final e in _consents.entries) e.key.code: e.value},
      );
      if (!mounted) return;
      // 가입되면 AuthGate 가 메인 화면으로 바꾼다. 이 화면은 닫는다.
      Navigator.of(context).popUntil((r) => r.isFirst);
      showFmSnack(context, '가입되었어요! 메일로 받은 인증 코드를 입력하면 예약할 수 있어요.');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.fieldErrors.isNotEmpty ? e.fieldErrors.values.first : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(FmSpace.xl),
            children: [
              TextFormField(
                key: const Key('signup_email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: fmInputDecoration(label: '이메일', hint: '인증 코드를 받을 주소'),
                validator: Validators.email,
              ),
              const SizedBox(height: FmSpace.m),
              TextFormField(
                key: const Key('signup_password'),
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: fmInputDecoration(
                  label: '비밀번호',
                  hint: '영문+숫자 8자 이상',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? '비밀번호 보기' : '비밀번호 숨기기',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: Validators.newPassword,
              ),
              const SizedBox(height: FmSpace.m),
              TextFormField(
                key: const Key('signup_password_confirm'),
                controller: _passwordConfirm,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                decoration: fmInputDecoration(label: '비밀번호 확인'),
                validator: Validators.confirmPassword(() => _password.text),
              ),
              const SizedBox(height: FmSpace.m),
              TextFormField(
                key: const Key('signup_nickname'),
                controller: _nickname,
                textInputAction: TextInputAction.done,
                maxLength: 20,
                decoration: fmInputDecoration(label: '닉네임', hint: '한글·영문·숫자 2~20자'),
                validator: Validators.nickname,
              ),
              const SizedBox(height: FmSpace.l),
              ConsentList(values: _consents, onChanged: (v) => setState(() => _consents = v)),
              if (_error != null) ...[
                const SizedBox(height: FmSpace.m),
                AuthErrorBox(message: _error!),
              ],
              const SizedBox(height: FmSpace.xl),
              LoadingButton(key: const Key('signup_submit'), label: '가입하기', onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
