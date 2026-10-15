import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/report_sheet.dart';
import '../../shared/widgets.dart';
import '../profile/user_profile_screen.dart';
import '../social/hashtag_screen.dart';
import '../social/post_detail_screen.dart';
import '../venues/venue_detail_screen.dart';
import '../venues/venue_slots.dart';

/// 숏폼만 따로 보는 화면 (게시물의 영상을 눌렀을 때 / 구장의 영상 목록에서).
class ShortsScreen extends StatelessWidget {
  const ShortsScreen({super.key, this.initialPosts, this.initialIndex = 0});

  /// 특정 게시물만 볼 때. 없으면 전체 숏폼을 불러온다.
  final List<Post>? initialPosts;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: FmColors.videoBackground,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: FullscreenFeed(
          initialPosts: initialPosts,
          initialIndex: initialIndex,
          loader: initialPosts == null ? (cursor) => services.social.shorts(cursor) : null,
          empty: const FeedMessage(icon: Icons.smart_display_outlined, title: '아직 올라온 영상이 없어요'),
        ),
      ),
    );
  }
}

/// 세로로 넘기는 전체 화면 피드. 영상은 자동 재생, 사진은 옆으로 넘겨 본다.
class FullscreenFeed extends StatefulWidget {
  const FullscreenFeed({
    super.key,
    this.initialPosts,
    this.initialIndex = 0,
    this.loader,
    this.active = true,
    this.empty,
    this.topInset = 0,
  });

  final List<Post>? initialPosts;
  final int initialIndex;
  final Future<CursorPage<Post>> Function(int? cursor)? loader;

  /// 이 피드가 화면에 보이는 중인지 (탭 전환 시 영상 멈춤)
  final bool active;
  final Widget? empty;

  /// 위쪽에 겹쳐 그리는 탭 등의 높이 (작성자 정보가 가려지지 않게)
  final double topInset;

  @override
  State<FullscreenFeed> createState() => FullscreenFeedState();
}

class FullscreenFeedState extends State<FullscreenFeed> {
  final List<Post> _posts = [];
  int? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _error = false;
  late int _current = widget.initialIndex;
  late final PageController _pages = PageController(initialPage: widget.initialIndex);

  @override
  void initState() {
    super.initState();
    if (widget.initialPosts != null) {
      _posts.addAll(widget.initialPosts!);
      _hasMore = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// 처리 중인 영상은 건너뛴다 (재생할 수 없으므로)
  static bool _showable(Post p) => p.video == null || p.video!.ready;

  Future<void> _loadMore() async {
    final loader = widget.loader;
    if (loader == null || _loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      // 걸러진 항목 때문에 화면이 비면 다음 페이지를 이어서 가져온다 (최대 5번)
      for (var tries = 0; tries < 5; tries++) {
        final page = await loader(_cursor);
        if (!mounted) return;
        setState(() {
          final seen = _posts.map((p) => p.id).toSet();
          _posts.addAll(page.items.where((p) => _showable(p) && !seen.contains(p.id)));
          _cursor = page.nextCursor;
          _hasMore = page.nextCursor != null;
          _error = false;
        });
        if (_posts.isNotEmpty || !_hasMore) break;
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> refresh() async {
    setState(() {
      _posts.clear();
      _cursor = null;
      _hasMore = true;
      _current = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    if (_posts.isEmpty) {
      if (_loading || (_hasMore && !_error && widget.loader != null)) {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      }
      if (_error) {
        return FeedMessage(
          icon: Icons.wifi_off_rounded,
          title: '피드를 불러오지 못했어요',
          action: TextButton(onPressed: _loadMore, child: const Text('다시 시도', style: TextStyle(color: Colors.white))),
        );
      }
      return widget.empty ?? const FeedMessage(icon: Icons.smart_display_outlined, title: '아직 올라온 게시물이 없어요');
    }
    return RefreshIndicator(
      onRefresh: widget.loader == null ? () async {} : refresh,
      color: FmColors.ink,
      edgeOffset: widget.topInset,
      child: PageView.builder(
        controller: _pages,
        scrollDirection: Axis.vertical,
        itemCount: _posts.length,
        onPageChanged: (i) {
          setState(() => _current = i);
          if (i >= _posts.length - 3) _loadMore();
        },
        itemBuilder: (context, i) => FeedItemPage(
          key: ValueKey(_posts[i].id),
          post: _posts[i],
          active: widget.active && i == _current,
          topInset: widget.topInset,
          onRemoved: () => setState(() => _posts.removeAt(i)),
        ),
      ),
    );
  }
}

/// 어두운 화면용 안내 문구
class FeedMessage extends StatelessWidget {
  const FeedMessage({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FmSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 56),
            const SizedBox(height: FmSpace.l),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            if (message != null) ...[
              const SizedBox(height: FmSpace.s),
              Text(message!,
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
            ],
            if (action != null) ...[const SizedBox(height: FmSpace.l), action!],
          ],
        ),
      ),
    );
  }
}

/// 전체 화면 게시물 한 장 (영상 / 사진 / 글)
class FeedItemPage extends StatefulWidget {
  const FeedItemPage({super.key, required this.post, required this.active, this.topInset = 0, this.onRemoved});

  final Post post;
  final bool active;
  final double topInset;
  final VoidCallback? onRemoved;

  @override
  State<FeedItemPage> createState() => _FeedItemPageState();
}

class _FeedItemPageState extends State<FeedItemPage> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _userPaused = false;
  bool _followed = false;
  int _photo = 0;

  /// 이 화면이 다른 화면에 가려졌는지 (가려지면 false)
  bool _tickerOn = true;

  Post get p => widget.post;

  bool get _visible => widget.active && _tickerOn;

  @override
  void initState() {
    super.initState();
    final url = p.video?.hlsUrl;
    if (p.video == null) return;
    if (url == null) {
      _failed = true;
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setLooping(true);
      if (_visible && !_userPaused) c.play();
      setState(() {});
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerOn = TickerMode.valuesOf(context).enabled;
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant FeedItemPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _scheduleSync();
  }

  /// 빌드가 끝난 뒤에 재생 상태를 맞춘다 (빌드 중 재생 상태를 바꾸지 않기 위해)
  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPlayback();
    });
  }

  /// 화면에 보일 때만 재생 (다른 탭·다른 화면으로 가면 멈춤)
  void _syncPlayback() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_visible && !_userPaused) {
      if (!c.value.isPlaying) c.play();
    } else if (c.value.isPlaying) {
      c.pause();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _userPaused = true;
      } else {
        c.play();
        _userPaused = false;
      }
    });
  }

  Future<void> _like() async {
    if (!requireLogin(context)) return;
    final before = p.likedByMe;
    setState(() {
      p.likedByMe = !before;
      p.likeCount += before ? -1 : 1;
    });
    try {
      await AppScope.read(context).social.like(p.id, !before);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        p.likedByMe = before;
        p.likeCount += before ? 1 : -1;
      });
      showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!requireLogin(context)) return;
    final before = p.savedByMe;
    setState(() => p.savedByMe = !before);
    try {
      await AppScope.read(context).social.save(p.id, !before);
      if (mounted) showFmSnack(context, before ? '저장을 취소했어요' : '저장했어요');
    } catch (e) {
      if (!mounted) return;
      setState(() => p.savedByMe = before);
      showError(context, e);
    }
  }

  Future<void> _follow() async {
    if (!requireLogin(context)) return;
    setState(() => _followed = true);
    try {
      final status = await AppScope.read(context).social.follow(p.author.id);
      if (mounted) showFmSnack(context, status == 'PENDING' ? '팔로우를 요청했어요' : '${p.author.nickname}님을 팔로우해요');
    } catch (e) {
      if (!mounted) return;
      setState(() => _followed = false);
      showError(context, e);
    }
  }

  Future<void> _more() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('링크 복사'),
            onTap: () => Navigator.of(ctx).pop('copy'),
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: FmColors.danger),
            title: const Text('신고', style: TextStyle(color: FmColors.danger)),
            onTap: () => Navigator.of(ctx).pop('report'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: 'https://fmate.app/p/${p.id}'));
      if (mounted) showFmSnack(context, '링크를 복사했어요');
    } else if (action == 'report' && requireLogin(context)) {
      await showReportSheet(context, 'POST', p.id);
    }
  }

  void _openProfile() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: p.author.id)));

  void _openComments() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: p.id, initial: p)));

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).session.me;
    final isMine = me?.id == p.author.id;
    const bottomPad = FmSpace.l;
    return Stack(
      fit: StackFit.expand,
      children: [
        _media(),
        // 글자가 잘 보이도록 위·아래만 살짝 어둡게
        const IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 140,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x8C0B0D10), Color(0x000B0D10)],
                  ),
                ),
              ),
            ),
          ),
        ),
        const IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 380,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xDB0B0D10), Color(0x000B0D10)],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_controller != null && _controller!.value.isInitialized && !_controller!.value.isPlaying)
          const IgnorePointer(child: Center(child: Icon(Icons.play_arrow_rounded, size: 80, color: Colors.white70))),
        // 사진 여러 장이면 점 표시
        if (p.images.length > 1)
          Positioned(
            top: MediaQuery.paddingOf(context).top + widget.topInset + FmSpace.s,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < p.images.length; i++)
                    Container(
                      width: i == _photo ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i == _photo ? Colors.white : Colors.white54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // 오른쪽 버튼
        Positioned(
          right: 6,
          bottom: bottomPad + 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AuthorAvatar(
                post: p,
                showFollow: !isMine && !_followed,
                onTap: _openProfile,
                onFollow: _follow,
              ),
              const SizedBox(height: FmSpace.l),
              _RailButton(
                icon: p.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: p.likedByMe ? const Color(0xFFFF4D6A) : Colors.white,
                label: Fmt.count(p.likeCount),
                semantics: p.likedByMe ? '좋아요 취소' : '좋아요',
                onTap: _like,
              ),
              _RailButton(
                icon: Icons.mode_comment_rounded,
                label: Fmt.count(p.commentCount),
                semantics: '댓글',
                onTap: _openComments,
              ),
              _RailButton(
                icon: p.savedByMe ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                label: '저장',
                semantics: p.savedByMe ? '저장 취소' : '저장',
                onTap: _save,
              ),
              _RailButton(icon: Icons.more_horiz_rounded, label: '더보기', semantics: '더보기', onTap: _more),
            ],
          ),
        ),
        // 작성자 · 캡션 · 구장
        Positioned(
          left: FmSpace.l,
          right: 76,
          bottom: bottomPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _openProfile,
                child: Text(p.author.nickname,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              if (p.caption != null && p.caption!.isNotEmpty && p.kind != 'TEXT') ...[
                const SizedBox(height: 6),
                _Caption(text: p.caption!),
              ],
              const SizedBox(height: 4),
              Text(Fmt.ago(p.createdAt), style: const TextStyle(color: Colors.white60, fontSize: 12)),
              if (p.venueId != null) ...[
                const SizedBox(height: FmSpace.m),
                VenueChip(venueId: p.venueId!, venueName: p.venueName ?? '구장'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _media() {
    final c = _controller;
    if (p.video != null) {
      return GestureDetector(
        onTap: _togglePlay,
        child: Container(
          color: FmColors.videoBackground,
          alignment: Alignment.center,
          child: _failed
              ? const Text('영상을 재생할 수 없어요', style: TextStyle(color: Colors.white70))
              : (c != null && c.value.isInitialized)
                  ? _fit(c.value.size.width, c.value.size.height, VideoPlayer(c))
                  : (p.video?.thumbnailUrl != null
                      ? Image.network(p.video!.thumbnailUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, e, s) => const SizedBox.shrink())
                      : const CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }
    if (p.images.isNotEmpty) {
      return PageView.builder(
        itemCount: p.images.length,
        onPageChanged: (i) => setState(() => _photo = i),
        itemBuilder: (context, i) {
          final img = p.images[i];
          final portrait = (img.height ?? 0) >= (img.width ?? 1);
          return Container(
            color: FmColors.videoBackground,
            child: img.url == null
                ? const SizedBox.shrink()
                : Image.network(
                    img.url!,
                    fit: portrait ? BoxFit.cover : BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    semanticLabel: '${p.author.nickname}님의 사진 ${i + 1}',
                    errorBuilder: (context, e, s) => const SizedBox.shrink(),
                  ),
          );
        },
      );
    }
    // 글만 있는 게시물
    return Container(
      color: const Color(0xFF17221D),
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(FmSpace.xl, 120, 88, 200),
      child: Text(
        p.caption ?? '',
        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, height: 1.5),
      ),
    );
  }

  /// 세로 영상은 화면을 꽉 채우고, 가로 영상은 잘리지 않게 가운데 놓는다
  Widget _fit(double w, double h, Widget child) {
    if (w <= 0 || h <= 0) return child;
    final portrait = h >= w;
    return SizedBox.expand(
      child: FittedBox(
        fit: portrait ? BoxFit.cover : BoxFit.contain,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: w, height: h, child: child),
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.post, required this.showFollow, required this.onTap, required this.onFollow});

  final Post post;
  final bool showFollow;
  final VoidCallback onTap;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 60,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: AppAvatar(url: post.author.avatarUrl, name: post.author.nickname, size: 46),
            ),
          ),
          if (showFollow)
            Positioned(
              bottom: 0,
              child: Semantics(
                button: true,
                label: '${post.author.nickname} 팔로우',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: onFollow,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: FmColors.brandDark, shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.semantics, required this.onTap, this.color = Colors.white});

  final IconData icon;
  final String label;
  final String semantics;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$semantics $label',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color, shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)]),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(color: Color(0x66000000), blurRadius: 4)])),
            ],
          ),
        ),
      ),
    );
  }
}

/// 캡션 (두 줄까지, 누르면 펼침). #해시태그는 색을 다르게 하고 누르면 모아 보기.
class _Caption extends StatefulWidget {
  const _Caption({required this.text});

  final String text;

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption> {
  bool _open = false;
  static final _tag = RegExp(r'#[^\s#]+');

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _tag.allMatches(widget.text)) {
      if (m.start > last) spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      final tag = m.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => HashtagScreen(tag: tag.substring(1)))),
          child: Text(tag, style: const TextStyle(color: Color(0xFF9BE8C4), fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ));
      last = m.end;
    }
    if (last < widget.text.length) spans.add(TextSpan(text: widget.text.substring(last)));
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: Text.rich(
        TextSpan(children: spans),
        maxLines: _open ? 8 : 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFFF2F4F5), fontSize: 15, height: 1.45),
      ),
    );
  }
}

/// 게시물에 태그된 구장 카드: 오늘 남은 시간 + 예약 버튼 → 구장 상세
class VenueChip extends StatelessWidget {
  const VenueChip({super.key, required this.venueId, required this.venueName});

  final int venueId;
  final String venueName;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    void open() =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => VenueDetailScreen(venueId: venueId)));
    return Semantics(
      button: true,
      label: '$venueName 예약하기',
      child: Material(
        color: const Color(0x24FFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x2EFFFFFF)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 20, color: Color(0xFF9BE8C4)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(venueName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      FutureBuilder<List<DateTime>>(
                        future: VenueSlots.of(services, venueId, DateTime.now()),
                        builder: (context, snap) {
                          final times = snap.data;
                          final text = times == null
                              ? '예약 가능 시간 확인 중'
                              : times.isEmpty
                                  ? '다른 날짜 예약 가능'
                                  : '오늘 ${times.take(2).map(Fmt.time).join(' · ')} 예약 가능';
                          return Text(text, style: const TextStyle(color: Color(0xC7FFFFFF), fontSize: 12));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: FmColors.brandDark, borderRadius: BorderRadius.circular(12)),
                  child: const Text('예약', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
