import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../profile/user_profile_screen.dart';
import 'hashtag_screen.dart';

/// 검색: 사람(닉네임) · #해시태그
class HashtagSearchScreen extends StatefulWidget {
  const HashtagSearchScreen({super.key});

  @override
  State<HashtagSearchScreen> createState() => _HashtagSearchScreenState();
}

class _HashtagSearchScreenState extends State<HashtagSearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<UserSummary> _users = [];
  bool _loading = false;

  static const _popular = ['풋살', '하이라이트', '골', '팀원모집', '주말풋살'];

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String get _text => _q.text.trim().replaceFirst(RegExp(r'^#'), '');

  void _changed(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final q = _text;
    if (q.isEmpty || !AppScope.read(context).session.isLoggedIn) {
      setState(() => _users = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final users = await AppScope.read(context).social.searchUsers(q);
      if (mounted && q == _text) setState(() => _users = users);
    } catch (_) {
      if (mounted) setState(() => _users = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openTag(String tag) {
    if (!requireLogin(context)) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => HashtagScreen(tag: tag)));
  }

  @override
  Widget build(BuildContext context) {
    final q = _text;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: FmSpace.l),
          child: TextField(
            controller: _q,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            onSubmitted: (_) {
              if (_text.isNotEmpty) _openTag(_text);
            },
            decoration: InputDecoration(
              hintText: '사람 또는 #해시태그 검색',
              filled: true,
              fillColor: FmColors.surfaceMuted,
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, color: FmColors.textSecondary),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(FmRadius.control), borderSide: BorderSide.none),
            ),
          ),
        ),
      ),
      body: ListView(
        children: [
          if (q.isEmpty) ...[
            const SectionTitle('인기 해시태그'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FmSpace.page),
              child: Wrap(
                spacing: FmSpace.s,
                runSpacing: FmSpace.s,
                children: [
                  for (final t in _popular) ActionChip(label: Text('#$t'), onPressed: () => _openTag(t)),
                ],
              ),
            ),
          ] else ...[
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: FmColors.surfaceMuted,
                child: Icon(Icons.tag_rounded, color: FmColors.textPrimary),
              ),
              title: Text('#$q'),
              subtitle: const Text('해시태그 게시물 보기'),
              onTap: () => _openTag(q),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            for (final u in _users)
              ListTile(
                leading: AppAvatar(url: u.avatarUrl, name: u.nickname, size: 40),
                title: Text(u.nickname),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u.id))),
              ),
          ],
        ],
      ),
    );
  }
}
