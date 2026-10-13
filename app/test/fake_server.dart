// 위젯 테스트용 가짜 서버 (Dio 어댑터). 실제 네트워크를 쓰지 않는다.
// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef Handler = (int, Object?) Function(RequestOptions req);

class FakeServer implements HttpClientAdapter {
  FakeServer(this.handler, {this.unreachable = false});

  final Handler handler;
  final bool unreachable;
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    if (unreachable) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError, message: 'unreachable');
    }
    final (status, body) = handler(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> configJson({bool payment = true, bool places = false}) => {
      'serverVersion': '1.0.0',
      'devMode': true,
      'features': {
        'payment': {'enabled': payment, 'mode': 'TEST'},
        'media': false,
        'video': false,
        'push': false,
        'maps': false,
        'email': false,
        'socialProviders': <String>[],
        'places': places,
      },
      'termsVersion': '2026-10',
      'regions': <String>[],
    };

Map<String, dynamic> error(String code, String title) => {'code': code, 'title': title, 'status': 400};

/// 이틀 뒤 19:00 부터 1시간 슬롯 3개 (60,000원)
List<Map<String, dynamic>> futureSlots() {
  final d = DateTime.now().add(const Duration(days: 2));
  final base = DateTime(d.year, d.month, d.day, 19);
  return [
    for (var i = 0; i < 3; i++)
      {
        'slotId': 100 + i,
        'startsAt': base.add(Duration(hours: i)).toUtc().toIso8601String(),
        'endsAt': base.add(Duration(hours: i + 1)).toUtc().toIso8601String(),
        'price': 60000,
        'available': i != 2,
      }
  ];
}

/// 기본 라우팅: 설정 OK, 구장 1곳
(int, Object?) defaultRoutes(RequestOptions r) {
  final path = r.path;
  if (path == '/api/v1/config') return (200, configJson());
  if (path == '/api/v1/venues' && r.method == 'GET') {
    return (
      200,
      {
        'items': [
          {
            'id': 1,
            'name': '화성 테스트 풋살장',
            'roadAddress': '경기도 화성시 테스트로 1',
            'regionCode': '41590',
            'latitude': 37.2,
            'longitude': 127.0,
            'minPrice': 60000,
            'hasIndoor': true,
            'hasOutdoor': false,
            'sizes': ['5V5'],
            'facilities': ['PARKING'],
            'availableSlots': 2,
          }
        ],
        'page': 0,
        'hasNext': false,
      }
    );
  }
  if (path == '/api/v1/venues/1') {
    return (
      200,
      {
        'id': 1,
        'name': '화성 테스트 풋살장',
        'roadAddress': '경기도 화성시 테스트로 1',
        'regionCode': '41590',
        'latitude': 37.2,
        'longitude': 127.0,
        'cancelPolicy': [
          {'hoursBefore': 72, 'refundPercent': 100},
          {'hoursBefore': 24, 'refundPercent': 50},
          {'hoursBefore': 0, 'refundPercent': 0},
        ],
        'verificationStatus': 'VERIFIED',
        'photos': <Object>[],
        'courts': [
          {'id': 10, 'name': 'A코트', 'isIndoor': true, 'surface': 'ARTIFICIAL_TURF', 'sizeClass': '5V5', 'isActive': true}
        ],
        'facilities': [
          {'code': 'PARKING', 'label': '주차'}
        ],
      }
    );
  }
  if (path == '/api/v1/venues/1/availability') {
    return (
      200,
      [
        {'courtId': 10, 'courtName': 'A코트', 'isIndoor': true, 'sizeClass': '5V5', 'slots': futureSlots()}
      ]
    );
  }
  if (path == '/api/v1/places/futsal-nearby') {
    return (
      200,
      {
        'items': [
          {
            'id': '123',
            'name': '동탄 실제 풋살장',
            'category': '스포츠,레저 > 축구 > 풋살장',
            'phone': '031-000-0000',
            'roadAddress': '경기 화성시 동탄대로 1',
            'lat': 37.2,
            'lng': 127.07,
            'placeUrl': 'https://place.map.kakao.com/123',
          }
        ],
        'page': 1,
        'hasNext': false,
        'attribution': '장소 정보 제공: 카카오',
      }
    );
  }
  if (path == '/api/v1/auth/login') {
    return (401, error('INVALID_CREDENTIALS', '이메일 또는 비밀번호가 올바르지 않아요'));
  }
  return (404, error('NOT_FOUND', '찾을 수 없어요'));
}
