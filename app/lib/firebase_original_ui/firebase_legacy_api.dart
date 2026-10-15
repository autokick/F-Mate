import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'demo_venue_catalog.dart';

/// Adapt the *existing collaborator REST repositories and widgets* to Firebase.
/// This is NOT a Spring Boot HTTP proxy; unsupported endpoints fail explicitly.
class FirebaseLegacyApi extends ApiClient {
  FirebaseLegacyApi(super.tokens);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Map<int, String> _postIds = {};
  final Map<int, String> _chatIds = {};
  final Map<int, DocumentReference<Map<String, dynamic>>> _commentRefs = {};

  static int displayId(String input) {
    var result = 0;
    for (final rune in input.runes) {
      result = ((result * 31) + rune) & 0x7fffffff;
    }
    return result;
  }

  String get _uid =>
      _auth.currentUser?.uid ??
      (throw ApiError('UNAUTHENTICATED', '로그인이 필요한 기능입니다', status: 401));

  Future<void> requireVerified() async {
    final user = _auth.currentUser;
    if (user == null)
      throw ApiError('UNAUTHENTICATED', '로그인이 필요합니다', status: 401);
    await user.reload();
    if (_auth.currentUser?.emailVerified != true) {
      throw ApiError('EMAIL_UNVERIFIED', '이메일 인증을 먼저 완료하세요');
    }
  }

  DocumentReference<Map<String, dynamic>> get _profile =>
      _db.collection('profiles').doc(_uid);

  Future<String> _nickname() async {
    final p = await _profile.get();
    return (p.data()?['nickname'] as String?) ?? '전시 체험 회원';
  }

  static DateTime _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse('$value') ?? DateTime.now();
  }

  static String _iso(Object? value) => _date(value).toUtc().toIso8601String();

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _dispatch('GET', path, query: query);

  @override
  Future<dynamic> post(String path, {Object? body, String? idempotencyKey}) =>
      _dispatch('POST', path, body: body, idempotencyKey: idempotencyKey);

  @override
  Future<dynamic> put(String path, {Object? body}) =>
      _dispatch('PUT', path, body: body);

  @override
  Future<dynamic> patch(String path, {Object? body}) =>
      _dispatch('PATCH', path, body: body);

  @override
  Future<dynamic> delete(String path, {Object? body}) =>
      _dispatch('DELETE', path, body: body);

  Future<dynamic> _dispatch(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    try {
      final data =
          body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
      final segments = Uri.parse(path).pathSegments;

      // Screen navigation and data models stay unchanged. Only their backend changes.
      if (path == '/api/v1/venues' && method == 'GET') return _venues(query);
      if (path == '/api/v1/facilities' && method == 'GET') return <Object>[];
      if (segments.length == 4 && segments[2] == 'venues') {
        final venueId = int.tryParse(segments[3]);
        if (venueId != null) {
          final venue = findDemoVenue(venueId);
          if (venue == null)
            throw ApiError('NOT_FOUND', '구장을 찾을 수 없어요', status: 404);
          if (method == 'GET') return venue.detail;
        }
      }
      if (segments.length == 5 &&
          segments[2] == 'venues' &&
          segments[4] == 'availability' &&
          method == 'GET') {
        final venue = findDemoVenue(int.tryParse(segments[3]) ?? -1);
        if (venue == null)
          throw ApiError('NOT_FOUND', '구장을 찾을 수 없어요', status: 404);
        return await _availability(venue, _date(query?['date']));
      }

      if (path == '/api/v1/reservations' && method == 'POST') {
        return await _createReservation(data, idempotencyKey);
      }
      if (path == '/api/v1/reservations' && method == 'GET') {
        return await _reservations(query);
      }
      if (segments.length == 4 && segments[2] == 'reservations') {
        if (method == 'GET') return await _reservation(segments[3]);
      }
      if (segments.length == 5 &&
          segments[2] == 'reservations' &&
          segments[4] == 'cancel' &&
          method == 'POST') {
        return await _cancelReservation(segments[3], data);
      }

      if (path == '/api/v1/feed' && method == 'GET') return await _feed(query);
      if (path == '/api/v1/shorts' && method == 'GET') {
        return {'items': <Object>[], 'nextCursor': null};
      }
      if (path == '/api/v1/posts' && method == 'POST')
        return await _createPost(data);
      if (segments.length == 5 &&
          segments[2] == 'posts' &&
          int.tryParse(segments[3]) != null) {
        final postId = int.parse(segments[3]);
        if (segments[4] == 'like' && (method == 'PUT' || method == 'DELETE')) {
          return await _likePost(postId, method == 'PUT');
        }
        if (segments[4] == 'save' && (method == 'PUT' || method == 'DELETE')) {
          return await _savePost(postId, method == 'PUT');
        }
        if (segments[4] == 'comments' && method == 'GET') {
          return await _comments(postId);
        }
        if (segments[4] == 'comments' && method == 'POST') {
          return await _addComment(postId, data);
        }
      }
      if (segments.length == 4 &&
          segments[2] == 'comments' &&
          method == 'DELETE') {
        return await _deleteComment(int.parse(segments[3]));
      }
      if (segments.length == 4 && segments[2] == 'posts' && method == 'GET') {
        return await _post(int.parse(segments[3]));
      }
      if (segments.length == 4 &&
          segments[2] == 'posts' &&
          method == 'DELETE') {
        return await _deletePost(int.parse(segments[3]));
      }
      if (segments.length == 5 &&
          segments[2] == 'users' &&
          segments[4] == 'posts') {
        return await _userPosts(int.parse(segments[3]));
      }
      if (path == '/api/v1/me/saved' && method == 'GET') {
        return await _savedPosts();
      }
      if (path == '/api/v1/users/search' && method == 'GET') {
        return await _searchUsers(query?['q']?.toString() ?? '');
      }
      if (segments.length == 4 &&
          segments[2] == 'users' &&
          int.tryParse(segments[3]) != null &&
          method == 'GET') {
        return await _userProfile(int.parse(segments[3]));
      }
      if (segments.length == 5 &&
          segments[2] == 'hashtags' &&
          segments[4] == 'posts') {
        final tag = Uri.decodeComponent(segments[3]).toLowerCase();
        final all = await _feed({'type': 'recommended'});
        final matching = (all['items'] as List)
            .where((item) => ((item as Map<String, dynamic>)['caption'] ?? '')
                .toString()
                .toLowerCase()
                .contains('#$tag'))
            .toList();
        return {'items': matching, 'nextCursor': null};
      }

      if (path == '/api/v1/chats' && method == 'GET') return await _chats();
      if (path == '/api/v1/chats' && method == 'POST')
        return await _openChat(data);
      if (segments.length >= 4 &&
          segments[2] == 'chats' &&
          int.tryParse(segments[3]) != null) {
        final id = int.parse(segments[3]);
        if (segments.length == 4 && method == 'GET') return await _chat(id);
        if (segments.length == 5 &&
            segments[4] == 'messages' &&
            method == 'GET') {
          return await _messages(id, query);
        }
        if (segments.length == 5 &&
            segments[4] == 'messages' &&
            method == 'POST') {
          return await _sendMessage(id, data);
        }
        if (segments.length == 5 && segments[4] == 'read' && method == 'POST')
          return {};
        if (segments.length == 5 && segments[4] == 'hide' && method == 'POST')
          return {};
      }

      if (path == '/api/v1/me/profile' && method == 'PATCH') {
        return await _updateProfile(data);
      }
      if (path == '/api/v1/notifications' && method == 'GET') return <Object>[];
      if (path == '/api/v1/notifications/unread-count' && method == 'GET') {
        return {'count': 0};
      }
      if (path == '/api/v1/notifications/read' && method == 'POST') return {};
      if (path == '/api/v1/me/notification-settings' && method == 'GET') {
        return {
          'reservation': false,
          'social': false,
          'chat': false,
          'marketing': false
        };
      }

      throw ApiError(
          'EXHIBITION_UNAVAILABLE',
          '이 기능은 Firebase 무료 전시 버전으로 아직 이전되지 않았습니다. '
              '기존 UI는 보존되지만 미구현 기능은 실행되지 않습니다.');
    } on FirebaseException catch (e) {
      throw ApiError(
          'FIRESTORE_${e.code.toUpperCase()}',
          e.code == 'permission-denied'
              ? 'Firestore 규칙이 이 작업을 허용하지 않아요. 새 보안 규칙을 게시했는지 확인해 주세요.'
              : 'Firebase 연결 실패: ${e.code}');
    }
  }

  Map<String, dynamic> _venues(Map<String, dynamic>? q) {
    final needle = (q?['q']?.toString() ?? '').trim().toLowerCase();
    final indoor = q?['indoor'];
    final size = q?['size']?.toString();
    final page = int.tryParse('${q?['page'] ?? 0}') ?? 0;
    final count = max(1, int.tryParse('${q?['pageSize'] ?? 20}') ?? 20);
    final matched = demonstrationVenues.where((venue) {
      if (needle.isNotEmpty &&
          !venue.name.toLowerCase().contains(needle) &&
          !venue.locationLabel.toLowerCase().contains(needle)) return false;
      if (indoor is bool && venue.indoor != indoor) return false;
      if (size != null && size.isNotEmpty && venue.size != size) return false;
      return true;
    }).toList();
    final start = max(0, page * count);
    final visible = start < matched.length
        ? matched.skip(start).take(count).toList()
        : <DemoVenue>[];
    return {
      'items': visible.map((v) => v.card).toList(),
      'hasNext': start + count < matched.length,
    };
  }

  Future<List<Object>> _availability(DemoVenue venue, DateTime day) async {
    final date = DateTime(day.year, day.month, day.day);
    final blocks = [18, 19, 20]
        .map((hour) => DateTime(date.year, date.month, date.day, hour))
        .toList();
    final docs = await Future.wait([
      for (final start in blocks)
        _db.collection('demo_slots').doc(demoSlotId(venue, start)).get(),
    ]);
    final slots = <Map<String, dynamic>>[];
    for (var i = 0; i < blocks.length; i++) {
      slots.add({
        'slotId': venue.courtId * 100 + blocks[i].hour,
        'startsAt': blocks[i].toUtc().toIso8601String(),
        'endsAt':
            blocks[i].add(const Duration(hours: 1)).toUtc().toIso8601String(),
        'price': venue.price,
        'available': !docs[i].exists && blocks[i].isAfter(DateTime.now()),
      });
    }
    return [
      {
        'courtId': venue.courtId,
        'courtName': '시연 코트',
        'isIndoor': venue.indoor,
        'sizeClass': venue.size,
        'slots': slots,
      }
    ];
  }

  CollectionReference<Map<String, dynamic>> get _myReservations =>
      _db.collection('private_users').doc(_uid).collection('demo_reservations');

  Map<String, dynamic> _reservationJson(String id, Map<String, dynamic> data) {
    final venue = findDemoVenue((data['venueId'] as num?)?.toInt() ?? -1);
    if (venue == null)
      throw ApiError('INVALID_DEMO_VENUE', '시연 구장 정보를 찾을 수 없습니다');
    final start = _iso(data['startsAt']);
    final end = _iso(data['endsAt']);
    return {
      'publicId': id,
      'venue': {
        'id': venue.id,
        'name': venue.name,
        'roadAddress': venue.locationLabel,
        'phone': null,
      },
      'court': {
        'name': '시연 코트',
        'isIndoor': venue.indoor,
        'sizeClass': venue.size,
      },
      'startsAt': start,
      'endsAt': end,
      'totalAmount': data['totalAmount'] ?? 0,
      'status': data['status'] ?? 'PENDING_PAYMENT',
      'cancelPolicy': venue.detail['cancelPolicy'],
      'refundIfCanceledNow': data['totalAmount'] ?? 0,
      'holdExpiresAt': null,
      'canceledAt':
          data['canceledAt'] == null ? null : _iso(data['canceledAt']),
      'cancelReason': data['cancelReason'],
      'refunds': <Object>[],
      'history': <Object>[],
      'payment': null,
    };
  }

  Future<Map<String, dynamic>> _createReservation(
      Map<String, dynamic> data, String? idempotencyKey) async {
    await requireVerified();
    final courtId = (data['courtId'] as num?)?.toInt() ?? -1;
    final venue = findDemoVenue(courtId);
    if (venue == null || venue.courtId != courtId) {
      throw ApiError('SLOT_UNAVAILABLE', '지원하지 않는 시연 코트입니다');
    }
    final start = _date(data['startsAt']).toLocal();
    final end = _date(data['endsAt']).toLocal();
    if (!start.isAfter(DateTime.now()) ||
        !end.isAfter(start) ||
        end.difference(start).inHours < 1 ||
        end.difference(start).inHours > 3 ||
        end.difference(start).inMinutes % 60 != 0 ||
        start.minute != 0 ||
        end.minute != 0 ||
        end.day != start.day ||
        end.month != start.month) {
      throw ApiError('SLOT_UNAVAILABLE', '시연 예약은 같은 날 18~21시, 1시간 단위만 가능합니다');
    }
    final blocks = <DateTime>[];
    for (var t = start; t.isBefore(end); t = t.add(const Duration(hours: 1))) {
      if (t.hour < 18 || t.hour > 20) {
        throw ApiError('SLOT_UNAVAILABLE', '시연 가능한 시간은 18~21시입니다');
      }
      blocks.add(t);
    }
    final id = idempotencyKey?.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '') ??
        'demo_${DateTime.now().microsecondsSinceEpoch}';
    final reservationRef = _myReservations.doc(id);
    final slotRefs = [
      for (final start in blocks)
        _db.collection('demo_slots').doc(demoSlotId(venue, start)),
    ];
    await _db.runTransaction((tx) async {
      final existing = await tx.get(reservationRef);
      if (existing.exists) return;
      final slots = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in slotRefs) {
        slots.add(await tx.get(ref));
      }
      if (slots.any((snap) => snap.exists)) {
        throw ApiError('SLOT_TAKEN', '다른 관람객이 이 시간을 먼저 예약했어요');
      }
      for (var i = 0; i < slotRefs.length; i++) {
        tx.set(slotRefs[i], {
          'ownerUid': _uid,
          'venueId': venue.slug,
          'dateKey': demoDateKey(blocks[i]),
          'hour': blocks[i].hour,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      tx.set(reservationRef, {
        'ownerUid': _uid,
        'venueId': venue.id,
        'courtId': courtId,
        'startsAt': Timestamp.fromDate(start.toUtc()),
        'endsAt': Timestamp.fromDate(end.toUtc()),
        'totalAmount': venue.price * blocks.length,
        'status': 'PENDING_PAYMENT',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    final saved = await reservationRef.get();
    if (!saved.exists) throw ApiError('FIRESTORE', '시연 예약 저장을 확인하지 못했습니다');
    return _reservationJson(id, saved.data()!);
  }

  Future<Map<String, dynamic>> _reservation(String id) async {
    final snap = await _myReservations.doc(id).get();
    if (!snap.exists) throw ApiError('NOT_FOUND', '예약 기록이 없습니다', status: 404);
    return _reservationJson(id, snap.data()!);
  }

  Future<List<Object>> _reservations(Map<String, dynamic>? query) async {
    final records = await _myReservations.limit(100).get();
    final selectedStatus = query?['status']?.toString();
    final items = <Map<String, dynamic>>[];
    for (final snap in records.docs) {
      final d = snap.data();
      if (selectedStatus != null &&
          selectedStatus.isNotEmpty &&
          selectedStatus != d['status']) continue;
      final full = _reservationJson(snap.id, d);
      items.add({
        'publicId': snap.id,
        'venueName': (full['venue'] as Map)['name'],
        'courtName': '시연 코트',
        'startsAt': full['startsAt'],
        'endsAt': full['endsAt'],
        'totalAmount': full['totalAmount'],
        'status': full['status'],
      });
    }
    items.sort((a, b) => '${b['startsAt']}'.compareTo('${a['startsAt']}'));
    final page = int.tryParse('${query?['page'] ?? 0}') ?? 0;
    return items.skip(max(0, page * 20)).take(20).toList();
  }

  Future<Map<String, dynamic>> _cancelReservation(
      String id, Map<String, dynamic> data) async {
    await requireVerified();
    final reservationRef = _myReservations.doc(id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(reservationRef);
      if (!snap.exists) throw ApiError('NOT_FOUND', '시연 예약을 찾을 수 없어요');
      final current = snap.data()!;
      if (current['status'] == 'CANCELED') return;
      if (current['status'] != 'PENDING_PAYMENT') {
        throw ApiError('INVALID_STATE', '취소할 수 없는 예약 상태입니다');
      }
      final venue = findDemoVenue((current['venueId'] as num).toInt());
      if (venue == null) throw ApiError('NOT_FOUND', '구장 정보가 없습니다');
      final start = _date(current['startsAt']).toLocal();
      final end = _date(current['endsAt']).toLocal();
      final references = <DocumentReference<Map<String, dynamic>>>[];
      for (var time = start;
          time.isBefore(end);
          time = time.add(const Duration(hours: 1))) {
        references
            .add(_db.collection('demo_slots').doc(demoSlotId(venue, time)));
      }
      final slotSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in references) {
        slotSnapshots.add(await tx.get(ref));
      }
      for (var i = 0; i < references.length; i++) {
        if (slotSnapshots[i].data()?['ownerUid'] == _uid)
          tx.delete(references[i]);
      }
      tx.update(reservationRef, {
        'status': 'CANCELED',
        'canceledAt': FieldValue.serverTimestamp(),
        'cancelReason': (data['reason']?.toString() ?? '')
            .substring(0, min(120, (data['reason']?.toString() ?? '').length)),
      });
    });
    return _reservation(id);
  }

  int _postId(String documentId) {
    final id = displayId(documentId);
    _postIds[id] = documentId;
    return id;
  }

  Map<String, dynamic> _jsonPost(String docId, Map<String, dynamic> data) {
    final uid = '${data['authorUid'] ?? ''}';
    return {
      'id': _postId(docId),
      'author': {
        'id': displayId(uid),
        'nickname': data['authorName'] ?? '체험 회원',
        'avatarUrl': null,
      },
      'kind': 'TEXT',
      'caption': data['body'] ?? '',
      'visibility': 'PUBLIC',
      'isHighlight': false,
      'status': 'READY',
      'images': <Object>[],
      'video': null,
      'likeCount': 0,
      'commentCount': 0,
      'likedByMe': false,
      'savedByMe': false,
      'createdAt': _iso(data['createdAt']),
    };
  }

  Future<Map<String, dynamic>> _feed(Map<String, dynamic>? query) async {
    if (query?['type'] == 'following' || query?['type'] == 'venue') {
      return {'items': <Object>[], 'nextCursor': null};
    }
    final snaps = await _db
        .collection('demo_posts')
        .orderBy('createdAt', descending: true)
        .limit(40)
        .get();
    final posts = <Map<String, dynamic>>[];
    for (final post in snaps.docs) {
      posts.add(await _decoratePost(post));
    }
    return {'items': posts, 'nextCursor': null};
  }

  Future<DocumentReference<Map<String, dynamic>>> _postRef(int id) async {
    var mapped = _postIds[id];
    if (mapped != null) return _db.collection('demo_posts').doc(mapped);
    final snaps = await _db
        .collection('demo_posts')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    for (final snap in snaps.docs) {
      if (_postId(snap.id) == id) {
        mapped = snap.id;
        break;
      }
    }
    if (mapped == null) throw ApiError('NOT_FOUND', '게시글을 찾을 수 없어요');
    return _db.collection('demo_posts').doc(mapped);
  }

  Future<Map<String, dynamic>> _post(int id) async {
    final ref = await _postRef(id);
    final snap = await ref.get();
    if (!snap.exists) throw ApiError('NOT_FOUND', '게시글이 삭제됐어요');
    return _decoratePost(snap);
  }

  Future<Map<String, dynamic>> _createPost(Map<String, dynamic> data) async {
    await requireVerified();
    final kind = (data['kind'] ?? 'TEXT').toString();
    final visibility = (data['visibility'] ?? 'PUBLIC').toString();
    final body = (data['caption'] ?? '').toString().trim();
    if (kind != 'TEXT' || visibility != 'PUBLIC') {
      throw ApiError('EXHIBITION_UNAVAILABLE',
          'Spark 전시 모드에서는 공개 텍스트 게시글만 가능합니다. 사진·영상 저장소는 아직 연결하지 않았습니다.');
    }
    if (body.isEmpty || body.length > 400) {
      throw ApiError('INVALID_BODY', '글은 1~400자로 작성해 주세요');
    }
    final ref = await _db.collection('demo_posts').add({
      'authorUid': _uid,
      'authorName': await _nickname(),
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final saved = await ref.get();
    return _jsonPost(ref.id, saved.data()!);
  }

  Future<void> _deletePost(int id) async {
    await requireVerified();
    await (await _postRef(id)).delete();
  }

  Future<Map<String, dynamic>> _userPosts(int userId) async {
    final all = await _feed({'type': 'recommended'});
    final items = (all['items'] as List)
        .where((p) => (p as Map<String, dynamic>)['author']?['id'] == userId)
        .toList();
    return {'items': items, 'nextCursor': null};
  }

  Future<List<Object>> _searchUsers(String needle) async {
    if (_auth.currentUser == null) return [];
    final snap = await _db.collection('profiles').limit(60).get();
    final lower = needle.toLowerCase();
    return [
      for (final user in snap.docs)
        if (user.id != _uid &&
            (user.data()['nickname']?.toString() ?? '')
                .toLowerCase()
                .contains(lower))
          {
            'id': displayId(user.id),
            'nickname': user.data()['nickname'],
            'avatarUrl': null,
          },
    ];
  }

  Future<String> _userUid(int display) async {
    if (displayId(_uid) == display) return _uid;
    final snap = await _db.collection('profiles').limit(100).get();
    for (final profile in snap.docs) {
      if (displayId(profile.id) == display) return profile.id;
    }
    throw ApiError('NOT_FOUND', '전시 참가자를 찾을 수 없어요');
  }

  Future<Map<String, dynamic>> _userProfile(int display) async {
    final uid = await _userUid(display);
    final profile = await _db.collection('profiles').doc(uid).get();
    final nickname = profile.data()?['nickname'] ?? '전시 회원';
    return {
      'id': display,
      'nickname': nickname,
      'bio': profile.data()?['bio'],
      'avatarUrl': null,
      'regionCode': profile.data()?['regionCode'],
      'preferredPosition': profile.data()?['preferredPosition'],
      'isPrivate': false,
      'counts': {'posts': 0, 'followers': 0, 'following': 0},
      'followStatus': 'NONE',
      'followsMe': false,
      'blockedByMe': false,
      'canViewPosts': true,
    };
  }

  Future<Map<String, dynamic>> _decoratePost(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final result = _jsonPost(doc.id, doc.data()!);
    final likes = await doc.reference.collection('likes').get();
    final comments = await doc.reference.collection('comments').count().get();
    result['likeCount'] = likes.size;
    result['commentCount'] = comments.count ?? 0;
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      result['likedByMe'] = likes.docs.any((d) => d.id == uid);
      final saved = await _db
          .collection('private_users')
          .doc(uid)
          .collection('saved_posts')
          .doc(doc.id)
          .get();
      result['savedByMe'] = saved.exists;
    }
    return result;
  }

  Future<void> _likePost(int postId, bool enabled) async {
    await requireVerified();
    final ref = (await _postRef(postId)).collection('likes').doc(_uid);
    if (enabled) {
      if (!(await ref.get()).exists) {
        await ref.set({'createdAt': FieldValue.serverTimestamp()});
      }
    } else {
      await ref.delete();
    }
  }

  Future<void> _savePost(int postId, bool enabled) async {
    await requireVerified();
    final postRef = await _postRef(postId);
    final ref = _db
        .collection('private_users')
        .doc(_uid)
        .collection('saved_posts')
        .doc(postRef.id);
    if (enabled) {
      if (!(await ref.get()).exists) {
        await ref.set({'createdAt': FieldValue.serverTimestamp()});
      }
    } else {
      await ref.delete();
    }
  }

  Future<Map<String, dynamic>> _savedPosts() async {
    final saved = await _db
        .collection('private_users')
        .doc(_uid)
        .collection('saved_posts')
        .limit(40)
        .get();
    final posts = <Map<String, dynamic>>[];
    for (final bookmark in saved.docs) {
      final snap = await _db.collection('demo_posts').doc(bookmark.id).get();
      if (snap.exists) posts.add(await _decoratePost(snap));
    }
    return {'items': posts, 'nextCursor': null};
  }

  Future<List<Object>> _comments(int postId) async {
    final ref = await _postRef(postId);
    final result =
        await ref.collection('comments').orderBy('createdAt').limit(100).get();
    return [
      for (final comment in result.docs)
        _commentJson(ref.id, comment.id, comment.data(), comment.reference),
    ];
  }

  Map<String, dynamic> _commentJson(String postDoc, String commentDoc,
      Map<String, dynamic> data, DocumentReference<Map<String, dynamic>> ref) {
    final id = displayId('$postDoc/$commentDoc');
    _commentRefs[id] = ref;
    final parent = data['parentId'];
    return {
      'id': id,
      'parentId': parent == null ? null : displayId('$postDoc/$parent'),
      'author': {
        'id': displayId(data['authorUid']?.toString() ?? ''),
        'nickname': data['authorName'] ?? '시연 회원',
        'avatarUrl': null,
      },
      'body': data['body'] ?? '',
      'createdAt': _iso(data['createdAt']),
      'mine': _auth.currentUser?.uid == data['authorUid'],
    };
  }

  Future<Map<String, dynamic>> _addComment(
      int postId, Map<String, dynamic> data) async {
    await requireVerified();
    final text = data['body']?.toString().trim() ?? '';
    if (text.isEmpty || text.length > 1000) {
      throw ApiError('INVALID_BODY', '댓글은 1~1000자로 작성해 주세요');
    }
    final post = await _postRef(postId);
    String? parentDoc;
    if (data['parentId'] != null) {
      final parentRef = _commentRefs[(data['parentId'] as num).toInt()];
      if (parentRef == null || parentRef.parent.parent?.id != post.id) {
        throw ApiError('NOT_FOUND', '답글을 달 댓글을 찾지 못했어요');
      }
      parentDoc = parentRef.id;
    }
    final ref = await post.collection('comments').add({
      'authorUid': _uid,
      'authorName': await _nickname(),
      'body': text,
      'parentId': parentDoc,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final saved = await ref.get();
    return _commentJson(post.id, ref.id, saved.data()!, ref);
  }

  Future<void> _deleteComment(int id) async {
    await requireVerified();
    final ref = _commentRefs[id];
    if (ref == null) throw ApiError('NOT_FOUND', '댓글을 다시 불러온 후 삭제해 주세요');
    await ref.delete();
  }

  Future<Map<String, dynamic>> _updateProfile(Map<String, dynamic> data) async {
    final uid = _uid;
    final nickname = (data['nickname'] ?? '').toString().trim();
    final bio = (data['bio'] ?? '').toString().trim();
    final position = (data['preferredPosition'] ?? '').toString();
    final region = (data['regionCode'] ?? '').toString();
    if (data['isPrivate'] == true) {
      throw ApiError('EXHIBITION_UNAVAILABLE',
          'Spark 전시 모드에서는 비공개 계정·팔로워 승인 기능이 아직 지원되지 않습니다');
    }
    if (nickname.length < 2 ||
        nickname.length > 20 ||
        bio.length > 300 ||
        (position.isNotEmpty &&
            !const ['PIVO', 'ALA', 'FIXO', 'GOLEIRO', 'ANY']
                .contains(position)) ||
        region.length > 5) {
      throw ApiError('INVALID_PROFILE', '닉네임·소개·지역 정보를 확인해 주세요');
    }
    await _profile.update({
      'nickname': nickname,
      'bio': bio,
      'preferredPosition': position,
      'regionCode': region,
    });
    await _auth.currentUser?.updateDisplayName(nickname);
    return {
      'id': displayId(uid),
      'email': _auth.currentUser?.email,
      'emailVerified': _auth.currentUser?.emailVerified == true,
      'role': 'USER',
      'nickname': nickname,
      'bio': bio,
      'regionCode': region,
      'preferredPosition': position,
      'isPrivate': false,
      'counts': {'posts': 0, 'followers': 0, 'following': 0},
      'hasPassword': true,
      'socialProviders': <String>[],
      'consents': <String, bool>{},
      'operatorVenueIds': <int>[],
      'needsProfile': false,
    };
  }

  int _chatId(String documentId) {
    final id = displayId(documentId);
    _chatIds[id] = documentId;
    return id;
  }

  Future<String> chatDocumentId(int id) async {
    final cached = _chatIds[id];
    if (cached != null) return cached;
    final rooms = await _db
        .collection('demo_chats')
        .where('members', arrayContains: _uid)
        .limit(60)
        .get();
    for (final room in rooms.docs) {
      if (_chatId(room.id) == id) return room.id;
    }
    throw ApiError('NOT_FOUND', '채팅방을 찾을 수 없어요');
  }

  Map<String, dynamic> _messageJson(
      String roomId, String messageId, Map<String, dynamic> data) {
    return {
      'id': displayId(messageId),
      'chatId': _chatId(roomId),
      'senderId': displayId(data['authorUid']?.toString() ?? ''),
      'clientMessageId': messageId,
      'body': data['text'] ?? '',
      'deleted': false,
      'createdAt': _iso(data['sentAt']),
    };
  }

  Future<Map<String, dynamic>> _roomJson(
      DocumentSnapshot<Map<String, dynamic>> room) async {
    if (!room.exists) throw ApiError('NOT_FOUND', '채팅방이 없어요');
    final members =
        List<String>.from(room.data()?['members'] ?? const <String>[]);
    final other = members.where((s) => s != _uid).firstOrNull;
    if (other == null) throw ApiError('NOT_FOUND', '상대방이 없어요');
    final otherProfile = await _db.collection('profiles').doc(other).get();
    final latest = await room.reference
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(1)
        .get();
    return {
      'id': _chatId(room.id),
      'other': {
        'id': displayId(other),
        'nickname': otherProfile.data()?['nickname'] ?? '전시 회원',
        'avatarUrl': null,
      },
      'lastMessage': latest.docs.isEmpty
          ? null
          : _messageJson(
              room.id, latest.docs.first.id, latest.docs.first.data()),
      'unreadCount': 0,
      'otherLastReadMessageId': 0,
      'blocked': false,
    };
  }

  Future<List<Object>> _chats() async {
    final docs = await _db
        .collection('demo_chats')
        .where('members', arrayContains: _uid)
        .limit(50)
        .get();
    final cards = <Map<String, dynamic>>[];
    for (final room in docs.docs) {
      cards.add(await _roomJson(room));
    }
    return cards;
  }

  Future<Map<String, dynamic>> _openChat(Map<String, dynamic> data) async {
    await requireVerified();
    final otherUid = await _userUid((data['userId'] as num).toInt());
    if (otherUid == _uid) {
      throw ApiError('INVALID_CHAT', '자신과는 채팅할 수 없어요');
    }
    final members = [_uid, otherUid]..sort();
    final ref = _db.collection('demo_chats').doc(members.join('_'));
    await _db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (!existing.exists) {
        tx.set(ref,
            {'members': members, 'createdAt': FieldValue.serverTimestamp()});
      }
    });
    return _roomJson(await ref.get());
  }

  Future<Map<String, dynamic>> _chat(int id) async {
    final name = await chatDocumentId(id);
    return _roomJson(await _db.collection('demo_chats').doc(name).get());
  }

  Future<List<Object>> _messages(int id, Map<String, dynamic>? query) async {
    final name = await chatDocumentId(id);
    final snap = await _db
        .collection('demo_chats')
        .doc(name)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .get();
    final before = int.tryParse('${query?['before'] ?? ''}');
    final after = int.tryParse('${query?['after'] ?? ''}');
    return [
      for (final m in snap.docs)
        if ((before == null || displayId(m.id) < before) &&
            (after == null || displayId(m.id) > after))
          _messageJson(name, m.id, m.data()),
    ];
  }

  Future<Map<String, dynamic>> _sendMessage(
      int id, Map<String, dynamic> data) async {
    await requireVerified();
    final name = await chatDocumentId(id);
    final text = data['body']?.toString().trim() ?? '';
    if (text.isEmpty || text.length > 500) {
      throw ApiError('INVALID_BODY', '채팅 메시지는 1~500자로 작성해 주세요');
    }
    final clientId = data['clientMessageId']?.toString() ??
        'm_${DateTime.now().microsecondsSinceEpoch}';
    final ref = _db
        .collection('demo_chats')
        .doc(name)
        .collection('messages')
        .doc(clientId);
    final existing = await ref.get();
    if (!existing.exists) {
      await ref.set({
        'authorUid': _uid,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
      });
    }
    final saved = await ref.get();
    return _messageJson(name, ref.id, saved.data()!);
  }

  /// The collaborator ChatRoomScreen remains unchanged. Subscribe to real
  /// Firestore snapshot events and expose them as its existing ChatEvent stream.
  Stream<ChatMessage> watchChat(int id) async* {
    final name = await chatDocumentId(id);
    final stream = _db
        .collection('demo_chats')
        .doc(name)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots();
    await for (final snapshot in stream) {
      for (final changed in snapshot.docChanges) {
        if (changed.type == DocumentChangeType.added ||
            changed.type == DocumentChangeType.modified) {
          yield ChatMessage.fromJson(
              _messageJson(name, changed.doc.id, changed.doc.data()!));
        }
      }
    }
  }

  Stream<void> watchRooms() async* {
    if (_auth.currentUser == null) return;
    await for (final _ in _db
        .collection('demo_chats')
        .where('members', arrayContains: _uid)
        .snapshots()) {
      yield null;
    }
  }
}
