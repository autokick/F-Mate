import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';

/// 서버 API 묶음. 화면은 이 클래스들만 통해 서버와 통신한다.

// ============================================================ 구장
class VenueRepo {
  VenueRepo(this.api);

  final ApiClient api;

  Future<({List<VenueCard> items, bool hasNext})> search({
    String? q,
    List<String>? regions,
    double? lat,
    double? lng,
    double? radiusKm,
    bool? indoor,
    String? size,
    List<String>? facilities,
    DateTime? date,
    int? fromHour,
    int? toHour,
    int page = 0,
    int pageSize = 20,
  }) async {
    final res = asMap(await api.get('/api/v1/venues', query: {
      'q': q,
      'regions': (regions == null || regions.isEmpty) ? null : regions,
      'lat': lat,
      'lng': lng,
      'radiusKm': radiusKm,
      'indoor': indoor,
      'size': size,
      'facilities': (facilities == null || facilities.isEmpty) ? null : facilities,
      'date': date == null ? null : Fmt.isoDate(date),
      'fromHour': fromHour,
      'toHour': toHour,
      'page': page,
      'pageSize': pageSize,
    }));
    return (items: asList(res['items']).map(VenueCard.fromJson).toList(), hasNext: asBool(res['hasNext']));
  }

  Future<VenueDetail> detail(int id) async => VenueDetail.fromJson(await api.get('/api/v1/venues/$id'));

  Future<List<CourtAvailability>> availability(int id, DateTime date) async =>
      asList(await api.get('/api/v1/venues/$id/availability', query: {'date': Fmt.isoDate(date)}))
          .map(CourtAvailability.fromJson)
          .toList();

  Future<List<Facility>> facilities() async =>
      asList(await api.get('/api/v1/facilities')).map(Facility.fromJson).toList();

  /// 실제 풋살장 (카카오 실시간 검색). 위치(lat,lng) 또는 지역(area) 중 하나는 있어야 한다.
  Future<({List<NearbyPlace> items, bool hasNext, String attribution})> nearbyReal({
    double? lat,
    double? lng,
    String? area,
    int radiusM = 10000,
    int page = 1,
  }) async {
    final res = asMap(await api.get('/api/v1/places/futsal-nearby', query: {
      'lat': lat,
      'lng': lng,
      'area': (area == null || area.trim().isEmpty) ? null : area.trim(),
      'radiusM': radiusM,
      'page': page,
    }));
    return (
      items: asList(res['items']).map(NearbyPlace.fromJson).toList(),
      hasNext: asBool(res['hasNext']),
      attribution: asStr(res['attribution'], '장소 정보 제공: 카카오'),
    );
  }
}

// ============================================================ 예약·결제
class ReservationRepo {
  ReservationRepo(this.api);

  final ApiClient api;

  Future<Reservation> create(int courtId, DateTime startsAt, DateTime endsAt, String idempotencyKey) async =>
      Reservation.fromJson(await api.post('/api/v1/reservations',
          idempotencyKey: idempotencyKey,
          body: {
            'courtId': courtId,
            'startsAt': startsAt.toUtc().toIso8601String(),
            'endsAt': endsAt.toUtc().toIso8601String(),
          }));

  Future<List<ReservationListItem>> list({String? status, int page = 0}) async =>
      asList(await api.get('/api/v1/reservations', query: {'status': status, 'page': page, 'limit': 20}))
          .map(ReservationListItem.fromJson)
          .toList();

  Future<Reservation> detail(String publicId) async =>
      Reservation.fromJson(await api.get('/api/v1/reservations/$publicId'));

  Future<Reservation> cancel(String publicId, String? reason, String idempotencyKey) async =>
      Reservation.fromJson(await api.post('/api/v1/reservations/$publicId/cancel',
          idempotencyKey: idempotencyKey, body: {'reason': reason}));

  Future<PaymentOrder> createOrder(String reservationId, String idempotencyKey) async =>
      PaymentOrder.fromJson(await api.post('/api/v1/payments/orders',
          idempotencyKey: idempotencyKey, body: {'reservationId': reservationId}));

  Future<PaymentStatus> paymentStatus(String orderId) async =>
      PaymentStatus.fromJson(await api.get('/api/v1/payments/$orderId'));

  Future<void> reconcile(String orderId) async {
    await api.post('/api/v1/payments/$orderId/reconcile');
  }
}

// ============================================================ 미디어 업로드
class MediaRepo {
  MediaRepo(this.api);

  final ApiClient api;

  static String contentTypeOf(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.heic') || p.endsWith('.heif')) return 'image/heic';
    if (p.endsWith('.pdf')) return 'application/pdf';
    if (p.endsWith('.mov')) return 'video/quicktime';
    if (p.endsWith('.mp4') || p.endsWith('.m4v')) return 'video/mp4';
    return 'image/jpeg';
  }

  /// 이미지·서류를 스토리지에 직접 올리고 objectKey 목록을 돌려준다.
  /// purpose: POST_IMAGE | AVATAR | VENUE_PHOTO | VENUE_DOCUMENT
  Future<List<String>> uploadFiles(String purpose, List<XFile> files,
      {void Function(double progress)? onProgress}) async {
    final specs = <Map<String, dynamic>>[];
    for (final f in files) {
      specs.add({'contentType': contentTypeOf(f.path), 'sizeBytes': await f.length()});
    }
    final targets = asList(await api.post('/api/v1/media/upload-urls', body: {'purpose': purpose, 'files': specs}));
    final total = specs.fold<int>(0, (a, s) => a + (s['sizeBytes'] as int));
    var done = 0;
    final keys = <String>[];
    for (var i = 0; i < files.length; i++) {
      final t = asMap(targets[i]);
      final headers = <String, String>{};
      asMap(t['headers']).forEach((k, v) => headers[k] = '$v');
      final size = specs[i]['sizeBytes'] as int;
      final base = done;
      await api.uploadToUrl(asStr(t['uploadUrl']), files[i].openRead(), size, headers,
          onProgress: (sent, _) => onProgress?.call(total == 0 ? 1 : (base + sent) / total));
      done += size;
      keys.add(asStr(t['objectKey']));
    }
    onProgress?.call(1);
    return keys;
  }

  /// 영상: 업로드 티켓 발급 → 스토리지 직접 PUT → 완료 통지. videoId 반환.
  Future<int> uploadVideo(XFile file, {void Function(double progress)? onProgress, CancelToken? cancelToken}) async {
    final size = await file.length();
    final ticket = asMap(await api.post('/api/v1/videos/uploads',
        body: {'contentType': contentTypeOf(file.path), 'sizeBytes': size}));
    final videoId = asInt(ticket['videoId']);
    final headers = <String, String>{};
    asMap(ticket['headers']).forEach((k, v) => headers[k] = '$v');
    try {
      await api.uploadToUrl(asStr(ticket['uploadUrl']), file.openRead(), size, headers,
          onProgress: (sent, total) => onProgress?.call(total <= 0 ? 0 : sent / size), cancelToken: cancelToken);
    } catch (e) {
      try {
        await api.post('/api/v1/videos/$videoId/abort');
      } catch (_) {
        // 정리 실패는 서버 배치가 처리
      }
      rethrow;
    }
    await api.post('/api/v1/videos/$videoId/complete');
    return videoId;
  }

  Future<PostVideo> videoStatus(int videoId) async {
    final m = asMap(await api.get('/api/v1/videos/$videoId'));
    return PostVideo(
        id: asInt(m['id']),
        status: asStr(m['status']),
        hlsUrl: asStrOrNull(m['hlsUrl']),
        thumbnailUrl: asStrOrNull(m['thumbnailUrl']),
        durationMs: asIntOrNull(m['durationMs']));
  }

  Future<String?> videoFailureReason(int videoId) async =>
      asStrOrNull(asMap(await api.get('/api/v1/videos/$videoId'))['failureReason']);
}

// ============================================================ SNS
class SocialRepo {
  SocialRepo(this.api);

  final ApiClient api;

  Future<CursorPage<Post>> feed(String type, int? cursor) async =>
      postPage(await api.get('/api/v1/feed', query: {'type': type, 'cursor': cursor, 'limit': 20}));

  Future<CursorPage<Post>> shorts(int? cursor) async =>
      postPage(await api.get('/api/v1/shorts', query: {'cursor': cursor, 'limit': 10}));

  /// 이 구장을 태그한 공개 게시물 (구장 상세의 "이 구장에서 올라온 영상")
  Future<CursorPage<Post>> venuePosts(int venueId, {int? cursor, int limit = 12}) async =>
      postPage(await api.get('/api/v1/feed', query: {'type': 'venue', 'venueId': venueId, 'cursor': cursor, 'limit': limit}));

  Future<CursorPage<Post>> userPosts(int userId, {bool highlights = false, int? cursor}) async =>
      postPage(await api.get('/api/v1/users/$userId/posts',
          query: {'tab': highlights ? 'highlights' : 'posts', 'cursor': cursor, 'limit': 24}));

  Future<CursorPage<Post>> saved(int? cursor) async =>
      postPage(await api.get('/api/v1/me/saved', query: {'cursor': cursor, 'limit': 24}));

  Future<CursorPage<Post>> hashtag(String tag, int? cursor) async =>
      postPage(await api.get('/api/v1/hashtags/${Uri.encodeComponent(tag)}/posts', query: {'cursor': cursor}));

  Future<Post> post(int id) async => Post.fromJson(await api.get('/api/v1/posts/$id'));

  Future<Post> create(Map<String, dynamic> body, String idempotencyKey) async =>
      Post.fromJson(await api.post('/api/v1/posts', body: body, idempotencyKey: idempotencyKey));

  Future<Post> update(int id, Map<String, dynamic> body) async =>
      Post.fromJson(await api.patch('/api/v1/posts/$id', body: body));

  Future<void> delete(int id) async => api.delete('/api/v1/posts/$id');

  Future<void> like(int id, bool on) async => on ? api.put('/api/v1/posts/$id/like') : api.delete('/api/v1/posts/$id/like');

  Future<void> save(int id, bool on) async => on ? api.put('/api/v1/posts/$id/save') : api.delete('/api/v1/posts/$id/save');

  Future<List<Comment>> comments(int postId, {int? after}) async =>
      asList(await api.get('/api/v1/posts/$postId/comments', query: {'after': after, 'limit': 100}))
          .map(Comment.fromJson)
          .toList();

  Future<Comment> addComment(int postId, String body, {int? parentId}) async =>
      Comment.fromJson(await api.post('/api/v1/posts/$postId/comments', body: {'body': body, 'parentId': parentId}));

  Future<void> deleteComment(int id) async => api.delete('/api/v1/comments/$id');

  Future<ProfileView> profile(int userId) async => ProfileView.fromJson(await api.get('/api/v1/users/$userId'));

  Future<List<UserSummary>> searchUsers(String q) async =>
      asList(await api.get('/api/v1/users/search', query: {'q': q})).map(UserSummary.fromJson).toList();

  Future<String> follow(int userId) async => asStr(asMap(await api.put('/api/v1/users/$userId/follow'))['followStatus']);

  Future<void> unfollow(int userId) async => api.delete('/api/v1/users/$userId/follow');

  Future<List<UserSummary>> followers(int userId, {int page = 0}) async =>
      asList(await api.get('/api/v1/users/$userId/followers', query: {'page': page})).map(UserSummary.fromJson).toList();

  Future<List<UserSummary>> following(int userId, {int page = 0}) async =>
      asList(await api.get('/api/v1/users/$userId/following', query: {'page': page})).map(UserSummary.fromJson).toList();

  Future<List<UserSummary>> followRequests() async =>
      asList(await api.get('/api/v1/me/follow-requests')).map(UserSummary.fromJson).toList();

  Future<void> acceptRequest(int userId) async => api.post('/api/v1/me/follow-requests/$userId/accept');

  Future<void> rejectRequest(int userId) async => api.post('/api/v1/me/follow-requests/$userId/reject');

  Future<void> block(int userId) async => api.put('/api/v1/users/$userId/block');

  Future<void> unblock(int userId) async => api.delete('/api/v1/users/$userId/block');

  Future<List<UserSummary>> blocks() async => asList(await api.get('/api/v1/me/blocks')).map(UserSummary.fromJson).toList();

  Future<void> report(String targetType, int targetId, String reason, String? detail) async =>
      api.post('/api/v1/reports', body: {'targetType': targetType, 'targetId': targetId, 'reason': reason, 'detail': detail});
}

// ============================================================ 채팅·알림
class ChatRepo {
  ChatRepo(this.api);

  final ApiClient api;

  Future<List<ChatSummary>> list() async => asList(await api.get('/api/v1/chats')).map(ChatSummary.fromJson).toList();

  Future<ChatSummary> open(int userId) async => ChatSummary.fromJson(await api.post('/api/v1/chats', body: {'userId': userId}));

  Future<ChatSummary> get(int chatId) async => ChatSummary.fromJson(await api.get('/api/v1/chats/$chatId'));

  Future<List<ChatMessage>> messages(int chatId, {int? before, int? after}) async =>
      asList(await api.get('/api/v1/chats/$chatId/messages', query: {'before': before, 'after': after, 'limit': 50}))
          .map(ChatMessage.fromJson)
          .toList();

  Future<ChatMessage> send(int chatId, String clientMessageId, String body) async =>
      ChatMessage.fromJson(await api.post('/api/v1/chats/$chatId/messages',
          body: {'clientMessageId': clientMessageId, 'body': body}));

  Future<void> read(int chatId, int messageId) async => api.post('/api/v1/chats/$chatId/read', body: {'messageId': messageId});

  Future<void> hide(int chatId) async => api.post('/api/v1/chats/$chatId/hide');
}

class NotificationRepo {
  NotificationRepo(this.api);

  final ApiClient api;

  Future<List<AppNotification>> list({int? before}) async =>
      asList(await api.get('/api/v1/notifications', query: {'before': before, 'limit': 30}))
          .map(AppNotification.fromJson)
          .toList();

  Future<int> unreadCount() async => asInt(asMap(await api.get('/api/v1/notifications/unread-count'))['count']);

  Future<void> markAllRead() async => api.post('/api/v1/notifications/read', body: {'ids': <int>[]});

  Future<void> registerDevice(String token, String platform) async =>
      api.post('/api/v1/me/devices', body: {'fcmToken': token, 'platform': platform});

  /// 로그아웃 시 이 기기로 푸시가 가지 않도록 토큰 해제
  Future<void> removeDevice(String token) async => api.post('/api/v1/me/devices/remove', body: {'fcmToken': token});
}

// ============================================================ 내 계정
class AccountRepo {
  AccountRepo(this.api);

  final ApiClient api;

  Future<Me> updateProfile(Map<String, dynamic> body) async => Me.fromJson(await api.patch('/api/v1/me/profile', body: body));

  Future<Me> setAvatar(String? objectKey) async => Me.fromJson(await api.put('/api/v1/me/avatar', body: {'objectKey': objectKey}));

  Future<Me> saveConsents(Map<String, bool> consents) async => Me.fromJson(await api.post('/api/v1/me/consents', body: {
        'consents': consents.entries.map((e) => {'type': e.key, 'agreed': e.value}).toList(),
        'version': '2026-10',
      }));

  Future<Map<String, bool>> notificationSettings() async {
    final m = asMap(await api.get('/api/v1/me/notification-settings'));
    return {for (final k in ['reservation', 'social', 'chat', 'marketing']) k: asBool(m[k])};
  }

  Future<void> saveNotificationSettings(Map<String, bool> s) async => api.put('/api/v1/me/notification-settings', body: s);

  Future<void> verifyEmail(String code) async => api.post('/api/v1/auth/email/verify', body: {'code': code});

  Future<void> resendVerification() async => api.post('/api/v1/auth/email/resend');

  Future<void> requestPasswordReset(String email) async =>
      api.post('/api/v1/auth/password/reset-request', body: {'email': email.trim()});

  Future<void> resetPassword(String email, String code, String newPassword) async =>
      api.post('/api/v1/auth/password/reset', body: {'email': email.trim(), 'code': code, 'newPassword': newPassword});

  Future<void> changePassword(String current, String next) async =>
      api.put('/api/v1/auth/password', body: {'currentPassword': current, 'newPassword': next});

  Future<void> deleteAccount(String? password) async =>
      api.post('/api/v1/me/delete', body: {'password': password, 'confirm': '탈퇴'});
}

// ============================================================ 구장 운영자
class OperatorRepo {
  OperatorRepo(this.api);

  final ApiClient api;

  Future<List<Map<String, dynamic>>> myVenues() async =>
      asList(await api.get('/api/v1/operator/venues')).map(asMap).toList();

  Future<int> apply(Map<String, dynamic> body) async =>
      asInt(asMap(await api.post('/api/v1/operator/venue-applications', body: body))['venueId']);

  Future<VenueDetail> venue(int id) async => VenueDetail.fromJson(await api.get('/api/v1/operator/venues/$id'));

  Future<VenueDetail> updateVenue(int id, Map<String, dynamic> body) async =>
      VenueDetail.fromJson(await api.patch('/api/v1/operator/venues/$id', body: body));

  Future<int> addCourt(int venueId, Map<String, dynamic> body) async =>
      asInt(asMap(await api.post('/api/v1/operator/venues/$venueId/courts', body: body))['courtId']);

  Future<void> updateCourt(int courtId, Map<String, dynamic> body) async =>
      api.patch('/api/v1/operator/courts/$courtId', body: body);

  Future<List<Map<String, dynamic>>> hours(int courtId) async =>
      asList(await api.get('/api/v1/operator/courts/$courtId/operating-hours')).map(asMap).toList();

  Future<int> replaceHours(int courtId, List<Map<String, dynamic>> hours) async =>
      asInt(asMap(await api.put('/api/v1/operator/courts/$courtId/operating-hours', body: hours))['generatedSlots']);

  Future<List<Map<String, dynamic>>> slots(int courtId, DateTime date) async =>
      asList(await api.get('/api/v1/operator/courts/$courtId/slots', query: {'date': Fmt.isoDate(date)})).map(asMap).toList();

  Future<void> updateSlot(int slotId, {String? status, int? price}) async =>
      api.patch('/api/v1/operator/slots/$slotId', body: {'status': status, 'price': price});

  Future<List<Map<String, dynamic>>> closures(int venueId) async =>
      asList(await api.get('/api/v1/operator/venues/$venueId/closures')).map(asMap).toList();

  Future<void> addClosure(int venueId, {int? courtId, required DateTime startsAt, required DateTime endsAt, String? reason}) async =>
      api.post('/api/v1/operator/venues/$venueId/closures', body: {
        'courtId': courtId,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
        'reason': reason,
      });

  Future<void> deleteClosure(int venueId, int closureId) async =>
      api.delete('/api/v1/operator/venues/$venueId/closures/$closureId');

  Future<List<Map<String, dynamic>>> reservations(int venueId, DateTime date) async =>
      asList(await api.get('/api/v1/operator/venues/$venueId/reservations', query: {'date': Fmt.isoDate(date)}))
          .map(asMap)
          .toList();

  Future<void> cancelReservation(String publicId, String reason, String idempotencyKey) async =>
      api.post('/api/v1/operator/reservations/$publicId/cancel', idempotencyKey: idempotencyKey, body: {'reason': reason});
}

// ============================================================ 관리자
class AdminRepo {
  AdminRepo(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> dashboard() async => asMap(await api.get('/api/v1/admin/dashboard'));

  Future<List<Map<String, dynamic>>> list(String path, {Map<String, dynamic>? query}) async =>
      asList(await api.get('/api/v1/admin/$path', query: query)).map(asMap).toList();

  Future<Map<String, dynamic>> one(String path) async => asMap(await api.get('/api/v1/admin/$path'));

  Future<dynamic> action(String path, Map<String, dynamic>? body) => api.post('/api/v1/admin/$path', body: body);
}
