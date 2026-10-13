import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/chat_socket.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _key = GlobalKey<AsyncBodyState<List<ChatSummary>>>();
  StreamSubscription<ChatEvent>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= AppScope.of(context).chatSocket.events.listen((e) {
      // 새 메시지가 오면 목록(마지막 메시지·안읽음 수)을 새로 고친다
      if (e is MessageEvent || (e is ConnectionEvent && e.connected)) _key.currentState?.reload();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!services.session.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('채팅')),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: '로그인이 필요해요',
          message: '팀원, 상대팀과 1:1로 대화하려면 로그인해 주세요.',
          actionLabel: '로그인',
          onAction: () => requireLogin(context),
        ),
      );
    }
    final myId = services.session.me!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('채팅')),
      body: AsyncBody<List<ChatSummary>>(
        key: _key,
        load: services.chats.list,
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(
          icon: Icons.forum_outlined,
          title: '아직 대화가 없어요',
          message: '다른 사람의 프로필에서 "메시지"를 눌러 대화를 시작해 보세요.',
        ),
        builder: (context, chats, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (context, i) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final c = chats[i];
              final last = c.lastMessage;
              return ListTile(
                leading: AppAvatar(url: c.other.avatarUrl, name: c.other.nickname, size: 48),
                title: Text(c.other.nickname, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  last == null ? '대화를 시작해 보세요' : '${last.senderId == myId ? '나: ' : ''}${last.body}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (last != null)
                      Text(Fmt.ago(last.createdAt), style: const TextStyle(fontSize: 12, color: FmColors.textSecondary)),
                    if (c.unreadCount > 0) ...[
                      const SizedBox(height: 4),
                      Badge(label: Text(c.unreadCount > 99 ? '99+' : '${c.unreadCount}')),
                    ],
                  ],
                ),
                onTap: () async {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ChatRoomScreen(chatId: c.id, initial: c)));
                  await reload();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
