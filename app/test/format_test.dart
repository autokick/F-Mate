// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/format.dart';
import '../lib/core/models.dart';

void main() {
  test('원화 표기', () {
    expect(Fmt.won(0), '0원');
    expect(Fmt.won(60000), '60,000원');
    expect(Fmt.won(1234567), '1,234,567원');
    expect(Fmt.won(-5000), '-5,000원');
    expect(Fmt.won(null), '-');
  });

  test('날짜 표기', () {
    expect(Fmt.date(DateTime(2026, 10, 11)), '10월 11일(일)');
    expect(Fmt.date(DateTime(2026, 12, 31)), '12월 31일(목)');
    expect(Fmt.range(DateTime(2026, 1, 1, 19), DateTime(2026, 1, 1, 21, 30)), '19:00 ~ 21:30');
    expect(Fmt.isoDate(DateTime(2026, 3, 5)), '2026-03-05');
  });

  test('UUID v4 형식과 고유성', () {
    final re = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final ids = {for (var i = 0; i < 1000; i++) uuidV4()};
    expect(ids.length, 1000);
    expect(ids.every(re.hasMatch), isTrue);
  });

  test('서버 응답 파싱: 누락·null 에 견고', () {
    final me = Me.fromJson({'id': 1, 'nickname': '풋살', 'counts': null});
    expect(me.counts.posts, 0);
    expect(me.needsProfile, isFalse);
    expect(me.isAdmin, isFalse);

    final r = Reservation.fromJson({
      'publicId': 'abc',
      'venue': {'id': 1, 'name': 'V'},
      'court': {'id': 2, 'name': 'A'},
      'startsAt': '2026-10-12T10:00:00Z',
      'endsAt': '2026-10-12T11:00:00Z',
      'totalAmount': 60000,
      'status': 'CONFIRMED',
      'cancelPolicy': [
        {'hoursBefore': 24, 'refundPercent': 50},
        {'hoursBefore': 72, 'refundPercent': 100},
      ],
    });
    expect(r.cancelPolicy.first.hoursBefore, 72, reason: '정책은 시간 내림차순 정렬');
    expect(r.payment, isNull);
    expect(reservationStatusLabel(r.status), '예약 확정');
  });

  test('지역 코드: 강원·전북은 구·신 코드 모두 포함', () {
    final gangwon = kRegions.firstWhere((r) => r.label == '강원');
    expect(gangwon.codes, containsAll(['42', '51']));
  });
}
