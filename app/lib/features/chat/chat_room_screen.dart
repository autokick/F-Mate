import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/chat_socket.dart';
import '../../firebase_original_ui/firebase_chat_socket.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/report_sheet.dart';
import '../../shared/widgets.dart';
import '../profile/user_profile_screen.dart';

/// 1:1 채팅방. 소켓이 연결돼 있으면 소켓으로, 끊겨 있으면 REST 로 보낸다.
/// 같은 clientMessageId 로 재전송해도 서버에는 1건만 저장된다.
class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.chatId, this.initial});

  final int chatId;
  final ChatSummary? initial;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = []; // 오래된 → 최신
  ChatSummary? _summary;
  StreamSubscription<ChatEvent>? _sub;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  int _otherRead = 0;
  late AppServices _s;

  @override
  void initState() {
    super.initState();
    _summary = widget.initial;
    _otherRead = widget.initial?.otherLastRead ?? 0;
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200)
        _loadOlder();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    _s = AppScope.of(context);
    _sub = _s.chatSocket.events.listen(_onEvent);
    if (_s.realtime) _s.chatSocket.start();
    if (_s.chatSocket is FirebaseChatSocket) {
      (_s.chatSocket as FirebaseChatSocket).watchChat(widget.chatId);
    }
    _load();
  }

  @override
  void dispose() {
    if (_s.chatSocket is FirebaseChatSocket) {
      (_s.chatSocket as FirebaseChatSocket).unwatchChat(widget.chatId);
    }
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int get _myId => _s.session.me?.id ?? 0;

  Future<void> _load() async {
    try {
      final summary = await _s.chats.get(widget.chatId);
      final latest = await _s.chats.messages(widget.chatId);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _otherRead = summary.otherLastRead;
        _messages
          ..clear()
          ..addAll(latest.reversed);
        _hasOlder = latest.length >= 50;
        _loading = false;
      });
      _markRead();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _messages.isEmpty) return;
    _loadingOlder = true;
    try {
      final firstId = _messages
          .firstWhere((m) => m.id > 0, orElse: () => _messages.first)
          .id;
      final older = await _s.chats.messages(widget.chatId, before: firstId);
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, older.reversed);
        _hasOlder = older.length >= 50;
      });
    } catch (_) {
      // 다음 스크롤에 다시 시도
    } finally {
      _loadingOlder = false;
    }
  }

  /// 재연결 후 누락분 동기화
  Future<void> _syncAfterReconnect() async {
    final lastId = _messages
        .where((m) => m.id > 0)
        .fold<int>(0, (a, m) => m.id > a ? m.id : a);
    try {
      final missed = await _s.chats.messages(widget.chatId, after: lastId);
      if (!mounted || missed.isEmpty) return;
      setState(() {
        for (final m in missed) {
          _upsert(m);
        }
      });
      _markRead();
    } catch (_) {
      // 무시
    }
  }

  void _onEvent(ChatEvent e) {
    if (!mounted) return;
    switch (e) {
      case MessageEvent(:final message):
        if (message.chatId != widget.chatId) return;
        setState(() => _upsert(message));
        if (message.senderId != _myId) _markRead();
      case AckEvent(:final clientMessageId, :final message):
        setState(() {
          _messages.removeWhere(
              (m) => m.clientMessageId == clientMessageId && m.id <= 0);
          _upsert(message);
        });
      case SendErrorEvent(:final clientMessageId, :final code, :final message):
        if (clientMessageId == null) return;
        setState(() {
          for (final m in _messages) {
            if (m.clientMessageId == clientMessageId) {
              m.pending = false;
              m.failed = true;
            }
          }
        });
        showFmSnack(
            context,
            code == 'BLOCKED'
                ? '차단 관계라 메시지를 보낼 수 없어요'
                : (message ?? '메시지를 보내지 못했어요'));
      case ReadEvent(:final chatId, :final messageId):
        if (chatId == widget.chatId) setState(() => _otherRead = messageId);
      case ConnectionEvent(:final connected):
        if (connected) _syncAfterReconnect();
        setState(() {});
    }
  }

  void _upsert(ChatMessage m) {
    final idx = _messages.indexWhere((x) =>
        x.id == m.id && m.id > 0 || x.clientMessageId == m.clientMessageId);
    if (idx >= 0) {
      _messages[idx] = m;
    } else {
      _messages.add(m);
      _messages.sort((a, b) {
        if (a.id > 0 && b.id > 0) return a.id.compareTo(b.id);
        return a.createdAt.compareTo(b.createdAt);
      });
    }
  }

  void _markRead() {
    final lastFromOther =
        _messages.where((m) => m.senderId != _myId && m.id > 0);
    if (lastFromOther.isEmpty) return;
    final id = lastFromOther.last.id;
    if (_s.chatSocket.connected) {
      _s.chatSocket.markRead(widget.chatId, id);
    } else {
      _s.chats.read(widget.chatId, id).catchError((_) {});
    }
  }

  Future<void> _send([ChatMessage? retry]) async {
    final text = retry?.body ?? _input.text.trim();
    if (text.isEmpty) return;
    final cmid = retry?.clientMessageId ?? uuidV4();
    if (retry == null) {
      _input.clear();
      setState(() => _messages.add(ChatMessage(
          id: -DateTime.now().millisecondsSinceEpoch,
          chatId: widget.chatId,
          senderId: _myId,
          clientMessageId: cmid,
          body: text,
          deleted: false,
          createdAt: DateTime.now(),
          pending: true)));
    } else {
      setState(() {
        retry.failed = false;
        retry.pending = true;
      });
    }
    if (_s.chatSocket.send(widget.chatId, cmid, text)) return;
    try {
      final saved = await _s.chats.send(widget.chatId, cmid, text);
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.clientMessageId == cmid && m.id <= 0);
        _upsert(saved);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        for (final m in _messages) {
          if (m.clientMessageId == cmid) {
            m.pending = false;
            m.failed = true;
          }
        }
      });
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = _summary?.other;
    final connected = _s.chatSocket.connected;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: other == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => UserProfileScreen(userId: other.id))),
          child: Row(children: [
            if (other != null)
              AppAvatar(url: other.avatarUrl, name: other.nickname, size: 32),
            const SizedBox(width: FmSpace.s),
            Expanded(
                child: Text(other?.nickname ?? '채팅',
                    overflow: TextOverflow.ellipsis)),
          ]),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'report' && other != null)
                await showReportSheet(context, 'USER', other.id);
              if (v == 'leave') {
                await _s.chats.hide(widget.chatId);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('상대 신고')),
              PopupMenuItem(value: 'leave', child: Text('목록에서 나가기')),
            ],
          ),
        ],
        bottom: connected
            ? null
            : const PreferredSize(
                preferredSize: Size.fromHeight(24),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('실시간 연결 중... (메시지는 계속 보낼 수 있어요)',
                      style: TextStyle(
                          fontSize: 12, color: FmColors.textSecondary)),
                ),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const LoadingState()
                : _messages.isEmpty
                    ? const EmptyState(
                        icon: Icons.waving_hand_outlined,
                        title: '첫 메시지를 보내 보세요')
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.all(FmSpace.m),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[_messages.length - 1 - i];
                          final mine = m.senderId == _myId;
                          final isLastMine = mine &&
                              m.id > 0 &&
                              _messages
                                      .lastWhere(
                                          (x) =>
                                              x.senderId == _myId && x.id > 0,
                                          orElse: () => m)
                                      .id ==
                                  m.id;
                          return _Bubble(
                            message: m,
                            mine: mine,
                            read: mine &&
                                m.id > 0 &&
                                m.id <= _otherRead &&
                                isLastMine,
                            onRetry: m.failed ? () => _send(m) : null,
                          );
                        },
                      ),
          ),
          if (_summary?.blocked == true)
            const Padding(
              padding: EdgeInsets.all(FmSpace.m),
              child: Text('차단 관계라 메시지를 보낼 수 없어요',
                  style: TextStyle(color: FmColors.textSecondary)),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    FmSpace.m, FmSpace.xs, FmSpace.xs, FmSpace.s),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          hintText: '메시지 입력',
                          counterText: '',
                          filled: true,
                          fillColor: FmColors.surfaceMuted,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: FmSpace.l, vertical: FmSpace.s),
                        ),
                      ),
                    ),
                    IconButton(
                        tooltip: '보내기',
                        icon: const Icon(Icons.send_rounded,
                            color: FmColors.brandDark),
                        onPressed: () => _send()),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(
      {required this.message,
      required this.mine,
      required this.read,
      this.onRetry});

  final ChatMessage message;
  final bool mine;
  final bool read;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final meta = message.failed
        ? '전송 실패 · 다시 보내기'
        : message.pending
            ? '보내는 중'
            : '${Fmt.time(message.createdAt)}${read ? ' · 읽음' : ''}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: mine ? FmColors.brandDark : FmColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  message.body,
                  style: TextStyle(
                    color: mine ? Colors.white : FmColors.textPrimary,
                    fontStyle:
                        message.deleted ? FontStyle.italic : FontStyle.normal,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: onRetry,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(meta,
                    style: TextStyle(
                        fontSize: 11,
                        color: message.failed
                            ? FmColors.danger
                            : FmColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
