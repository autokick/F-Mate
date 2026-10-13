import 'dart:math';

/// 표시용 포맷 (intl 패키지 없이)
class Fmt {
  Fmt._();

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  static String weekday(DateTime d) => _weekdays[d.weekday - 1];

  /// 60000 → 60,000원
  static String won(num? amount) {
    if (amount == null) return '-';
    final s = amount.round().abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${amount < 0 ? '-' : ''}${buf.toString()}원';
  }

  static String two(int n) => n.toString().padLeft(2, '0');

  /// 10월 12일(월)
  static String date(DateTime d) => '${d.month}월 ${d.day}일(${weekday(d)})';

  /// 19:00
  static String time(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

  /// 10월 12일(월) 19:00
  static String dateTime(DateTime d) => '${date(d)} ${time(d)}';

  /// 19:00 ~ 21:00
  static String range(DateTime a, DateTime b) => '${time(a)} ~ ${time(b)}';

  /// 2026-10-12 (서버 날짜 파라미터)
  static String isoDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

  /// 방금 / 5분 전 / 3시간 전 / 2일 전 / 10월 1일
  static String ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${d.month}월 ${d.day}일';
  }

  /// 숫자 축약: 1200 → 1.2천, 15000 → 1.5만
  static String count(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}천';
    return '${(n / 10000).toStringAsFixed(1)}만';
  }
}

/// UUID v4 (멱등키·채팅 메시지 ID 용)
String uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = List.generate(16, h).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

/// JSON 파싱 도우미
int asInt(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);
int? asIntOrNull(dynamic v) => v is num ? v.toInt() : (v == null ? null : int.tryParse('$v'));
double? asDoubleOrNull(dynamic v) => v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));
bool asBool(dynamic v) => v == true;
String asStr(dynamic v, [String fallback = '']) => v is String ? v : (v == null ? fallback : '$v');
String? asStrOrNull(dynamic v) => v is String ? v : (v == null ? null : '$v');
DateTime? asTime(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> asList(dynamic v) => v is List ? v : const [];
