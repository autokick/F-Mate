import 'format.dart';

// ============================================================ 공통

class UserSummary {
  UserSummary({required this.id, required this.nickname, this.avatarUrl});

  final int id;
  final String nickname;
  final String? avatarUrl;

  factory UserSummary.fromJson(dynamic j) {
    final m = asMap(j);
    return UserSummary(id: asInt(m['id']), nickname: asStr(m['nickname'], '(알 수 없음)'), avatarUrl: asStrOrNull(m['avatarUrl']));
  }
}

class FeatureConfig {
  FeatureConfig({
    required this.paymentEnabled,
    required this.paymentMode,
    required this.media,
    required this.video,
    required this.push,
    required this.maps,
    required this.email,
    required this.devMode,
    required this.socialProviders,
    this.places = false,
  });

  final bool paymentEnabled;
  final String paymentMode;
  final bool media;
  final bool video;
  final bool push;
  final bool maps;
  final bool email;
  final bool devMode;
  final List<String> socialProviders;
  /// 내 주변 실제 풋살장 검색 (카카오) 사용 가능
  final bool places;

  bool get isTestPayment => paymentMode != 'LIVE';

  factory FeatureConfig.fromJson(dynamic j) {
    final m = asMap(j);
    final f = asMap(m['features']);
    final p = asMap(f['payment']);
    return FeatureConfig(
      paymentEnabled: asBool(p['enabled']),
      paymentMode: asStr(p['mode'], 'TEST'),
      media: asBool(f['media']),
      video: asBool(f['video']),
      push: asBool(f['push']),
      maps: asBool(f['maps']),
      email: asBool(f['email']),
      devMode: asBool(m['devMode']),
      socialProviders: asList(f['socialProviders']).map((e) => '$e').toList(),
      places: asBool(f['places']),
    );
  }

  static FeatureConfig offline() => FeatureConfig(
      paymentEnabled: false,
      paymentMode: 'TEST',
      media: false,
      video: false,
      push: false,
      maps: false,
      email: false,
      devMode: false,
      socialProviders: const []);
}

// ============================================================ 실제 풋살장 (카카오 검색, 저장하지 않음)

class NearbyPlace {
  NearbyPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.phone,
    this.roadAddress,
    this.address,
    this.distanceM,
    this.placeUrl,
  });

  final String id;
  final String name;
  final String category;
  final String? phone;
  final String? roadAddress;
  final String? address;
  final double lat;
  final double lng;
  final int? distanceM;
  final String? placeUrl;

  String get displayAddress => roadAddress ?? address ?? '';

  String? get distanceLabel {
    final d = distanceM;
    if (d == null) return null;
    return d < 1000 ? '${d}m' : '${(d / 1000).toStringAsFixed(1)}km';
  }

  factory NearbyPlace.fromJson(dynamic j) {
    final m = asMap(j);
    final dist = m['distanceM'];
    return NearbyPlace(
      id: asStr(m['id']),
      name: asStr(m['name']),
      category: asStr(m['category']),
      phone: m['phone'] == null ? null : asStr(m['phone']),
      roadAddress: m['roadAddress'] == null ? null : asStr(m['roadAddress']),
      address: m['address'] == null ? null : asStr(m['address']),
      lat: asDoubleOrNull(m['lat']) ?? 0,
      lng: asDoubleOrNull(m['lng']) ?? 0,
      distanceM: dist == null ? null : asInt(dist),
      placeUrl: m['placeUrl'] == null ? null : asStr(m['placeUrl']),
    );
  }
}

// ============================================================ 내 정보

class Counts {
  Counts(this.posts, this.followers, this.following);

  final int posts;
  final int followers;
  final int following;

  factory Counts.fromJson(dynamic j) {
    final m = asMap(j);
    return Counts(asInt(m['posts']), asInt(m['followers']), asInt(m['following']));
  }
}

class Me {
  Me({
    required this.id,
    this.email,
    required this.emailVerified,
    required this.role,
    required this.nickname,
    this.bio,
    this.avatarUrl,
    this.regionCode,
    this.preferredPosition,
    required this.isPrivate,
    required this.counts,
    required this.hasPassword,
    required this.socialProviders,
    required this.consents,
    required this.operatorVenueIds,
    required this.needsProfile,
  });

  final int id;
  final String? email;
  final bool emailVerified;
  final String role;
  final String nickname;
  final String? bio;
  final String? avatarUrl;
  final String? regionCode;
  final String? preferredPosition;
  final bool isPrivate;
  final Counts counts;
  final bool hasPassword;
  final List<String> socialProviders;
  final Map<String, bool> consents;
  final List<int> operatorVenueIds;
  final bool needsProfile;

  bool get isAdmin => role == 'ADMIN';
  bool get isModerator => role == 'ADMIN' || role == 'MODERATOR';
  bool get isOperator => operatorVenueIds.isNotEmpty;

  factory Me.fromJson(dynamic j) {
    final m = asMap(j);
    final consents = <String, bool>{};
    asMap(m['consents']).forEach((k, v) => consents[k] = v == true);
    return Me(
      id: asInt(m['id']),
      email: asStrOrNull(m['email']),
      emailVerified: asBool(m['emailVerified']),
      role: asStr(m['role'], 'USER'),
      nickname: asStr(m['nickname']),
      bio: asStrOrNull(m['bio']),
      avatarUrl: asStrOrNull(m['avatarUrl']),
      regionCode: asStrOrNull(m['regionCode']),
      preferredPosition: asStrOrNull(m['preferredPosition']),
      isPrivate: asBool(m['isPrivate']),
      counts: Counts.fromJson(m['counts']),
      hasPassword: asBool(m['hasPassword']),
      socialProviders: asList(m['socialProviders']).map((e) => '$e').toList(),
      consents: consents,
      operatorVenueIds: asList(m['operatorVenueIds']).map((e) => asInt(e)).toList(),
      needsProfile: asBool(m['needsProfile']),
    );
  }
}

class ProfileView {
  ProfileView({
    required this.id,
    required this.nickname,
    this.bio,
    this.avatarUrl,
    this.regionCode,
    this.preferredPosition,
    required this.isPrivate,
    required this.counts,
    required this.followStatus,
    required this.followsMe,
    required this.blockedByMe,
    required this.canViewPosts,
  });

  final int id;
  final String nickname;
  final String? bio;
  final String? avatarUrl;
  final String? regionCode;
  final String? preferredPosition;
  final bool isPrivate;
  final Counts counts;
  final String followStatus; // NONE | PENDING | FOLLOWING
  final bool followsMe;
  final bool blockedByMe;
  final bool canViewPosts;

  factory ProfileView.fromJson(dynamic j) {
    final m = asMap(j);
    return ProfileView(
      id: asInt(m['id']),
      nickname: asStr(m['nickname']),
      bio: asStrOrNull(m['bio']),
      avatarUrl: asStrOrNull(m['avatarUrl']),
      regionCode: asStrOrNull(m['regionCode']),
      preferredPosition: asStrOrNull(m['preferredPosition']),
      isPrivate: asBool(m['isPrivate']),
      counts: Counts.fromJson(m['counts']),
      followStatus: asStr(m['followStatus'], 'NONE'),
      followsMe: asBool(m['followsMe']),
      blockedByMe: asBool(m['blockedByMe']),
      canViewPosts: asBool(m['canViewPosts']),
    );
  }
}

// ============================================================ 구장

class VenueCard {
  VenueCard({
    required this.id,
    required this.name,
    required this.roadAddress,
    required this.latitude,
    required this.longitude,
    this.thumbnailUrl,
    this.minPrice,
    required this.hasIndoor,
    required this.hasOutdoor,
    required this.sizes,
    required this.facilities,
    this.distanceKm,
    this.availableSlots,
    this.dataSource,
  });

  final int id;
  final String name;
  final String roadAddress;
  final double latitude;
  final double longitude;
  final String? thumbnailUrl;
  final int? minPrice;
  final bool hasIndoor;
  final bool hasOutdoor;
  final List<String> sizes;
  final List<String> facilities;
  final double? distanceKm;
  final int? availableSlots;
  /// OPERATOR(입점 구장) / PARTNER_API(공공데이터 등 외부 자료로 가져온 구장)
  final String? dataSource;

  /// 공공데이터로 가져온 구장: 실제 시설이지만 제휴 전이라 시간표·가격·시설은 시연용
  bool get isPublicData => dataSource == 'PARTNER_API';

  factory VenueCard.fromJson(dynamic j) {
    final m = asMap(j);
    return VenueCard(
      id: asInt(m['id']),
      name: asStr(m['name']),
      roadAddress: asStr(m['roadAddress']),
      latitude: asDoubleOrNull(m['latitude']) ?? 0,
      longitude: asDoubleOrNull(m['longitude']) ?? 0,
      thumbnailUrl: asStrOrNull(m['thumbnailUrl']),
      minPrice: asIntOrNull(m['minPrice']),
      hasIndoor: asBool(m['hasIndoor']),
      hasOutdoor: asBool(m['hasOutdoor']),
      sizes: asList(m['sizes']).map((e) => '$e').toList(),
      facilities: asList(m['facilities']).map((e) => '$e').toList(),
      distanceKm: asDoubleOrNull(m['distanceKm']),
      availableSlots: asIntOrNull(m['availableSlots']),
      dataSource: asStrOrNull(m['dataSource']),
    );
  }
}

class Court {
  Court({
    required this.id,
    required this.name,
    required this.isIndoor,
    required this.surface,
    required this.sizeClass,
    this.widthM,
    this.lengthM,
    required this.isActive,
  });

  final int id;
  final String name;
  final bool isIndoor;
  final String surface;
  final String sizeClass;
  final double? widthM;
  final double? lengthM;
  final bool isActive;

  factory Court.fromJson(dynamic j) {
    final m = asMap(j);
    return Court(
      id: asInt(m['id']),
      name: asStr(m['name']),
      isIndoor: asBool(m['isIndoor']),
      surface: asStr(m['surface']),
      sizeClass: asStr(m['sizeClass']),
      widthM: asDoubleOrNull(m['widthM']),
      lengthM: asDoubleOrNull(m['lengthM']),
      isActive: m['isActive'] != false,
    );
  }
}

class Facility {
  Facility(this.code, this.label, this.note);

  final String code;
  final String label;
  final String? note;

  factory Facility.fromJson(dynamic j) {
    final m = asMap(j);
    return Facility(asStr(m['code']), asStr(m['label']), asStrOrNull(m['note']));
  }
}

class PolicyRule {
  PolicyRule(this.hoursBefore, this.refundPercent);

  final int hoursBefore;
  final int refundPercent;
}

class Photo {
  Photo(this.id, this.url, this.objectKey);

  final int id;
  final String? url;
  final String? objectKey;

  factory Photo.fromJson(dynamic j) {
    final m = asMap(j);
    return Photo(asInt(m['id']), asStrOrNull(m['url']), asStrOrNull(m['objectKey']));
  }
}

class VenueDetail {
  VenueDetail({
    required this.id,
    required this.name,
    this.description,
    required this.roadAddress,
    this.detailAddress,
    required this.regionCode,
    required this.latitude,
    required this.longitude,
    this.phone,
    this.rules,
    required this.cancelPolicy,
    required this.verificationStatus,
    this.rejectionReason,
    required this.photos,
    required this.courts,
    required this.facilities,
    this.dataSource,
  });

  final int id;
  final String name;
  final String? description;
  final String roadAddress;
  final String? detailAddress;
  final String regionCode;
  final double latitude;
  final double longitude;
  final String? phone;
  final String? rules;
  final List<PolicyRule> cancelPolicy;
  final String verificationStatus;
  final String? rejectionReason;
  final List<Photo> photos;
  final List<Court> courts;
  final List<Facility> facilities;
  final String? dataSource;

  bool get isPublicData => dataSource == 'PARTNER_API';

  factory VenueDetail.fromJson(dynamic j) {
    final m = asMap(j);
    return VenueDetail(
      id: asInt(m['id']),
      name: asStr(m['name']),
      description: asStrOrNull(m['description']),
      roadAddress: asStr(m['roadAddress']),
      detailAddress: asStrOrNull(m['detailAddress']),
      regionCode: asStr(m['regionCode']),
      latitude: asDoubleOrNull(m['latitude']) ?? 0,
      longitude: asDoubleOrNull(m['longitude']) ?? 0,
      phone: asStrOrNull(m['phone']),
      rules: asStrOrNull(m['rules']),
      cancelPolicy: parsePolicy(m['cancelPolicy']),
      verificationStatus: asStr(m['verificationStatus']),
      rejectionReason: asStrOrNull(m['rejectionReason']),
      photos: asList(m['photos']).map(Photo.fromJson).toList(),
      courts: asList(m['courts']).map(Court.fromJson).toList(),
      facilities: asList(m['facilities']).map(Facility.fromJson).toList(),
      dataSource: asStrOrNull(m['dataSource']),
    );
  }
}

List<PolicyRule> parsePolicy(dynamic v) {
  final rules = asList(v)
      .map((r) => PolicyRule(asInt(asMap(r)['hoursBefore']), asInt(asMap(r)['refundPercent'])))
      .toList();
  rules.sort((a, b) => b.hoursBefore.compareTo(a.hoursBefore));
  return rules;
}

class Slot {
  Slot({required this.id, required this.startsAt, required this.endsAt, required this.price, required this.available});

  final int id;
  final DateTime startsAt;
  final DateTime endsAt;
  final int price;
  final bool available;

  factory Slot.fromJson(dynamic j) {
    final m = asMap(j);
    return Slot(
      id: asInt(m['slotId']),
      startsAt: asTime(m['startsAt']) ?? DateTime.now(),
      endsAt: asTime(m['endsAt']) ?? DateTime.now(),
      price: asInt(m['price']),
      available: asBool(m['available']),
    );
  }
}

class CourtAvailability {
  CourtAvailability({required this.courtId, required this.courtName, required this.isIndoor, required this.sizeClass, required this.slots});

  final int courtId;
  final String courtName;
  final bool isIndoor;
  final String sizeClass;
  final List<Slot> slots;

  factory CourtAvailability.fromJson(dynamic j) {
    final m = asMap(j);
    return CourtAvailability(
      courtId: asInt(m['courtId']),
      courtName: asStr(m['courtName']),
      isIndoor: asBool(m['isIndoor']),
      sizeClass: asStr(m['sizeClass']),
      slots: asList(m['slots']).map(Slot.fromJson).toList(),
    );
  }
}

// ============================================================ 예약·결제

class PaymentInfo {
  PaymentInfo({
    required this.orderId,
    required this.status,
    required this.mode,
    this.method,
    required this.amount,
    this.approvedAmount,
    this.balanceAmount,
    this.receiptUrl,
    this.failureCode,
    this.failureMessage,
  });

  final String orderId;
  final String status;
  final String mode;
  final String? method;
  final int amount;
  final int? approvedAmount;
  final int? balanceAmount;
  final String? receiptUrl;
  final String? failureCode;
  final String? failureMessage;

  factory PaymentInfo.fromJson(dynamic j) {
    final m = asMap(j);
    return PaymentInfo(
      orderId: asStr(m['orderId']),
      status: asStr(m['status']),
      mode: asStr(m['mode'], 'TEST'),
      method: asStrOrNull(m['method']),
      amount: asInt(m['amount']),
      approvedAmount: asIntOrNull(m['approvedAmount']),
      balanceAmount: asIntOrNull(m['balanceAmount']),
      receiptUrl: asStrOrNull(m['receiptUrl']),
      failureCode: asStrOrNull(m['failureCode']),
      failureMessage: asStrOrNull(m['failureMessage']),
    );
  }
}

class RefundInfo {
  RefundInfo({required this.amount, required this.status, this.reason, this.createdAt, this.completedAt});

  final int amount;
  final String status;
  final String? reason;
  final DateTime? createdAt;
  final DateTime? completedAt;

  factory RefundInfo.fromJson(dynamic j) {
    final m = asMap(j);
    return RefundInfo(
      amount: asInt(m['amount']),
      status: asStr(m['status']),
      reason: asStrOrNull(m['reason']),
      createdAt: asTime(m['createdAt']),
      completedAt: asTime(m['completedAt']),
    );
  }
}

class HistoryItem {
  HistoryItem(this.fromStatus, this.toStatus, this.at);

  final String? fromStatus;
  final String toStatus;
  final DateTime? at;

  factory HistoryItem.fromJson(dynamic j) {
    final m = asMap(j);
    return HistoryItem(asStrOrNull(m['fromStatus']), asStr(m['toStatus']), asTime(m['at']));
  }
}

class Reservation {
  Reservation({
    required this.publicId,
    required this.venueId,
    required this.venueName,
    required this.venueAddress,
    this.venuePhone,
    required this.courtName,
    required this.courtIndoor,
    required this.courtSize,
    required this.startsAt,
    required this.endsAt,
    required this.totalAmount,
    required this.status,
    this.holdExpiresAt,
    this.canceledAt,
    this.canceledBy,
    this.cancelReason,
    required this.cancelPolicy,
    this.refundIfCanceledNow,
    this.payment,
    required this.refunds,
    required this.history,
  });

  final String publicId;
  final int venueId;
  final String venueName;
  final String venueAddress;
  final String? venuePhone;
  final String courtName;
  final bool courtIndoor;
  final String courtSize;
  final DateTime startsAt;
  final DateTime endsAt;
  final int totalAmount;
  final String status;
  final DateTime? holdExpiresAt;
  final DateTime? canceledAt;
  final String? canceledBy;
  final String? cancelReason;
  final List<PolicyRule> cancelPolicy;
  final int? refundIfCanceledNow;
  final PaymentInfo? payment;
  final List<RefundInfo> refunds;
  final List<HistoryItem> history;

  factory Reservation.fromJson(dynamic j) {
    final m = asMap(j);
    final v = asMap(m['venue']);
    final c = asMap(m['court']);
    return Reservation(
      publicId: asStr(m['publicId']),
      venueId: asInt(v['id']),
      venueName: asStr(v['name']),
      venueAddress: asStr(v['roadAddress']),
      venuePhone: asStrOrNull(v['phone']),
      courtName: asStr(c['name']),
      courtIndoor: asBool(c['isIndoor']),
      courtSize: asStr(c['sizeClass']),
      startsAt: asTime(m['startsAt']) ?? DateTime.now(),
      endsAt: asTime(m['endsAt']) ?? DateTime.now(),
      totalAmount: asInt(m['totalAmount']),
      status: asStr(m['status']),
      holdExpiresAt: asTime(m['holdExpiresAt']),
      canceledAt: asTime(m['canceledAt']),
      canceledBy: asStrOrNull(m['canceledBy']),
      cancelReason: asStrOrNull(m['cancelReason']),
      cancelPolicy: parsePolicy(m['cancelPolicy']),
      refundIfCanceledNow: asIntOrNull(m['refundIfCanceledNow']),
      payment: m['payment'] == null ? null : PaymentInfo.fromJson(m['payment']),
      refunds: asList(m['refunds']).map(RefundInfo.fromJson).toList(),
      history: asList(m['history']).map(HistoryItem.fromJson).toList(),
    );
  }
}

class ReservationListItem {
  ReservationListItem({
    required this.publicId,
    required this.venueName,
    required this.courtName,
    required this.startsAt,
    required this.endsAt,
    required this.totalAmount,
    required this.status,
    this.holdExpiresAt,
  });

  final String publicId;
  final String venueName;
  final String courtName;
  final DateTime startsAt;
  final DateTime endsAt;
  final int totalAmount;
  final String status;
  final DateTime? holdExpiresAt;

  factory ReservationListItem.fromJson(dynamic j) {
    final m = asMap(j);
    return ReservationListItem(
      publicId: asStr(m['publicId']),
      venueName: asStr(m['venueName']),
      courtName: asStr(m['courtName']),
      startsAt: asTime(m['startsAt']) ?? DateTime.now(),
      endsAt: asTime(m['endsAt']) ?? DateTime.now(),
      totalAmount: asInt(m['totalAmount']),
      status: asStr(m['status']),
      holdExpiresAt: asTime(m['holdExpiresAt']),
    );
  }
}

/// 예약 상태 → 화면 표시
String reservationStatusLabel(String s) => switch (s) {
      'PENDING_PAYMENT' => '결제 대기',
      'CONFIRMED' => '예약 확정',
      'CANCELED' => '취소됨',
      'REFUNDED' => '환불 완료',
      'EXPIRED' => '결제 시간 만료',
      'COMPLETED' => '이용 완료',
      'NO_SHOW' => '노쇼',
      _ => s,
    };

class PaymentOrder {
  PaymentOrder({required this.orderId, required this.amount, required this.orderName, required this.checkoutUrl, required this.successUrlPrefix, required this.failUrlPrefix, required this.mode, this.holdExpiresAt});

  final String orderId;
  final int amount;
  final String orderName;
  final String checkoutUrl;
  final String successUrlPrefix;
  final String failUrlPrefix;
  final String mode;
  final DateTime? holdExpiresAt;

  factory PaymentOrder.fromJson(dynamic j) {
    final m = asMap(j);
    return PaymentOrder(
      orderId: asStr(m['orderId']),
      amount: asInt(m['amount']),
      orderName: asStr(m['orderName']),
      checkoutUrl: asStr(m['checkoutUrl']),
      successUrlPrefix: asStr(m['successUrlPrefix']),
      failUrlPrefix: asStr(m['failUrlPrefix']),
      mode: asStr(m['mode'], 'TEST'),
      holdExpiresAt: asTime(m['holdExpiresAt']),
    );
  }
}

class PaymentStatus {
  PaymentStatus({required this.orderId, required this.status, required this.reservationPublicId, required this.reservationStatus, this.failureMessage, this.receiptUrl});

  final String orderId;
  final String status;
  final String reservationPublicId;
  final String reservationStatus;
  final String? failureMessage;
  final String? receiptUrl;

  bool get isConfirmed => reservationStatus == 'CONFIRMED';
  bool get isPending => status == 'IN_PROGRESS' || status == 'READY';
  bool get isFailed => status == 'ABORTED' || status == 'EXPIRED' || (status == 'CANCELED' && !isConfirmed);

  factory PaymentStatus.fromJson(dynamic j) {
    final m = asMap(j);
    return PaymentStatus(
      orderId: asStr(m['orderId']),
      status: asStr(m['status']),
      reservationPublicId: asStr(m['reservationPublicId']),
      reservationStatus: asStr(m['reservationStatus']),
      failureMessage: asStrOrNull(m['failureMessage']),
      receiptUrl: asStrOrNull(m['receiptUrl']),
    );
  }
}

// ============================================================ SNS

class PostImage {
  PostImage(this.url, this.width, this.height);

  final String? url;
  final int? width;
  final int? height;

  factory PostImage.fromJson(dynamic j) {
    final m = asMap(j);
    return PostImage(asStrOrNull(m['url']), asIntOrNull(m['width']), asIntOrNull(m['height']));
  }
}

class PostVideo {
  PostVideo({required this.id, required this.status, this.hlsUrl, this.thumbnailUrl, this.durationMs});

  final int id;
  final String status;
  final String? hlsUrl;
  final String? thumbnailUrl;
  final int? durationMs;

  bool get ready => status == 'READY' && hlsUrl != null;

  factory PostVideo.fromJson(dynamic j) {
    final m = asMap(j);
    return PostVideo(
      id: asInt(m['id']),
      status: asStr(m['status']),
      hlsUrl: asStrOrNull(m['hlsUrl']),
      thumbnailUrl: asStrOrNull(m['thumbnailUrl']),
      durationMs: asIntOrNull(m['durationMs']),
    );
  }
}

class Post {
  Post({
    required this.id,
    required this.author,
    required this.kind,
    this.caption,
    required this.visibility,
    required this.isHighlight,
    this.venueId,
    this.venueName,
    required this.status,
    required this.images,
    this.video,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
    required this.savedByMe,
    required this.createdAt,
  });

  final int id;
  final UserSummary author;
  final String kind;
  final String? caption;
  final String visibility;
  final bool isHighlight;
  final int? venueId;
  final String? venueName;
  final String status;
  final List<PostImage> images;
  final PostVideo? video;
  int likeCount;
  final int commentCount;
  bool likedByMe;
  bool savedByMe;
  final DateTime createdAt;

  factory Post.fromJson(dynamic j) {
    final m = asMap(j);
    final venue = m['venue'] == null ? null : asMap(m['venue']);
    return Post(
      id: asInt(m['id']),
      author: UserSummary.fromJson(m['author']),
      kind: asStr(m['kind']),
      caption: asStrOrNull(m['caption']),
      visibility: asStr(m['visibility'], 'PUBLIC'),
      isHighlight: asBool(m['isHighlight']),
      venueId: venue == null ? null : asInt(venue['id']),
      venueName: venue == null ? null : asStr(venue['name']),
      status: asStr(m['status']),
      images: asList(m['images']).map(PostImage.fromJson).toList(),
      video: m['video'] == null ? null : PostVideo.fromJson(m['video']),
      likeCount: asInt(m['likeCount']),
      commentCount: asInt(m['commentCount']),
      likedByMe: asBool(m['likedByMe']),
      savedByMe: asBool(m['savedByMe']),
      createdAt: asTime(m['createdAt']) ?? DateTime.now(),
    );
  }
}

class CursorPage<T> {
  CursorPage(this.items, this.nextCursor);

  final List<T> items;
  final int? nextCursor;
}

CursorPage<Post> postPage(dynamic j) {
  final m = asMap(j);
  return CursorPage(asList(m['items']).map(Post.fromJson).toList(), asIntOrNull(m['nextCursor']));
}

class Comment {
  Comment({required this.id, this.parentId, required this.author, required this.body, required this.createdAt, required this.mine});

  final int id;
  final int? parentId;
  final UserSummary author;
  final String body;
  final DateTime createdAt;
  final bool mine;

  factory Comment.fromJson(dynamic j) {
    final m = asMap(j);
    return Comment(
      id: asInt(m['id']),
      parentId: asIntOrNull(m['parentId']),
      author: UserSummary.fromJson(m['author']),
      body: asStr(m['body']),
      createdAt: asTime(m['createdAt']) ?? DateTime.now(),
      mine: asBool(m['mine']),
    );
  }
}

// ============================================================ 채팅·알림

class ChatMessage {
  ChatMessage({required this.id, required this.chatId, required this.senderId, required this.clientMessageId, required this.body, required this.deleted, required this.createdAt, this.pending = false, this.failed = false});

  final int id;
  final int chatId;
  final int senderId;
  final String clientMessageId;
  final String body;
  final bool deleted;
  final DateTime createdAt;
  bool pending;
  bool failed;

  factory ChatMessage.fromJson(dynamic j) {
    final m = asMap(j);
    return ChatMessage(
      id: asInt(m['id']),
      chatId: asInt(m['chatId']),
      senderId: asInt(m['senderId']),
      clientMessageId: asStr(m['clientMessageId']),
      body: asStr(m['body']),
      deleted: asBool(m['deleted']),
      createdAt: asTime(m['createdAt']) ?? DateTime.now(),
    );
  }
}

class ChatSummary {
  ChatSummary({required this.id, required this.other, this.lastMessage, required this.unreadCount, required this.otherLastRead, required this.blocked});

  final int id;
  final UserSummary other;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final int otherLastRead;
  final bool blocked;

  factory ChatSummary.fromJson(dynamic j) {
    final m = asMap(j);
    return ChatSummary(
      id: asInt(m['id']),
      other: UserSummary.fromJson(m['other']),
      lastMessage: m['lastMessage'] == null ? null : ChatMessage.fromJson(m['lastMessage']),
      unreadCount: asInt(m['unreadCount']),
      otherLastRead: asInt(m['otherLastReadMessageId']),
      blocked: asBool(m['blocked']),
    );
  }
}

class AppNotification {
  AppNotification({required this.id, required this.type, this.actor, this.targetType, this.targetId, this.title, this.body, required this.data, required this.read, required this.createdAt});

  final int id;
  final String type;
  final UserSummary? actor;
  final String? targetType;
  final int? targetId;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
  bool read;
  final DateTime createdAt;

  factory AppNotification.fromJson(dynamic j) {
    final m = asMap(j);
    return AppNotification(
      id: asInt(m['id']),
      type: asStr(m['type']),
      actor: m['actor'] == null ? null : UserSummary.fromJson(m['actor']),
      targetType: asStrOrNull(m['targetType']),
      targetId: asIntOrNull(m['targetId']),
      title: asStrOrNull(m['title']),
      body: asStrOrNull(m['body']),
      data: asMap(m['data']),
      read: asBool(m['read']),
      createdAt: asTime(m['createdAt']) ?? DateTime.now(),
    );
  }
}

// ============================================================ 지역

class Region {
  const Region(this.label, this.codes);

  final String label;
  final List<String> codes;
}

/// 시도 코드 (법정동 앞 2자리). 강원·전북은 특별자치도 전환 전후 코드를 모두 포함.
const List<Region> kRegions = [
  Region('전체', []),
  Region('서울', ['11']),
  Region('경기', ['41']),
  Region('인천', ['28']),
  Region('부산', ['26']),
  Region('대구', ['27']),
  Region('대전', ['30']),
  Region('광주', ['29']),
  Region('울산', ['31']),
  Region('세종', ['36']),
  Region('강원', ['42', '51']),
  Region('충북', ['43']),
  Region('충남', ['44']),
  Region('전북', ['45', '52']),
  Region('전남', ['46']),
  Region('경북', ['47']),
  Region('경남', ['48']),
  Region('제주', ['50']),
];

const Map<String, String> kPositions = {
  'PIVO': '피보(공격)',
  'ALA': '아라(측면)',
  'FIXO': '픽소(수비)',
  'GOLEIRO': '골레이로(골키퍼)',
  'ANY': '상관없음',
};

const Map<String, String> kSurfaces = {
  'ARTIFICIAL_TURF': '인조잔디',
  'URETHANE': '우레탄',
  'WOOD': '마루',
  'OTHER': '기타',
};
