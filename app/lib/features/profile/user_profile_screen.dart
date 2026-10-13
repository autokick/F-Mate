import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/report_sheet.dart';
import '../../shared/widgets.dart';
import '../chat/chat_room_screen.dart';
import 'follow_list_screen.dart';
import 'post_grid.dart';

/// 다른 사용자 프로필 (팔로우·메시지·차단·신고)
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final int userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _key = GlobalKey<AsyncBodyState<ProfileView>>();
  int _tab = 0;

  Future<void> _follow(ProfileView p) async {
    if (!requireLogin(context)) return;
    final s = AppScope.read(context).social;
    try {
      if (p.followStatus == 'NONE') {
        final status = await s.follow(p.id);
        if (mounted && status == 'PENDING') showFmSnack(context, '팔로우를 요청했어요');
      } else {
        await s.unfollow(p.id);
      }
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _message(ProfileView p) async {
    if (!requireLogin(context)) return;
    try {
      final chat = await AppScope.read(context).chats.open(p.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatRoomScreen(chatId: chat.id, initial: chat)));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _more(ProfileView p) async {
    if (!requireLogin(context)) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(p.blockedByMe ? Icons.lock_open_rounded : Icons.block_rounded, color: FmColors.danger),
            title: Text(p.blockedByMe ? '차단 해제' : '차단', style: const TextStyle(color: FmColors.danger)),
            onTap: () => Navigator.of(ctx).pop('block'),
          ),
          ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('신고'), onTap: () => Navigator.of(ctx).pop('report')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    final s = AppScope.read(context).social;
    if (action == 'report') {
      await showReportSheet(context, 'USER', p.id);
    } else if (action == 'block') {
      if (!p.blockedByMe &&
          !await confirmDialog(context,
              title: '${p.nickname}님을 차단할까요?',
              message: '서로의 게시물·프로필을 볼 수 없고 팔로우와 채팅이 끊겨요.',
              confirm: '차단',
              destructive: true)) {
        return;
      }
      try {
        if (p.blockedByMe) {
          await s.unblock(p.id);
        } else {
          await s.block(p.id);
        }
        await _key.currentState?.reload();
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final isMe = services.session.me?.id == widget.userId;
    return Scaffold(
      appBar: AppBar(title: const Text('프로필')),
      body: !services.session.isLoggedIn
          ? EmptyState(
              icon: Icons.person_outline_rounded,
              title: '로그인하면 프로필을 볼 수 있어요',
              actionLabel: '로그인',
              onAction: () => requireLogin(context))
          : AsyncBody<ProfileView>(
              key: _key,
              load: () => services.social.profile(widget.userId),
              builder: (context, p, reload) => RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  children: [
                    ProfileHeader(
                      name: p.nickname,
                      avatarUrl: p.avatarUrl,
                      bio: p.bio,
                      position: p.preferredPosition,
                      counts: p.counts,
                      onFollowers: p.canViewPosts
                          ? () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => FollowListScreen(userId: p.id, followers: true)))
                          : null,
                      onFollowing: p.canViewPosts
                          ? () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => FollowListScreen(userId: p.id, followers: false)))
                          : null,
                    ),
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
                        child: Row(children: [
                          Expanded(
                            child: p.followStatus == 'NONE'
                                ? FilledButton(
                                    onPressed: p.blockedByMe ? null : () => _follow(p),
                                    child: Text(p.followsMe ? '맞팔로우' : '팔로우'))
                                : OutlinedButton(
                                    onPressed: () => _follow(p),
                                    child: Text(p.followStatus == 'PENDING' ? '요청됨' : '팔로잉')),
                          ),
                          const SizedBox(width: FmSpace.s),
                          Expanded(
                            child: OutlinedButton(onPressed: p.blockedByMe ? null : () => _message(p), child: const Text('메시지')),
                          ),
                          IconButton(tooltip: '더보기', icon: const Icon(Icons.more_horiz_rounded), onPressed: () => _more(p)),
                        ]),
                      ),
                    const SizedBox(height: FmSpace.m),
                    if (p.blockedByMe)
                      const EmptyState(icon: Icons.block_rounded, title: '차단한 사용자예요')
                    else if (!p.canViewPosts)
                      const EmptyState(icon: Icons.lock_outline_rounded, title: '비공개 계정이에요', message: '팔로우 요청이 수락되면 게시물을 볼 수 있어요.')
                    else ...[
                      DefaultTabController(
                        length: 2,
                        initialIndex: _tab,
                        child: TabBar(
                          onTap: (i) => setState(() => _tab = i),
                          tabs: const [Tab(text: '게시물'), Tab(text: '하이라이트')],
                        ),
                      ),
                      PostGrid(key: ValueKey('u${p.id}-$_tab'), userId: p.id, highlights: _tab == 1),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

/// 프로필 상단 (사진·닉네임·포지션·소개·카운트)
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    this.avatarUrl,
    this.bio,
    this.position,
    required this.counts,
    this.onFollowers,
    this.onFollowing,
  });

  final String name;
  final String? avatarUrl;
  final String? bio;
  final String? position;
  final Counts counts;
  final VoidCallback? onFollowers;
  final VoidCallback? onFollowing;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int n, VoidCallback? onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FmSpace.s),
              child: Column(children: [
                Text('$n', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(label, style: const TextStyle(fontSize: 13, color: FmColors.textSecondary)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(FmSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            AppAvatar(url: avatarUrl, name: name, size: 76),
            const SizedBox(width: FmSpace.l),
            stat('게시물', counts.posts, null),
            stat('팔로워', counts.followers, onFollowers),
            stat('팔로잉', counts.following, onFollowing),
          ]),
          const SizedBox(height: FmSpace.m),
          Row(children: [
            Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (position != null) ...[
              const SizedBox(width: FmSpace.s),
              StatusChip(label: kPositions[position] ?? position!),
            ],
          ]),
          if (bio != null && bio!.isNotEmpty) ...[
            const SizedBox(height: FmSpace.xs),
            Text(bio!, style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
        ],
      ),
    );
  }
}
