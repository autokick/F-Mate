import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/services.dart';

/// A widget ABOVE MaterialApp's Navigator so taps on nested booking/chat/auth
/// routes also reset the inactivity timer. Only active in Firebase kiosk mode.
class FirebaseExhibitionIdleGuard extends StatefulWidget {
  const FirebaseExhibitionIdleGuard({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<FirebaseExhibitionIdleGuard> createState() =>
      _FirebaseExhibitionIdleGuardState();
}

class _FirebaseExhibitionIdleGuardState
    extends State<FirebaseExhibitionIdleGuard> {
  Timer? _idleTimer;
  bool _promptOpen = false;

  @override
  void initState() {
    super.initState();
    _touch();
  }

  void _touch() {
    if (!AppConfig.exhibitionKiosk || _promptOpen) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(minutes: 5), _onIdle);
  }

  Future<void> _onIdle() async {
    if (!mounted || _promptOpen) return;
    final routeContext = widget.navigatorKey.currentContext;
    if (routeContext == null) {
      _touch();
      return;
    }
    _promptOpen = true;
    final timeout = Timer(const Duration(seconds: 30), () {
      final nav = widget.navigatorKey.currentState;
      if (mounted && nav != null && nav.canPop()) nav.pop(false);
    });
    final keep = await showDialog<bool>(
      context: routeContext,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('체험을 계속하시겠어요?'),
        content: const Text('30초 안에 선택하지 않으면 이전 관람객 보호를 위해 로그아웃합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('체험 종료'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('계속 체험'),
          ),
        ],
      ),
    );
    timeout.cancel();
    if (!mounted) return;
    _promptOpen = false;
    if (keep == true) {
      _touch();
      return;
    }
    try {
      final services = AppScope.read(context);
      if (services.session.isLoggedIn) {
        await services.logout();
      } else if (services.session.guest) {
        services.session.stopBrowsing();
      }
      widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
      services.goHome.value++;
    } finally {
      if (mounted) _touch();
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.exhibitionKiosk) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      child: widget.child,
    );
  }
}
