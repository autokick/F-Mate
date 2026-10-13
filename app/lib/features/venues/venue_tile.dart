import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../shared/court_illustration.dart';
import '../../shared/widgets.dart';

/// 구장 목록 카드
class VenueTile extends StatelessWidget {
  const VenueTile({super.key, required this.venue, required this.onTap, this.showAvailability = false});

  final VenueCard venue;
  final VoidCallback onTap;
  final bool showAvailability;

  @override
  Widget build(BuildContext context) {
    final v = venue;
    final tags = <String>[
      if (v.isPublicData) '공공데이터',
      if (v.hasIndoor) '실내',
      if (v.hasOutdoor) '실외',
      ...v.sizes.map((s) => s.replaceAll('V', ':')),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FmSpace.l, vertical: FmSpace.s / 2),
      child: FmCard(
        onTap: onTap,
        padding: const EdgeInsets.all(FmSpace.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(FmRadius.control),
              child: SizedBox(
                width: 88,
                height: 88,
                child: v.thumbnailUrl == null
                    ? CourtIllustration(seed: v.id, indoor: v.hasIndoor && !v.hasOutdoor)
                    : Image.network(v.thumbnailUrl!, fit: BoxFit.cover,
                        errorBuilder: (context, e, s) => Container(color: FmColors.surfaceMuted)),
              ),
            ),
            const SizedBox(width: FmSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [if (v.distanceKm != null) '${v.distanceKm}km', v.roadAddress].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: FmColors.textSecondary),
                  ),
                  const SizedBox(height: FmSpace.s),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [for (final t in tags) StatusChip(label: t, color: FmColors.textSecondary, background: FmColors.surfaceMuted)],
                  ),
                  const SizedBox(height: FmSpace.s),
                  Row(
                    children: [
                      Text(v.minPrice == null ? '요금 정보 없음' : '${Fmt.won(v.minPrice)}~',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: FmColors.brandDark)),
                      const Spacer(),
                      if (showAvailability && v.availableSlots != null)
                        Text('예약 가능 ${v.availableSlots}타임', style: const TextStyle(fontSize: 13, color: FmColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
