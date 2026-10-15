import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../shorts/shorts_screen.dart';
import '../social/post_detail_screen.dart';

/// 게시물 3열 그리드 (더 보기 버튼으로 다음 페이지).
/// 칸을 누르면 그 게시물부터 전체 화면으로 넘겨 본다.
class PostGrid extends StatefulWidget {
  const PostGrid({
    super.key,
    this.userId,
    this.highlights = false,
    this.saved = false,
    this.loader,
    this.emptyTitle,
  });

  /// 프로필 게시물 (userId) / 저장됨 (saved) / 직접 지정 (loader)
  final int? userId;
  final bool highlights;
  final bool saved;
  final Future<CursorPage<Post>> Function(AppServices s, int? cursor)? loader;
  final String? emptyTitle;

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

  Future<CursorPage<Post>> _fetch(AppServices s, int? cursor) {
    if (widget.loader != null) return widget.loader!(s, cursor);
    if (widget.saved) return s.social.saved(cursor);
    return s.social.userPosts(widget.userId ?? 0, highlights: widget.highlights, cursor: cursor);
  }

  Future<void> _load({bool more = false}) async {
    final s = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final page = await _fetch(s, more ? _next : null);
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

  void _open(int index) {
    final p = _posts[index];
    // 처리 중인 영상은 상세 화면으로 (아직 재생할 수 없음)
    if (p.video != null && !p.video!.ready) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: p.id, initial: p)));
      return;
    }
    final playable = _posts.where((x) => x.video == null || x.video!.ready).toList();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShortsScreen(initialPosts: playable, initialIndex: playable.indexOf(p).clamp(0, playable.length - 1)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _posts.isEmpty) return const Padding(padding: EdgeInsets.all(FmSpace.xl), child: LoadingState());
    if (_error && _posts.isEmpty) {
      return ErrorState(title: '불러오지 못했어요', onRetry: () => _load());
    }
    if (_posts.isEmpty) {
      return EmptyState(
        icon: widget.saved
            ? Icons.bookmark_border_rounded
            : (widget.highlights ? Icons.smart_display_outlined : Icons.photo_library_outlined),
        title: widget.emptyTitle ??
            (widget.saved ? '저장한 게시물이 없어요' : (widget.highlights ? '하이라이트가 없어요' : '게시물이 없어요')),
      );
    }
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 3 / 4,
          ),
          itemCount: _posts.length,
          itemBuilder: (context, i) => PostThumb(post: _posts[i], onTap: () => _open(i)),
        ),
        if (_next != null)
          TextButton(onPressed: _loading ? null : () => _load(more: true), child: const Text('더 보기')),
      ],
    );
  }
}

/// 게시물 썸네일 칸 (영상은 ▶ + 조회 대신 좋아요 수)
class PostThumb extends StatelessWidget {
  const PostThumb({super.key, required this.post, required this.onTap, this.radius = 0});

  final Post post;
  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = post;
    final image = p.images.isNotEmpty ? p.images.first.url : p.video?.thumbnailUrl;
    return Semantics(
      button: true,
      label: '${p.video != null ? '영상' : '게시물'} ${p.caption ?? ''}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Material(
          color: p.video != null ? const Color(0xFF17221D) : FmColors.photoPlaceholder,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image != null)
                  Image.network(image, fit: BoxFit.cover, errorBuilder: (context, e, s) => const SizedBox.shrink())
                else if (p.video == null)
                  Container(
                    color: FmColors.brandSoft,
                    padding: const EdgeInsets.all(FmSpace.s),
                    child: Text(p.caption ?? '',
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.4, color: FmColors.brandOnSoft)),
                  ),
                if (p.video != null)
                  Positioned(
                    left: 6,
                    bottom: 5,
                    child: Row(children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16,
                          shadows: [Shadow(color: Color(0x80000000), blurRadius: 4)]),
                      Text(Fmt.count(p.likeCount),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              shadows: [Shadow(color: Color(0x80000000), blurRadius: 4)])),
                    ]),
                  ),
                if (p.video != null && !p.video!.ready)
                  const Center(
                    child: SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2)),
                  ),
                if (p.images.length > 1)
                  const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.collections_rounded,
                          color: Colors.white, size: 18, shadows: [Shadow(color: Color(0x80000000), blurRadius: 4)])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
