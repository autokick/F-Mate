import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/court_illustration.dart';
import 'venue_slots.dart';

/// 구장 목록 카드: 큰 사진 + 이름·거리·시설 + 가격 + 남은 시간
class VenueTile extends StatelessWidget {
  const VenueTile({
    super.key,
    required this.venue,
    required this.onTap,
    this.date,
    this.fromHour,
    this.toHour,
    this.onTimeTap,
  });

  final VenueCard venue;
  final VoidCallback onTap;

  /// 이 날짜의 남은 시간을 칩으로 보여준다 (없으면 생략)
  final DateTime? date;
  final int? fromHour;
  final int? toHour;
  final void Function(DateTime time)? onTimeTap;

  static const Map<String, String> _facilityShort = {
    'SHOWER': '샤워실',
    'PARKING': '주차',
    'CHANGING_ROOM': '탈의실',
    'NIGHT_LIGHTING': '야간 조명',
  };

  @override
  Widget build(BuildContext context) {
    final v = venue;
    final kind = [
      if (v.hasIndoor && v.hasOutdoor) '실내·실외' else if (v.hasIndoor) '실내' else if (v.hasOutdoor) '실외',
      ...v.sizes.map((s) => s.replaceAll('V', ':')),
    ].join(' · ');
    final district = _district(v.roadAddress);
    final meta = [
      if (district != null) district,
      if (v.distanceKm != null) '${v.distanceKm}km',
      for (final f in v.facilities)
        if (_facilityShort.containsKey(f)) _facilityShort[f]!,
    ].take(4).join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(FmSpace.page, 0, FmSpace.page, FmSpace.xl),
      child: Semantics(
        button: true,
        label: v.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FmRadius.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(FmRadius.card),
                child: AspectRatio(
                  aspectRatio: 350 / 196,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      v.thumbnailUrl == null
                          ? CourtIllustration(seed: v.id, indoor: v.hasIndoor && !v.hasOutdoor)
                          : Image.network(
                              v.thumbnailUrl!,
                              fit: BoxFit.cover,
                              semanticLabel: '${v.name} 사진',
                              errorBuilder: (context, e, s) => Container(color: FmColors.photoPlaceholder),
                            ),
                      if (kind.isNotEmpty)
                        Positioned(
                          left: 12,
                          top: 12,
                          child: _Badge(text: kind),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: FmColors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  if (v.minPrice != null) ...[
                    const SizedBox(width: FmSpace.s),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('시간당', style: TextStyle(fontSize: 12, color: FmColors.textSecondary)),
                        Text('${Fmt.won(v.minPrice)}~', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ],
              ),
              if (date != null) ...[
                const SizedBox(height: 10),
                _TimeChips(venueId: v.id, date: date!, fromHour: fromHour, toHour: toHour, onTap: onTimeTap ?? (_) => onTap()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "서울특별시 중랑구 ..." → "중랑구"
  static String? _district(String address) {
    final parts = address.split(' ');
    for (final p in parts.skip(1)) {
      if (p.endsWith('구') || p.endsWith('시') || p.endsWith('군')) return p;
    }
    return null;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xB80F1419), borderRadius: BorderRadius.circular(FmRadius.chip)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// 남은 시간 칩 (최대 3개 + 나머지 개수)
class _TimeChips extends StatelessWidget {
  const _TimeChips({required this.venueId, required this.date, required this.onTap, this.fromHour, this.toHour});

  final int venueId;
  final DateTime date;
  final int? fromHour;
  final int? toHour;
  final void Function(DateTime time) onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return SizedBox(
      height: 34,
      child: FutureBuilder<List<DateTime>>(
        future: VenueSlots.of(s, venueId, date, fromHour: fromHour, toHour: toHour),
        builder: (context, snap) {
          final times = snap.data;
          if (times == null) return const SizedBox.shrink();
          if (times.isEmpty) {
            return const Align(
              alignment: Alignment.centerLeft,
              child: Text('이 날은 남은 시간이 없어요', style: TextStyle(fontSize: 13, color: FmColors.textSecondary)),
            );
          }
          return Row(
            children: [
              for (final t in times.take(3))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Material(
                    color: FmColors.brandSoft,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onTap(t),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: Text(Fmt.time(t),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: FmColors.brandOnSoft)),
                      ),
                    ),
                  ),
                ),
              if (times.length > 3)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: FmColors.surfaceMuted, borderRadius: BorderRadius.circular(10)),
                  child: Text('+${times.length - 3}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: FmColors.textSecondary)),
                ),
            ],
          );
        },
      ),
    );
  }
}
