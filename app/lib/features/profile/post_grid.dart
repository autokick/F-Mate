import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../social/post_detail_screen.dart';

/// 프로필 게시물·하이라이트 3열 그리드 (더 보기 버튼으로 다음 페이지)
class PostGrid extends StatefulWidget {
  const PostGrid({super.key, required this.userId, required this.highlights, this.saved = false});

  final int userId;
  final bool highlights;
  final bool saved;

  @override
  State<PostGrid> createState() => _PostGridState();
}

class _PostGridState extends State<PostGrid> {
  final List<Post> _posts = [];
  int? _next;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load({bool more = false}) async {
    final s = AppScope.read(context).social;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final page = widget.saved
          ? await s.saved(more ? _next : null)
          : await s.userPosts(widget.userId, highlights: widget.highlights, cursor: more ? _next : null);
      if (!mounted) return;
      setState(() {
        if (!more) _posts.clear();
        _posts.addAll(page.items);
        _next = page.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _posts.isEmpty) return const Padding(padding: EdgeInsets.all(FmSpace.xl), child: LoadingState());
    if (_error && _posts.isEmpty) {
      return ErrorState(title: '불러오지 못했어요', onRetry: () => _load());
    }
    if (_posts.isEmpty) {
      return EmptyState(
        icon: widget.highlights ? Icons.movie_outlined : Icons.grid_on_rounded,
        title: widget.saved ? '저장한 게시물이 없어요' : (widget.highlights ? '하이라이트가 없어요' : '게시물이 없어요'),
      );
    }
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
          itemCount: _posts.length,
          itemBuilder: (context, i) => _Cell(post: _posts[i]),
        ),
        if (_next != null)
          TextButton(onPressed: _loading ? null : () => _load(more: true), child: const Text('더 보기')),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final p = post;
    final image = p.images.isNotEmpty ? p.images.first.url : p.video?.thumbnailUrl;
    return Semantics(
      button: true,
      label: '게시물 ${p.caption ?? ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: p.id, initial: p))),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              Image.network(image, fit: BoxFit.cover, errorBuilder: (context, e, s) => Container(color: FmColors.surfaceMuted))
            else
              Container(
                color: FmColors.brandSoft,
                padding: const EdgeInsets.all(FmSpace.s),
                child: Text(p.caption ?? '', maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ),
            if (p.video != null)
              const Positioned(top: 4, right: 4, child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 20)),
            if (p.images.length > 1)
              const Positioned(top: 4, right: 4, child: Icon(Icons.collections_rounded, color: Colors.white, size: 18)),
          ],
        ),
      ),
    );
  }
}
