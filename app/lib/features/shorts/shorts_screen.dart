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
import '../social/post_detail_screen.dart';
import 'shorts_upload_screen.dart';

/// 세로형 숏폼 피드. 위아래로 넘기면 다음 영상이 재생된다 (HLS 스트리밍).
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key, this.initialPosts});

  /// 특정 게시물만 볼 때 (피드 카드에서 영상 탭)
  final List<Post>? initialPosts;

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  final List<Post> _posts = [];
  int? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _current = 0;

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

  Future<void> _loadMore() async {
    final services = AppScope.read(context);
    if (_loading || !_hasMore || !services.session.isLoggedIn) return;
    setState(() => _loading = true);
    try {
      final page = await services.social.shorts(_cursor);
      if (!mounted) return;
      setState(() {
        _posts.addAll(page.items.where((p) => p.video?.ready == true));
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    if (!await requireVerified(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShortsUploadScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AppScope.of(context).session.isLoggedIn;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: const Text('숏폼', style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(tooltip: '영상 올리기', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: _upload),
          ],
        ),
        body: !loggedIn && widget.initialPosts == null
            ? _Message(
                icon: Icons.lock_outline_rounded,
                title: '로그인하고 하이라이트 영상을 보세요',
                action: TextButton(onPressed: () => requireLogin(context), child: const Text('로그인')))
            : _posts.isEmpty
                ? (_loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _Message(
                        icon: _error == null ? Icons.smart_display_outlined : Icons.wifi_off_rounded,
                        title: _error == null ? '아직 올라온 영상이 없어요' : '영상을 불러오지 못했어요',
                        action: TextButton(
                            onPressed: _error == null ? _upload : _loadMore,
                            child: Text(_error == null ? '첫 영상 올리기' : '다시 시도')),
                      ))
                : PageView.builder(
                    scrollDirection: Axis.vertical,
                    itemCount: _posts.length,
                    onPageChanged: (i) {
                      setState(() => _current = i);
                      if (i >= _posts.length - 3) _loadMore();
                    },
                    itemBuilder: (context, i) => _ShortPage(
                      key: ValueKey(_posts[i].id),
                      post: _posts[i],
                      active: i == _current,
                    ),
                  ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.action});

  final IconData icon;
  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 56),
          const SizedBox(height: FmSpace.l),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: FmSpace.s),
          action,
        ],
      ),
    );
  }
}

class _ShortPage extends StatefulWidget {
  const _ShortPage({super.key, required this.post, required this.active});

  final Post post;
  final bool active;

  @override
  State<_ShortPage> createState() => _ShortPageState();
}

class _ShortPageState extends State<_ShortPage> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _userPaused = false;

  @override
  void initState() {
    super.initState();
    final url = widget.post.video?.hlsUrl;
    if (url == null) {
      _failed = true;
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setLooping(true);
      if (widget.active) c.play();
      setState(() {});
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didUpdateWidget(covariant _ShortPage old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (widget.active && !_userPaused) {
      c.play();
    } else if (!widget.active) {
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
    final p = widget.post;
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final c = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: _failed
                ? const Text('영상을 재생할 수 없어요', style: TextStyle(color: Colors.white70))
                : (c != null && c.value.isInitialized)
                    ? AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))
                    : (p.video?.thumbnailUrl != null
                        ? Image.network(p.video!.thumbnailUrl!, fit: BoxFit.contain)
                        : const CircularProgressIndicator(color: Colors.white)),
          ),
        ),
        if (c != null && c.value.isInitialized && !c.value.isPlaying)
          const IgnorePointer(child: Center(child: Icon(Icons.play_arrow_rounded, size: 72, color: Colors.white70))),
        // 하단 그라데이션 + 작성자·캡션
        Positioned(
          left: 0,
          right: 72,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.xxl, FmSpace.s, FmSpace.xl),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: p.author.id))),
                  child: Row(children: [
                    AppAvatar(url: p.author.avatarUrl, name: p.author.nickname, size: 32),
                    const SizedBox(width: FmSpace.s),
                    Text(p.author.nickname, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),
                if (p.caption != null && p.caption!.isNotEmpty) ...[
                  const SizedBox(height: FmSpace.s),
                  Text(p.caption!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
                ],
              ],
            ),
          ),
        ),
        // 오른쪽 버튼
        Positioned(
          right: FmSpace.s,
          bottom: FmSpace.xl,
          child: Column(
            children: [
              _SideButton(
                icon: p.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: p.likedByMe ? FmColors.danger : Colors.white,
                label: Fmt.count(p.likeCount),
                tooltip: '좋아요',
                onTap: _like,
              ),
              _SideButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: Fmt.count(p.commentCount),
                tooltip: '댓글',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: p.id, initial: p))),
              ),
              _SideButton(
                icon: Icons.share_outlined,
                label: '공유',
                tooltip: '링크 복사',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: 'F-Mate 하이라이트 https://fmate.app/p/${p.id}'));
                  if (context.mounted) showFmSnack(context, '링크를 복사했어요');
                },
              ),
              _SideButton(
                icon: Icons.flag_outlined,
                label: '신고',
                tooltip: '신고',
                onTap: () {
                  if (requireLogin(context)) showReportSheet(context, 'POST', p.id);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.icon, required this.label, required this.tooltip, required this.onTap, this.color = Colors.white});

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FmSpace.m),
      child: Column(
        children: [
          IconButton(tooltip: tooltip, iconSize: 32, icon: Icon(icon, color: color), onPressed: onTap),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
