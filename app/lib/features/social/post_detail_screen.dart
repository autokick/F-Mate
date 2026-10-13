import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/report_sheet.dart';
import '../../shared/widgets.dart';
import '../profile/user_profile_screen.dart';
import 'post_card.dart';

/// 게시물 상세 + 댓글 (답글 1단계)
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId, this.initial});

  final int postId;
  final Post? initial;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _bodyKey = GlobalKey<AsyncBodyState<(Post, List<Comment>)>>();
  Comment? _replyTo;
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<(Post, List<Comment>)> _load() async {
    final s = AppScope.read(context).social;
    final post = await s.post(widget.postId);
    final comments = await s.comments(widget.postId);
    return (post, comments);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (!await requireVerified(context)) return;
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      await AppScope.read(context).social.addComment(widget.postId, text, parentId: _replyTo?.parentId ?? _replyTo?.id);
      _input.clear();
      setState(() => _replyTo = null);
      await _bodyKey.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _commentMenu(Comment c, bool canDelete) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('답글 달기'), onTap: () => Navigator.of(ctx).pop('reply')),
          if (canDelete)
            ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: FmColors.danger),
                title: const Text('삭제', style: TextStyle(color: FmColors.danger)),
                onTap: () => Navigator.of(ctx).pop('delete')),
          if (!c.mine)
            ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('신고'), onTap: () => Navigator.of(ctx).pop('report')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reply') {
      setState(() => _replyTo = c);
      _focus.requestFocus();
    } else if (action == 'delete') {
      try {
        await AppScope.read(context).social.deleteComment(c.id);
        await _bodyKey.currentState?.reload();
      } catch (e) {
        if (mounted) showError(context, e);
      }
    } else if (action == 'report') {
      if (requireLogin(context)) await showReportSheet(context, 'COMMENT', c.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).session.me;
    return Scaffold(
      appBar: AppBar(title: const Text('게시물')),
      body: Column(
        children: [
          Expanded(
            child: AsyncBody<(Post, List<Comment>)>(
              key: _bodyKey,
              load: _load,
              builder: (context, data, reload) {
                final (post, comments) = data;
                final roots = comments.where((c) => c.parentId == null).toList();
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: FmSpace.l),
                    children: [
                      PostCard(post: post, openDetailOnTap: false, onDeleted: () => Navigator.of(context).pop()),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, FmSpace.s),
                        child: Text('댓글 ${comments.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      if (comments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(FmSpace.xl),
                          child: Text('첫 댓글을 남겨 보세요', textAlign: TextAlign.center, style: TextStyle(color: FmColors.textSecondary)),
                        ),
                      for (final c in roots) ...[
                        _CommentTile(
                          comment: c,
                          onMore: () => _commentMenu(c, c.mine || post.author.id == me?.id || me?.isModerator == true),
                        ),
                        for (final r in comments.where((x) => x.parentId == c.id))
                          Padding(
                            padding: const EdgeInsets.only(left: 48),
                            child: _CommentTile(
                              comment: r,
                              onMore: () => _commentMenu(r, r.mine || post.author.id == me?.id || me?.isModerator == true),
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          if (_replyTo != null)
            Container(
              color: FmColors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: FmSpace.l, vertical: FmSpace.xs),
              child: Row(children: [
                Expanded(child: Text('${_replyTo!.author.nickname}님에게 답글', style: const TextStyle(fontSize: 13))),
                IconButton(tooltip: '답글 취소', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _replyTo = null)),
              ]),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.s, FmSpace.s),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: '댓글 달기...', counterText: '', border: InputBorder.none),
                    ),
                  ),
                  IconButton(
                    tooltip: '댓글 보내기',
                    icon: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded, color: FmColors.brandDark),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onMore});

  final Comment comment;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: GestureDetector(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: comment.author.id))),
        child: AppAvatar(url: comment.author.avatarUrl, name: comment.author.nickname, size: 34),
      ),
      title: Text.rich(TextSpan(children: [
        TextSpan(text: '${comment.author.nickname}  ', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        TextSpan(text: comment.body, style: const TextStyle(fontSize: 14)),
      ])),
      subtitle: Text(Fmt.ago(comment.createdAt), style: const TextStyle(fontSize: 12)),
      trailing: IconButton(tooltip: '댓글 메뉴', icon: const Icon(Icons.more_vert_rounded, size: 18), onPressed: onMore),
    );
  }
}
