import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import '../profile/follow_list_screen.dart';
import 'policy_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final me = s.session.me;
    Widget tile(IconData icon, String title, Widget page) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          const SectionTitle('계정'),
          if (me?.email != null)
            ListTile(leading: const Icon(Icons.alternate_email_rounded), title: Text(me!.email!), subtitle: Text(me.emailVerified ? '인증 완료' : '인증 필요')),
          if (me?.hasPassword == true) tile(Icons.lock_outline_rounded, '비밀번호 변경', const ChangePasswordScreen()),
          tile(Icons.notifications_none_rounded, '알림 설정', const NotificationSettingsScreen()),
          tile(Icons.person_add_alt_outlined, '팔로우 요청', const FollowRequestsScreen()),
          tile(Icons.block_rounded, '차단한 사용자', const BlockedUsersScreen()),
          const SectionTitle('정보'),
          tile(Icons.description_outlined, '약관 및 정책', const PolicyListScreen()),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('앱 정보'),
            subtitle: Text('버전 ${AppConfig.appVersion}'),
          ),
          const SectionTitle('기타'),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('로그아웃'),
            onTap: () async {
              if (!await confirmDialog(context, title: '로그아웃할까요?', confirm: '로그아웃')) return;
              await s.logout();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined, color: FmColors.danger),
            title: const Text('회원 탈퇴', style: TextStyle(color: FmColors.danger)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
          ),
          const SizedBox(height: FmSpace.xl),
        ],
      ),
    );
  }
}

class PolicyListScreen extends StatelessWidget {
  const PolicyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('약관 및 정책')),
      body: ListView(children: [
        for (final k in PolicyKind.values)
          ListTile(
            title: Text(PolicyScreen.title(k)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PolicyScreen(kind: k))),
          ),
      ]),
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  static const _labels = {
    'reservation': ('예약·결제', '예약 확정, 취소, 환불 알림'),
    'social': ('소셜', '팔로우, 좋아요, 댓글 알림'),
    'chat': ('채팅', '새 메시지 알림'),
    'marketing': ('이벤트·혜택', '마케팅 정보 수신 (선택)'),
  };
  Map<String, bool>? _values;

  Future<void> _set(String k, bool v) async {
    final next = {...?_values, k: v};
    setState(() => _values = next);
    try {
      await AppScope.read(context).account.saveNotificationSettings(next);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: AsyncBody<Map<String, bool>>(
        load: () async => _values = await s.account.notificationSettings(),
        builder: (context, _, reload) => ListView(children: [
          if (!s.features.value.push || !s.pushReady)
            const Padding(
              padding: EdgeInsets.all(FmSpace.l),
              child: NotConnectedBanner(message: '새 알림은 앱을 쓰는 동안 화면 아래와 알림 목록에 바로 표시돼요.'),
            ),
          for (final e in _labels.entries)
            SwitchListTile(
              title: Text(e.value.$1),
              subtitle: Text(e.value.$2),
              value: _values?[e.key] ?? false,
              onChanged: (v) => _set(e.key, v),
            ),
        ]),
      ),
    );
  }
}

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).social;
    return Scaffold(
      appBar: AppBar(title: const Text('팔로우 요청')),
      body: AsyncBody<List<UserSummary>>(
        key: ValueKey(_reload),
        load: s.followRequests,
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.person_add_alt_outlined, title: '받은 팔로우 요청이 없어요', message: '비공개 계정일 때 요청이 여기에 모여요.'),
        builder: (context, list, reload) => ListView(children: [
          for (final u in list)
            UserTile(
              user: u,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                  onPressed: () async {
                    await s.acceptRequest(u.id);
                    if (mounted) setState(() => _reload++);
                  },
                  child: const Text('수락'),
                ),
                TextButton(
                  onPressed: () async {
                    await s.rejectRequest(u.id);
                    if (mounted) setState(() => _reload++);
                  },
                  child: const Text('거절', style: TextStyle(color: FmColors.textSecondary)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).social;
    return Scaffold(
      appBar: AppBar(title: const Text('차단한 사용자')),
      body: AsyncBody<List<UserSummary>>(
        key: ValueKey(_reload),
        load: s.blocks,
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.block_rounded, title: '차단한 사용자가 없어요'),
        builder: (context, list, reload) => ListView(children: [
          for (final u in list)
            ListTile(
              leading: AppAvatar(url: u.avatarUrl, name: u.nickname),
              title: Text(u.nickname),
              trailing: OutlinedButton(
                onPressed: () async {
                  try {
                    await s.unblock(u.id);
                    if (mounted) setState(() => _reload++);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('해제'),
              ),
            ),
        ]),
      ),
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final s = AppScope.read(context);
    try {
      await s.account.changePassword(_current.text, _next.text);
      // 서버가 모든 기기의 로그인을 끊었으므로 다시 로그인해야 한다
      await s.session.clearLocal();
      s.session.notice = '비밀번호를 바꿨어요. 새 비밀번호로 다시 로그인해 주세요.';
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      if (mounted) showFmSnack(context, e.code == 'INVALID_CREDENTIALS' ? '현재 비밀번호가 맞지 않아요' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 변경')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(FmSpace.l), children: [
          TextFormField(controller: _current, obscureText: true, decoration: fmInputDecoration(label: '현재 비밀번호'), validator: Validators.loginPassword),
          const SizedBox(height: FmSpace.m),
          TextFormField(controller: _next, obscureText: true, decoration: fmInputDecoration(label: '새 비밀번호', hint: '영문+숫자 8자 이상'), validator: Validators.newPassword),
          const SizedBox(height: FmSpace.m),
          TextFormField(controller: _confirm, obscureText: true, decoration: fmInputDecoration(label: '새 비밀번호 확인'), validator: Validators.confirmPassword(() => _next.text)),
          const SizedBox(height: FmSpace.s),
          const Text('바꾸면 모든 기기에서 로그아웃돼요.', style: TextStyle(fontSize: 13, color: FmColors.textSecondary)),
          const SizedBox(height: FmSpace.l),
          LoadingButton(label: '변경하기', onPressed: _save),
        ]),
      ),
    );
  }
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _understood = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final s = AppScope.read(context);
    if (!_understood) {
      showFmSnack(context, '안내 내용을 확인해 주세요');
      return;
    }
    if (!await confirmDialog(context, title: '정말 탈퇴할까요?', message: '되돌릴 수 없어요.', confirm: '탈퇴', destructive: true)) return;
    try {
      await s.account.deleteAccount(s.session.me?.hasPassword == true ? _password.text : null);
      await s.session.clearLocal();
      s.session.notice = '탈퇴가 완료되었어요. 그동안 이용해 주셔서 감사합니다.';
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPassword = AppScope.of(context).session.me?.hasPassword == true;
    return Scaffold(
      appBar: AppBar(title: const Text('회원 탈퇴')),
      body: ListView(padding: const EdgeInsets.all(FmSpace.l), children: [
        const Text('탈퇴하면', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: FmSpace.s),
        const Text(
          '• 프로필, 게시물, 댓글, 좋아요, 팔로우, 영상이 모두 삭제돼요.\n'
          '• 보낸 채팅 메시지는 "삭제된 메시지"로 바뀌어요.\n'
          '• 결제·예약 기록은 법령에 따라 개인을 알 수 없는 형태로 일정 기간 보관돼요.\n'
          '• 진행 중인 예약이나 환불이 있으면 먼저 처리해야 탈퇴할 수 있어요.',
          style: TextStyle(fontSize: 14, height: 1.7),
        ),
        const SizedBox(height: FmSpace.l),
        if (hasPassword)
          TextField(controller: _password, obscureText: true, decoration: fmInputDecoration(label: '비밀번호 확인')),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _understood,
          onChanged: (v) => setState(() => _understood = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('안내 내용을 모두 확인했어요'),
        ),
        const SizedBox(height: FmSpace.l),
        LoadingButton(label: '탈퇴하기', onPressed: _delete),
      ]),
    );
  }
}
