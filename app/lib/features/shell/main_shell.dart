import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../chat/chat_list_screen.dart';
import '../home/home_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/my_screen.dart';
import '../social/compose_screen.dart';
import '../venues/venues_screen.dart';

/// 하단 탭: 홈(숏폼) · 구장 · [올리기] · 채팅 · 마이
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  // 처음 열 때만 만들고 이후에는 상태 유지 (불필요한 서버 호출 방지)
  final _built = <int>{0};
  int _homeReload = 0;
  AppServices? _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (!identical(s, _services)) {
      _services?.incomingNotification.removeListener(_onIncoming);
      _services?.goHome.removeListener(_onGoHome);
      _services = s;
      s.incomingNotification.addListener(_onIncoming);
      s.goHome.addListener(_onGoHome);
    }
  }

  @override
  void dispose() {
    _services?.incomingNotification.removeListener(_onIncoming);
    _services?.goHome.removeListener(_onGoHome);
    super.dispose();
  }

  /// '초기화면' 버튼: 홈 탭으로 돌아가 피드를 처음부터
  void _onGoHome() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _index = 0;
      _built.add(0);
      _homeReload++;
    });
  }

  /// 새 알림이 오면 화면 아래에 잠깐 보여준다 (좋아요·댓글·팔로우·예약)
  void _onIncoming() {
    final n = _services?.incomingNotification.value;
    if (n == null || !mounted) return;
    final text = [n.title, n.body].whereType<String>().where((t) => t.isNotEmpty).join(' · ');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        content: Row(children: [
          const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
          const SizedBox(width: FmSpace.s),
          Expanded(child: Text(text.isEmpty ? '새 알림이 있어요' : text, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        action: SnackBarAction(
          label: '보기',
          textColor: const Color(0xFF7EE2B0),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        ),
      ));
  }

  void _select(int i) {
    if (i == _index && i == 0) {
      // 홈을 한 번 더 누르면 새로고침
      setState(() => _homeReload++);
      return;
    }
    setState(() {
      _index = i;
      _built.add(i);
    });
  }

  Future<void> _upload() async {
    if (!await requireVerified(context)) return;
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ComposeScreen()),
    );
    if (created == true && mounted) {
      setState(() {
        _index = 0;
        _homeReload++;
      });
    }
  }

  Widget _page(int i) {
    switch (i) {
      case 0:
        return HomeScreen(active: _index == 0, reloadToken: _homeReload);
      case 1:
        return const VenuesScreen();
      case 2:
        return const ChatListScreen();
      default:
        return const MyScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = _index == 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: dark ? FmColors.videoBackground : FmColors.background,
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < 4; i++) _built.contains(i) ? _page(i) : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: FmBottomBar(index: _index, dark: dark, onSelect: _select, onUpload: _upload),
      ),
    );
  }
}

/// 하단 탭 바. 홈(영상)에서는 어두운 색, 나머지는 흰색.
class FmBottomBar extends StatelessWidget {
  const FmBottomBar({super.key, required this.index, required this.dark, required this.onSelect, required this.onUpload});

  final int index;
  final bool dark;
  final ValueChanged<int> onSelect;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? FmColors.videoBackground : Colors.white;
    final on = dark ? Colors.white : FmColors.ink;
    final off = dark ? const Color(0x9EFFFFFF) : FmColors.textSecondary;
    final unread = AppScope.of(context).unreadNotifications;

    Widget tab(int i, String label, IconData icon, IconData activeIcon, {Widget? badge}) {
      final selected = index == i;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: InkResponse(
            key: Key('nav_$label'),
            onTap: () => onSelect(i),
            radius: 32,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(clipBehavior: Clip.none, children: [
                  Icon(selected ? activeIcon : icon, size: 26, color: selected ? on : off),
                  if (badge != null) Positioned(right: -4, top: -2, child: badge),
                ]),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? on : off)),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: bg,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: dark ? const Color(0x14FFFFFF) : FmColors.divider)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                tab(0, '홈', Icons.home_outlined, Icons.home_rounded),
                tab(1, '구장', Icons.sports_soccer_outlined, Icons.sports_soccer),
                Expanded(
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: '올리기',
                      excludeSemantics: true,
                      child: Material(
                        key: const Key('nav_upload'),
                        color: dark ? Colors.white : FmColors.ink,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onUpload,
                          child: SizedBox(
                            width: 50,
                            height: 36,
                            child: Icon(Icons.add_rounded, size: 26, color: dark ? FmColors.ink : Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                tab(2, '채팅', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
                tab(
                  3,
                  '마이',
                  Icons.person_outline_rounded,
                  Icons.person_rounded,
                  badge: ValueListenableBuilder<int>(
                    valueListenable: unread,
                    builder: (context, n, _) => n > 0
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
