import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/report_sheet.dart';
import '../../shared/widgets.dart';
import '../profile/user_profile_screen.dart';
import '../shorts/shorts_screen.dart';
import '../venues/venue_detail_screen.dart';
import 'hashtag_screen.dart';
import 'post_detail_screen.dart';

/// 피드 게시물 카드. 좋아요·저장은 즉시 반영(낙관적 업데이트) 후 실패하면 되돌린다.
class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.post, this.onDeleted, this.openDetailOnTap = true});

  final Post post;
  final VoidCallback? onDeleted;
  final bool openDetailOnTap;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  int _page = 0;

  Post get p => widget.post;

  Future<void> _toggleLike() async {
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

  Future<void> _toggleSave() async {
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

  Future<void> _share() async {
    await Clipboard.setData(ClipboardData(text: 'F-Mate 게시물 https://fmate.app/p/${p.id}'));
    if (mounted) showFmSnack(context, '게시물 링크를 복사했어요');
  }

  void _openDetail() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: p.id, initial: p)));
  }

  Future<void> _menu() async {
    final services = AppScope.read(context);
    final mine = services.session.me?.id == p.author.id;
    final moderator = services.session.me?.isModerator == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mine)
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: Text(p.isHighlight ? '하이라이트에서 빼기' : '하이라이트에 추가'),
                onTap: () => Navigator.of(ctx).pop('highlight'),
              ),
            if (mine || moderator)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: FmColors.danger),
                title: const Text('삭제', style: TextStyle(color: FmColors.danger)),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            if (!mine)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('신고'),
                onTap: () => Navigator.of(ctx).pop('report'),
              ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('링크 복사'),
              onTap: () => Navigator.of(ctx).pop('share'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'delete':
        if (!await confirmDialog(context, title: '게시물을 삭제할까요?', confirm: '삭제', destructive: true)) return;
        if (!mounted) return;
        try {
          await services.social.delete(p.id);
          widget.onDeleted?.call();
          if (mounted) showFmSnack(context, '삭제했어요');
        } catch (e) {
          if (mounted) showError(context, e);
        }
      case 'highlight':
        try {
          await services.social.update(p.id, {'isHighlight': !p.isHighlight});
          if (mounted) showFmSnack(context, p.isHighlight ? '하이라이트에서 뺐어요' : '하이라이트에 추가했어요');
        } catch (e) {
          if (mounted) showError(context, e);
        }
      case 'report':
        if (!requireLogin(context)) return;
        await showReportSheet(context, 'POST', p.id);
      case 'share':
        await _share();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FmSpace.l, vertical: FmSpace.s),
      child: FmCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.only(left: FmSpace.m, right: FmSpace.xs),
              leading: GestureDetector(
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: p.author.id))),
                child: AppAvatar(url: p.author.avatarUrl, name: p.author.nickname),
              ),
              title: Text(p.author.nickname, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              subtitle: Text(
                [
                  Fmt.ago(p.createdAt),
                  if (p.visibility == 'FOLLOWERS') '팔로워 공개',
                  if (p.visibility == 'PRIVATE') '나만 보기',
                  if (p.status == 'PENDING_MEDIA') '영상 처리 중',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: FmColors.textSecondary),
              ),
              trailing: IconButton(tooltip: '더보기', icon: const Icon(Icons.more_horiz_rounded), onPressed: _menu),
            ),
            if (p.images.isNotEmpty) _images(),
            if (p.video != null) _videoThumb(),
            if (p.caption != null && p.caption!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(FmSpace.m, FmSpace.s, FmSpace.m, 0),
                child: GestureDetector(
                  onTap: widget.openDetailOnTap ? _openDetail : null,
                  child: CaptionText(text: p.caption!, maxLines: widget.openDetailOnTap ? 4 : null),
                ),
              ),
            if (p.venueId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(FmSpace.m, FmSpace.s, FmSpace.m, 0),
                child: ActionChip(
                  avatar: const Icon(Icons.place_outlined, size: 16),
                  label: Text(p.venueName ?? '구장'),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => VenueDetailScreen(venueId: p.venueId!))),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FmSpace.xs),
              child: Row(
                children: [
                  IconButton(
                    tooltip: p.likedByMe ? '좋아요 취소' : '좋아요',
                    icon: Icon(p.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: p.likedByMe ? FmColors.danger : FmColors.textPrimary),
                    onPressed: _toggleLike,
                  ),
                  Text(Fmt.count(p.likeCount)),
                  const SizedBox(width: FmSpace.s),
                  IconButton(
                    tooltip: '댓글',
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    onPressed: widget.openDetailOnTap ? _openDetail : null,
                  ),
                  Text(Fmt.count(p.commentCount)),
                  const Spacer(),
                  IconButton(tooltip: '공유', icon: const Icon(Icons.share_outlined), onPressed: _share),
                  IconButton(
                    tooltip: p.savedByMe ? '저장 취소' : '저장',
                    icon: Icon(p.savedByMe ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                    onPressed: _toggleSave,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _images() {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: p.images.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final url = p.images[i].url;
              return url == null
                  ? Container(color: FmColors.surfaceMuted)
                  : Image.network(url, fit: BoxFit.cover, semanticLabel: '게시물 사진 ${i + 1}',
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : Container(color: FmColors.surfaceMuted),
                      errorBuilder: (context, e, s) => Container(
                          color: FmColors.surfaceMuted,
                          child: const Center(child: Icon(Icons.broken_image_outlined, color: FmColors.textSecondary))));
            },
          ),
          if (p.images.length > 1)
            Positioned(
              right: FmSpace.s,
              top: FmSpace.s,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(FmRadius.chip)),
                child: Text('${_page + 1}/${p.images.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _videoThumb() {
    final v = p.video!;
    return GestureDetector(
      onTap: v.ready
          ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShortsScreen(initialPosts: [p])))
          : null,
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            v.thumbnailUrl == null
                ? Container(color: Colors.black87)
                : Image.network(v.thumbnailUrl!, fit: BoxFit.cover,
                    errorBuilder: (context, e, s) => Container(color: Colors.black87)),
            Center(
              child: v.ready
                  ? const Icon(Icons.play_circle_fill_rounded, size: 64, color: Colors.white)
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4)),
                        SizedBox(height: FmSpace.s),
                        Text('영상 처리 중', style: TextStyle(color: Colors.white)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 해시태그를 눌러 이동할 수 있는 본문
class CaptionText extends StatelessWidget {
  const CaptionText({super.key, required this.text, this.maxLines});

  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'#([A-Za-z0-9가-힣_]{1,50})');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final tag = m.group(1)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HashtagScreen(tag: tag))),
          child: Text('#$tag', style: const TextStyle(color: FmColors.brandDark, fontWeight: FontWeight.w600, fontSize: 15)),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(style: const TextStyle(fontSize: 15, height: 1.45, color: FmColors.textPrimary), children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
