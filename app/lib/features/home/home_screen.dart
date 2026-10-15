import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../shorts/shorts_screen.dart';
import '../social/hashtag_search_screen.dart';

enum FeedType { following, recommended }

extension FeedTypeX on FeedType {
  String get label => switch (this) {
        FeedType.following => '팔로잉',
        FeedType.recommended => '추천',
      };

  String get api => switch (this) {
        FeedType.following => 'following',
        FeedType.recommended => 'recommended',
      };
}

/// 홈: 전체 화면 숏폼 피드 (추천 / 팔로잉). 영상·사진을 위아래로 넘겨 본다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.active = true, this.reloadToken = 0});

  /// 홈 탭이 보이는 중인지 (다른 탭이면 영상 멈춤)
  final bool active;

  /// 바뀌면 피드를 처음부터 다시 불러온다 (게시물을 올린 뒤 등)
  final int reloadToken;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FeedType _feed = FeedType.recommended;

  static const double _tabsHeight = 52;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.session,
      builder: (context, _) {
        final loggedIn = services.session.isLoggedIn;
        final top = MediaQuery.paddingOf(context).top;
        return ColoredBox(
          color: FmColors.videoBackground,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!loggedIn)
                FeedMessage(
                  icon: Icons.play_circle_outline_rounded,
                  title: '로그인하고 풋살 피드를 보세요',
                  message: '팀원들의 경기 영상과 사진이 여기에 모여요.',
                  action: FilledButton(
                    key: const Key('home_login_button'),
                    style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                    onPressed: () => requireLogin(context),
                    child: const Text('로그인'),
                  ),
                )
              else
                FullscreenFeed(
                  key: ValueKey('${_feed.api}-${widget.reloadToken}'),
                  active: widget.active,
                  topInset: _tabsHeight,
                  loader: (cursor) => _load(services, cursor),
                  empty: _feed == FeedType.following
                      ? FeedMessage(
                          icon: Icons.person_add_alt_rounded,
                          title: '팔로우한 사람의 게시물이 없어요',
                          message: '추천 피드에서 함께 뛸 사람을 찾아 팔로우해 보세요.',
                          action: TextButton(
                            onPressed: () => setState(() => _feed = FeedType.recommended),
                            child: const Text('추천 보기', style: TextStyle(color: Colors.white)),
                          ),
                        )
                      : const FeedMessage(
                          icon: Icons.smart_display_outlined,
                          title: '아직 올라온 게시물이 없어요',
                          message: '아래 + 버튼으로 첫 경기 영상을 올려 보세요.',
                        ),
                ),
              // 위쪽: 팔로잉 | 추천 + 검색
              Positioned(
                top: top,
                left: 0,
                right: 0,
                height: _tabsHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 56),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final f in FeedType.values) _tab(f, enabled: loggedIn),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: IconButton(
                        tooltip: '검색',
                        icon: const Icon(Icons.search_rounded, color: Colors.white, size: 26),
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const HashtagSearchScreen())),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<CursorPage<Post>> _load(AppServices s, int? cursor) => s.social.feed(_feed.api, cursor);

  Widget _tab(FeedType f, {required bool enabled}) {
    final selected = _feed == f;
    return Semantics(
      button: true,
      selected: selected,
      label: '${f.label} 피드',
      excludeSemantics: true,
      child: InkWell(
        key: Key('feed_${f.api}'),
        onTap: enabled ? () => setState(() => _feed = f) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                f.label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0x9EFFFFFF),
                  fontSize: 17,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)],
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 18,
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
