import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/services.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import 'user_profile_screen.dart';

/// 팔로워 / 팔로잉 목록
class FollowListScreen extends StatelessWidget {
  const FollowListScreen({super.key, required this.userId, required this.followers});

  final int userId;
  final bool followers;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).social;
    return Scaffold(
      appBar: AppBar(title: Text(followers ? '팔로워' : '팔로잉')),
      body: PagedList<UserSummary>(
        fetch: (cursor) async {
          final page = cursor ?? 0;
          final list = followers ? await s.followers(userId, page: page) : await s.following(userId, page: page);
          return (list, list.length >= 30 ? page + 1 : null);
        },
        itemBuilder: (context, u, i) => UserTile(user: u),
        empty: EmptyState(icon: Icons.people_outline_rounded, title: followers ? '팔로워가 없어요' : '팔로우한 사람이 없어요'),
      ),
    );
  }
}

class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.user, this.trailing});

  final UserSummary user;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AppAvatar(url: user.avatarUrl, name: user.nickname),
      title: Text(user.nickname, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: trailing,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: user.id))),
    );
  }
}
