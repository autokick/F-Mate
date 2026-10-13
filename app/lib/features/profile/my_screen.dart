import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../admin/admin_home_screen.dart';
import '../auth/verify_email_screen.dart';
import '../operator/operator_home_screen.dart';
import '../reservations/my_reservations_screen.dart';
import '../settings/settings_screen.dart';
import 'follow_list_screen.dart';
import 'post_grid.dart';
import 'profile_edit_screen.dart';
import 'user_profile_screen.dart' show ProfileHeader;

class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  int _tab = 0;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.session,
      builder: (context, _) {
        final me = services.session.me;
        if (me == null) return _guest(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(me.nickname),
            actions: [
              IconButton(
                tooltip: '설정',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await services.session.refreshMe();
              setState(() => _reload++);
            },
            child: ListView(
              children: [
                if (!me.emailVerified)
                  ListTile(
                    tileColor: const Color(0xFFFEF3C7),
                    leading: const Icon(Icons.mark_email_unread_outlined, color: Color(0xFF92400E)),
                    title: const Text('이메일 인증이 필요해요', style: TextStyle(color: Color(0xFF92400E))),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyEmailScreen())),
                  ),
                ProfileHeader(
                  name: me.nickname,
                  avatarUrl: me.avatarUrl,
                  bio: me.bio,
                  position: me.preferredPosition,
                  counts: me.counts,
                  onFollowers: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => FollowListScreen(userId: me.id, followers: true))),
                  onFollowing: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => FollowListScreen(userId: me.id, followers: false))),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileEditScreen()));
                          setState(() => _reload++);
                        },
                        child: const Text('프로필 편집'),
                      ),
                    ),
                    const SizedBox(width: FmSpace.s),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const MyReservationsScreen())),
                        child: const Text('내 예약'),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: FmSpace.s),
                if (me.isOperator || me.isModerator)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
                    child: Row(children: [
                      if (me.isOperator)
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const OperatorHomeScreen())),
                            icon: const Icon(Icons.storefront_outlined),
                            label: const Text('구장 관리'),
                          ),
                        ),
                      if (me.isOperator && me.isModerator) const SizedBox(width: FmSpace.s),
                      if (me.isModerator)
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const AdminHomeScreen())),
                            icon: const Icon(Icons.admin_panel_settings_outlined),
                            label: const Text('운영 관리'),
                          ),
                        ),
                    ]),
                  ),
                const SizedBox(height: FmSpace.s),
                DefaultTabController(
                  length: 3,
                  initialIndex: _tab,
                  child: TabBar(
                    key: const Key('profile_tabs'),
                    onTap: (i) => setState(() => _tab = i),
                    tabs: const [Tab(text: '게시물'), Tab(text: '하이라이트'), Tab(text: '저장됨')],
                  ),
                ),
                PostGrid(
                  key: ValueKey('me-$_tab-$_reload'),
                  userId: me.id,
                  highlights: _tab == 1,
                  saved: _tab == 2,
                ),
                const SizedBox(height: FmSpace.xl),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _guest(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('마이페이지')),
      body: ListView(
        padding: const EdgeInsets.all(FmSpace.l),
        children: [
          FmCard(
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: FmColors.surfaceMuted,
                  child: Icon(Icons.person_rounded, size: 36, color: FmColors.textSecondary),
                ),
                const SizedBox(width: FmSpace.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('로그인이 필요해요', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: FmSpace.xs),
                      const Text('프로필을 만들고 경기 기록을 남겨 보세요',
                          style: TextStyle(fontSize: 13, color: FmColors.textSecondary)),
                      const SizedBox(height: FmSpace.s),
                      FilledButton(
                        key: const Key('my_login_button'),
                        style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
                        onPressed: () => requireLogin(context),
                        child: const Text('로그인 / 회원가입', style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FmSpace.l),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('구장 운영자 입점 안내'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OperatorHomeScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('약관 및 정책'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PolicyListScreen())),
          ),
          const SizedBox(height: FmSpace.l),
          Center(
            child: Text('버전 ${AppConfig.appVersion} (${AppConfig.env})',
                style: const TextStyle(fontSize: 12, color: FmColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
