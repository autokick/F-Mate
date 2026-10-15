import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/services.dart';
import '../../shared/widgets.dart';
import '../profile/post_grid.dart';

/// #해시태그 게시물 모아 보기 (3열 그리드)
class HashtagScreen extends StatelessWidget {
  const HashtagScreen({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('#$tag')),
      body: !services.session.isLoggedIn
          ? EmptyState(
              icon: Icons.tag_rounded,
              title: '로그인하면 해시태그 게시물을 볼 수 있어요',
              actionLabel: '로그인',
              onAction: () => requireLogin(context))
          : ListView(
              children: [
                PostGrid(
                  loader: (s, cursor) => s.social.hashtag(tag, cursor),
                  emptyTitle: '#$tag 게시물이 아직 없어요',
                ),
              ],
            ),
    );
  }
}
