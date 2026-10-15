import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../admin/admin_home_screen.dart';
import '../auth/verify_email_screen.dart';
import '../notifications/notifications_screen.dart';
import '../operator/operator_home_screen.dart';
import '../reservations/my_reservations_screen.dart';
import '../reservations/reservation_detail_screen.dart';
import '../settings/settings_screen.dart';
import 'follow_list_screen.dart';
import 'post_grid.dart';
import 'profile_edit_screen.dart';
import 'user_profile_screen.dart' show ProfileHeader;

/// 지역 코드 → 표시 이름 (예: 11260 → 서울)
String? regionLabelOf(String? code) {
  if (code == null || code.length < 2) return null;
  final prefix = code.substring(0, 2);
  for (final r in kRegions) {
    if (r.codes.contains(prefix)) return r.label;
  }
  return null;
}

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
              ValueListenableBuilder<int>(
                valueListenable: services.unreadNotifications,
                builder: (context, count, _) => IconButton(
                  key: const Key('notifications_button'),
                  tooltip: count > 0 ? '알림 $count개' : '알림',
                  icon: Badge(
                    isLabelVisible: count > 0,
                    smallSize: 8,
                    backgroundColor: const Color(0xFFE5484D),
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                ),
              ),
              IconButton(
                tooltip: '설정',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await services.session.refreshMe();
              await services.refreshUnread();
              setState(() => _reload++);
            },
            child: ListView(
              children: [
                if (!me.emailVerified)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(FmSpace.page, 0, FmSpace.page, FmSpace.s),
                    child: Material(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(FmRadius.control),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FmRadius.control)),
                        leading: const Icon(Icons.mark_email_unread_outlined, color: Color(0xFF92400E)),
                        title: const Text('이메일 인증을 마치면 예약과 게시물 올리기를 할 수 있어요',
                            style: TextStyle(fontSize: 14, color: Color(0xFF92400E))),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF92400E)),
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyEmailScreen())),
                      ),
                    ),
                  ),
                ProfileHeader(
                  name: me.nickname,
                  avatarUrl: me.avatarUrl,
                  bio: me.bio,
                  position: me.preferredPosition,
                  regionLabel: regionLabelOf(me.regionCode),
                  counts: me.counts,
                  onFollowers: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => FollowListScreen(userId: me.id, followers: true))),
                  onFollowing: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => FollowListScreen(userId: me.id, followers: false))),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FmSpace.page),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 42)),
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
                        key: const Key('my_reservations'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 42)),
                        onPressed: () async {
                          await Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const MyReservationsScreen()));
                          setState(() => _reload++);
                        },
                        child: const Text('내 예약'),
                      ),
                    ),
                  ]),
                ),
                _UpcomingMatch(key: ValueKey('upcoming-$_reload')),
                if (me.isOperator || me.isModerator)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.m, FmSpace.page, 0),
                    child: Row(children: [
                      if (me.isOperator)
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 42)),
                            onPressed: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const OperatorHomeScreen())),
                            icon: const Icon(Icons.storefront_outlined, size: 18),
                            label: const Text('구장 관리'),
                          ),
                        ),
                      if (me.isOperator && me.isModerator) const SizedBox(width: FmSpace.s),
                      if (me.isModerator)
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 42)),
                            onPressed: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const AdminHomeScreen())),
                            icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                            label: const Text('운영 관리'),
                          ),
                        ),
                    ]),
                  ),
                const SizedBox(height: FmSpace.l),
                DefaultTabController(
                  length: 3,
                  initialIndex: _tab,
                  child: TabBar(
                    key: const Key('profile_tabs'),
                    onTap: (i) => setState(() => _tab = i),
                    tabs: const [
                      Tab(icon: Icon(Icons.grid_on_rounded, semanticLabel: '게시물')),
                      Tab(icon: Icon(Icons.smart_display_outlined, semanticLabel: '하이라이트')),
                      Tab(icon: Icon(Icons.bookmark_border_rounded, semanticLabel: '저장됨')),
                    ],
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

/// 다가오는 경기 (확정된 예약 중 가장 가까운 것)
class _UpcomingMatch extends StatelessWidget {
  const _UpcomingMatch({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return FutureBuilder<List<ReservationListItem>>(
      future: s.reservations.list(status: 'CONFIRMED'),
      builder: (context, snap) {
        final now = DateTime.now();
        final next = (snap.data ?? const <ReservationListItem>[]).where((r) => r.endsAt.isAfter(now)).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        if (next.isEmpty) return const SizedBox.shrink();
        final r = next.first;
        final days = DateTime(r.startsAt.year, r.startsAt.month, r.startsAt.day)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        final dday = days <= 0 ? '오늘' : 'D-$days';
        return Padding(
          padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.m, FmSpace.page, 0),
          child: Material(
            color: FmColors.ink,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ReservationDetailScreen(publicId: r.publicId))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 50,
                      decoration: BoxDecoration(color: FmColors.brandDark, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(Fmt.weekday(r.startsAt),
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          Text('${r.startsAt.day}',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.1)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('다가오는 경기 · $dday',
                              style: const TextStyle(color: Color(0xFFB9C2CC), fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('${r.venueName} ${r.courtName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                          Text(Fmt.range(r.startsAt, r.endsAt),
                              style: const TextStyle(color: Color(0xFFDCE2E8), fontSize: 13)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFFB9C2CC)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
