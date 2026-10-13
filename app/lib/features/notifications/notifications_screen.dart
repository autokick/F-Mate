import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import '../chat/chat_room_screen.dart';
import '../profile/user_profile_screen.dart';
import '../reservations/reservation_detail_screen.dart';
import '../social/post_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = AppScope.read(context);
      try {
        await s.notifications.markAllRead();
        s.unreadNotifications.value = 0;
      } catch (_) {
        // 읽음 처리 실패는 무시 (다음에 다시 시도)
      }
    });
  }

  IconData _icon(String type) {
    if (type.startsWith('RESERVATION')) return Icons.event_available_rounded;
    if (type.startsWith('REFUND')) return Icons.payments_outlined;
    return switch (type) {
      'FOLLOW' || 'FOLLOW_REQUEST' => Icons.person_add_alt_1_rounded,
      'LIKE' => Icons.favorite_rounded,
      'COMMENT' || 'MENTION' => Icons.chat_bubble_rounded,
      'MESSAGE' => Icons.forum_rounded,
      'VIDEO_READY' || 'VIDEO_FAILED' => Icons.movie_rounded,
      'CONTENT_ACTIONED' => Icons.gavel_rounded,
      _ => Icons.notifications_rounded,
    };
  }

  void _open(AppNotification n) {
    Widget? page;
    final rid = n.data['reservationId'];
    if (rid is String) {
      page = ReservationDetailScreen(publicId: rid);
    } else if (n.targetType == 'POST' && n.targetId != null) {
      page = PostDetailScreen(postId: n.targetId!);
    } else if (n.targetType == 'USER' && n.targetId != null) {
      page = UserProfileScreen(userId: n.targetId!);
    } else if (n.targetType == 'CHAT' && n.targetId != null) {
      page = ChatRoomScreen(chatId: n.targetId!);
    }
    if (page != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('알림')),
      body: PagedList<AppNotification>(
        fetch: (cursor) async {
          final list = await services.notifications.list(before: cursor);
          return (list, list.length < 30 ? null : list.last.id);
        },
        itemBuilder: (context, n, i) => ListTile(
          onTap: () => _open(n),
          tileColor: n.read ? null : const Color(0x80E8F7EE),
          leading: n.actor != null
              ? AppAvatar(url: n.actor!.avatarUrl, name: n.actor!.nickname)
              : CircleAvatar(backgroundColor: FmColors.brandSoft, child: Icon(_icon(n.type), color: FmColors.brandDark)),
          title: Text(n.title ?? '알림', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: Text('${n.body ?? ''}\n${Fmt.ago(n.createdAt)}', style: const TextStyle(fontSize: 13, height: 1.4)),
          isThreeLine: true,
        ),
        empty: const EmptyState(icon: Icons.notifications_none_rounded, title: '새 알림이 없어요'),
      ),
    );
  }
}
