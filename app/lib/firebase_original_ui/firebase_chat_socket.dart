import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/chat_socket.dart';
import '../core/models.dart';
import 'firebase_legacy_api.dart';

/// Adapter for the collaborator's unchanged chat list and room widgets.
/// Firestore snapshots are mapped into their existing ChatEvent API.
class FirebaseChatSocket extends ChatSocket {
  FirebaseChatSocket(this.api) : super(api.tokens);

  final FirebaseLegacyApi api;
  final _emitter = StreamController<ChatEvent>.broadcast();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _roomsSubscription;
  final _latest =
      <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final _openRooms = <int, StreamSubscription<ChatMessage>>{};

  @override
  Stream<ChatEvent> get events => _emitter.stream;

  @override
  void start() {
    if (_roomsSubscription != null || FirebaseAuth.instance.currentUser == null)
      return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _roomsSubscription = FirebaseFirestore.instance
        .collection('demo_chats')
        .where('members', arrayContains: uid)
        .snapshots(includeMetadataChanges: true)
        .listen((event) {
      final online = !event.metadata.isFromCache;
      if (connected != online) {
        connected = online;
        _emitter.add(ConnectionEvent(connected));
      }
      // Changes in last messages must refresh the existing chat list.
      for (final room in event.docs) {
        if (_latest.containsKey(room.id)) continue;
        _latest[room.id] = room.reference
            .collection('messages')
            .orderBy('sentAt', descending: true)
            .limit(1)
            .snapshots()
            .listen((messages) {
          if (!messages.metadata.isFromCache) {
            _emitter.add(ConnectionEvent(true));
          }
        }, onError: (_) {});
      }
      final active = event.docs.map((e) => e.id).toSet();
      for (final id in _latest.keys.toList()) {
        if (!active.contains(id)) {
          _latest.remove(id)?.cancel();
        }
      }
    }, onError: (_) {
      connected = false;
      _emitter.add(ConnectionEvent(false));
    });
  }

  /// The room still uses ChatRoomScreen and its original message bubbles.
  void watchChat(int id) {
    if (_openRooms.containsKey(id)) return;
    _openRooms[id] = api.watchChat(id).listen((message) {
      _emitter.add(MessageEvent(message));
    }, onError: (_) {
      // The original UI separately shows fetch/send errors.
    });
  }

  void unwatchChat(int id) {
    _openRooms.remove(id)?.cancel();
  }

  @override
  bool send(int chatId, String clientMessageId, String body) {
    // Never pass data into the old WebSocket transport. The original UI
    // gracefully falls back to ChatRepo.send -> Firestore.
    return false;
  }

  @override
  void markRead(int chatId, int messageId) {
    // The Spark demo intentionally does not track personal read receipts.
  }

  @override
  void stop() {
    _roomsSubscription?.cancel();
    _roomsSubscription = null;
    for (final sub in _latest.values) {
      sub.cancel();
    }
    _latest.clear();
    for (final sub in _openRooms.values) {
      sub.cancel();
    }
    _openRooms.clear();
    connected = false;
    _emitter.add(ConnectionEvent(false));
  }
}
