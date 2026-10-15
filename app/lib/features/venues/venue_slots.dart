import '../../core/format.dart';
import '../../core/services.dart';

/// 구장의 날짜별 남은 시작 시간 (목록 카드·숏폼 구장 카드용).
/// 같은 구장·날짜는 1분 동안 다시 서버에 묻지 않는다.
class VenueSlots {
  VenueSlots._();

  static final Map<String, (DateTime, Future<List<DateTime>>)> _cache = {};

  /// [date] 의 예약 가능한 시작 시간 (지금 이후, 시간순). [fromHour]~[toHour] 로 거를 수 있다.
  static Future<List<DateTime>> of(AppServices s, int venueId, DateTime date, {int? fromHour, int? toHour}) {
    final now = DateTime.now();
    final key = '$venueId|${Fmt.isoDate(date)}';
    final hit = _cache[key];
    final Future<List<DateTime>> all;
    if (hit != null && now.difference(hit.$1) < const Duration(minutes: 1)) {
      all = hit.$2;
    } else {
      all = s.venues.availability(venueId, date).then((courts) {
        final times = <DateTime>{};
        for (final c in courts) {
          for (final slot in c.slots) {
            if (slot.available && slot.startsAt.isAfter(now)) times.add(slot.startsAt);
          }
        }
        return times.toList()..sort();
      }).catchError((Object _) => <DateTime>[]);
      _cache[key] = (now, all);
    }
    if (fromHour == null && toHour == null) return all;
    return all.then((list) =>
        list.where((t) => t.hour >= (fromHour ?? 0) && t.hour < (toHour ?? 24)).toList());
  }

  /// 예약하거나 취소한 뒤 바로 반영되도록 비운다
  static void clear() => _cache.clear();
}
