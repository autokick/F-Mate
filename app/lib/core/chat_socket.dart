import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'config.dart';
import 'format.dart';
import 'models.dart';

/// 서버 → 앱 이벤트
sealed class ChatEvent {}

class MessageEvent extends ChatEvent {
  MessageEvent(this.message);

  final ChatMessage message;
}

class ReadEvent extends ChatEvent {
  ReadEvent(this.chatId, this.userId, this.messageId);

  final int chatId;
  final int userId;
  final int messageId;
}

class AckEvent extends ChatEvent {
  AckEvent(this.clientMessageId, this.message);

  final String clientMessageId;
  final ChatMessage message;
}

class SendErrorEvent extends ChatEvent {
  SendErrorEvent(this.clientMessageId, this.code, this.message);

  final String? clientMessageId;
  final String code;
  final String? message;
}

class ConnectionEvent extends ChatEvent {
  ConnectionEvent(this.connected);

  final bool connected;
}

/// 채팅 WebSocket. 끊기면 지수 백오프(1→2→4…최대 30초)로 다시 연결하고,
/// 화면은 ConnectionEvent(connected) 를 받으면 REST 로 누락 메시지를 동기화한다.
class ChatSocket {
  ChatSocket(this.tokens);

  final TokenStore tokens;
  final _events = StreamController<ChatEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _ping;
  int _attempt = 0;
  bool _wanted = false;
  bool connected = false;

  Stream<ChatEvent> get events => _events.stream;

  void start() {
    _wanted = true;
    if (_channel == null) _connect();
  }

  void stop() {
    _wanted = false;
    _retry?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setConnected(false);
  }

  /// 연결돼 있으면 소켓으로, 아니면 false (호출 측이 REST 로 보낸다)
  bool send(int chatId, String clientMessageId, String body) {
    if (!connected || _channel == null) return false;
    _channel!.sink.add(jsonEncode({'type': 'send', 'chatId': chatId, 'clientMessageId': clientMessageId, 'body': body}));
    return true;
  }

  void markRead(int chatId, int messageId) {
    if (!connected || _channel == null) return;
    _channel!.sink.add(jsonEncode({'type': 'read', 'chatId': chatId, 'messageId': messageId}));
  }

  Future<void> _connect() async {
    final token = tokens.access;
    if (!_wanted || token == null) return;
    try {
      final ch = WebSocketChannel.connect(Uri.parse(AppConfig.chatSocketUrl));
      _channel = ch;
      await ch.ready;
      ch.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _sub = ch.stream.listen(_onData, onDone: _onClosed, onError: (_) => _onClosed());
    } catch (_) {
      _onClosed();
    }
  }

  void _onData(dynamic raw) {
    Map<String, dynamic> m;
    try {
      m = asMap(jsonDecode('$raw'));
    } catch (_) {
      return;
    }
    switch (asStr(m['type'])) {
      case 'ready':
        _attempt = 0;
        _setConnected(true);
        _ping?.cancel();
        _ping = Timer.periodic(const Duration(seconds: 25), (_) {
          try {
            _channel?.sink.add(jsonEncode({'type': 'ping'}));
          } catch (_) {
            // 다음 재연결에서 처리
          }
        });
      case 'message':
        _events.add(MessageEvent(ChatMessage.fromJson(m['message'])));
      case 'ack':
        _events.add(AckEvent(asStr(m['clientMessageId']), ChatMessage.fromJson(m['message'])));
      case 'read':
        _events.add(ReadEvent(asInt(m['chatId']), asInt(m['userId']), asInt(m['messageId'])));
      case 'error':
        _events.add(SendErrorEvent(asStrOrNull(m['clientMessageId']), asStr(m['code']), asStrOrNull(m['message'])));
      default:
        break;
    }
  }

  void _onClosed() {
    _sub?.cancel();
    _sub = null;
    _ping?.cancel();
    _channel = null;
    _setConnected(false);
    if (!_wanted) return;
    _attempt++;
    final seconds = min(30, pow(2, min(_attempt, 5)).toInt());
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  void _setConnected(bool v) {
    if (connected == v) return;
    connected = v;
    _events.add(ConnectionEvent(v));
  }
}
