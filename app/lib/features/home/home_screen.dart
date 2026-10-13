import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import '../auth/verify_email_screen.dart';
import '../notifications/notifications_screen.dart';
import '../shorts/shorts_screen.dart';
import '../social/compose_screen.dart';
import '../social/post_card.dart';

enum FeedType { following, latest, recommended }

extension FeedTypeX on FeedType {
  String get label => switch (this) {
        FeedType.following => '팔로잉',
        FeedType.latest => '최신',
        FeedType.recommended => '추천',
      };

  String get api => switch (this) {
        FeedType.following => 'following',
        FeedType.latest => 'latest',
        FeedType.recommended => 'recommended',
      };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FeedType _feed = FeedType.latest;
  int _reloadToken = 0;

  Future<void> _compose() async {
    if (!await requireVerified(context)) return;
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ComposeScreen()));
    if (created == true) setState(() => _reloadToken++);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(listenable: services.session, builder: (context, _) => _build(context, services));
  }

  Widget _build(BuildContext context, AppServices services) {
    final session = services.session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('F-Mate'),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: services.unreadNotifications,
            builder: (context, count, _) => IconButton(
              tooltip: count > 0 ? '알림 $count개' : '알림',
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text(count > 99 ? '99+' : '$count'),
                child: const Icon(Icons.notifications_none_rounded),
              ),
              onPressed: () {
                if (!requireLogin(context)) return;
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
              },
            ),
          ),
          IconButton(tooltip: '게시물 작성', icon: const Icon(Icons.add_box_outlined), onPressed: _compose),
        ],
      ),
      body: !session.isLoggedIn
          ? ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, 0),
                  child: _ShortsEntryCard(),
                ),
                EmptyState(
                  icon: Icons.group_outlined,
                  title: '로그인하고 풋살 피드를 보세요',
                  message: '팀원들의 경기 사진과 하이라이트가 여기에 모여요.',
                  actionLabel: '로그인',
                  onAction: () => requireLogin(context),
                ),
              ],
            )
          : PagedList<Post>(
              key: ValueKey('${_feed.api}-$_reloadToken'),
              fetch: (cursor) async {
                final page = await services.social.feed(_feed.api, cursor);
                return (page.items, page.nextCursor);
              },
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (session.me?.emailVerified == false) const _VerifyBanner(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, 0),
                    child: _ShortsEntryCard(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.l, FmSpace.l, FmSpace.s),
                    child: SegmentedButton<FeedType>(
                      key: const Key('feed_selector'),
                      segments: [for (final f in FeedType.values) ButtonSegment(value: f, label: Text(f.label))],
                      selected: {_feed},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _feed = s.first),
                    ),
                  ),
                ],
              ),
              itemBuilder: (context, post, i) => PostCard(key: ValueKey(post.id), post: post),
              empty: _feed == FeedType.following
                  ? const EmptyState(
                      icon: Icons.person_add_alt_outlined,
                      title: '팔로우한 사람의 게시물이 없어요',
                      message: '최신·추천 피드에서 함께 뛸 사람을 찾아 팔로우해 보세요.',
                    )
                  : EmptyState(
                      icon: Icons.photo_library_outlined,
                      title: '아직 게시물이 없어요',
                      message: '첫 게시물을 올려 보세요.',
                      actionLabel: '게시물 작성',
                      onAction: _compose,
                    ),
            ),
    );
  }
}

class _VerifyBanner extends StatelessWidget {
  const _VerifyBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, 0),
      child: FmCard(
        color: const Color(0xFFFEF3C7),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerifyEmailScreen())),
        child: const Row(
          children: [
            Icon(Icons.mark_email_unread_outlined, color: Color(0xFF92400E)),
            SizedBox(width: FmSpace.m),
            Expanded(
              child: Text('이메일 인증을 마치면 구장 예약과 게시물 작성을 할 수 있어요',
                  style: TextStyle(fontSize: 14, color: Color(0xFF92400E))),
            ),
            Icon(Icons.chevron_right_rounded, color: Color(0xFF92400E)),
          ],
        ),
      ),
    );
  }
}

class _ShortsEntryCard extends StatelessWidget {
  const _ShortsEntryCard();

  @override
  Widget build(BuildContext context) {
    return FmCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShortsScreen())),
      color: FmColors.brandSoft,
      child: const Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: FmColors.brand,
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
          ),
          SizedBox(width: FmSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('하이라이트 숏폼',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: FmColors.textPrimary)),
                SizedBox(height: 2),
                Text('골 장면, 개인기를 세로 영상으로 확인하세요', style: TextStyle(fontSize: 13, color: FmColors.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: FmColors.textSecondary),
        ],
      ),
    );
  }
}
