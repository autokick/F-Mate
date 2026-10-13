import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import 'post_card.dart';

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
          : PagedList<Post>(
              fetch: (cursor) async {
                final p = await services.social.hashtag(tag, cursor);
                return (p.items, p.nextCursor);
              },
              itemBuilder: (context, post, i) => PostCard(post: post),
              empty: EmptyState(icon: Icons.tag_rounded, title: '#$tag 게시물이 아직 없어요'),
            ),
    );
  }
}
