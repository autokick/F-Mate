import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../booking/booking_screen.dart';
import '../chat/chat_list_screen.dart';
import '../home/home_screen.dart';
import '../profile/my_screen.dart';
import '../venues/venues_screen.dart';

/// 하단 탭: 홈 · 예약 · 풋살장 · 채팅 · 마이페이지
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  // 처음 열 때만 만들고 이후에는 상태 유지 (불필요한 서버 호출 방지)
  final _built = <int>{0};

  static const _pages = <Widget>[
    HomeScreen(),
    BookingScreen(),
    VenuesScreen(),
    ChatListScreen(),
    MyScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _pages.length; i++) _built.contains(i) ? _pages[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: FmColors.border))),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() {
            _index = i;
            _built.add(i);
          }),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '홈'),
            NavigationDestination(
                icon: Icon(Icons.event_available_outlined), selectedIcon: Icon(Icons.event_available_rounded), label: '예약'),
            NavigationDestination(
                icon: Icon(Icons.sports_soccer_outlined), selectedIcon: Icon(Icons.sports_soccer), label: '풋살장'),
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: '채팅'),
            NavigationDestination(
                icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: '마이'),
          ],
        ),
      ),
    );
  }
}
