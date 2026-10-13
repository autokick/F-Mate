import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import '../reservations/my_reservations_screen.dart';
import '../venues/venue_detail_screen.dart';
import '../venues/venue_tile.dart';

enum TimeBand {
  all('전체', null, null),
  morning('오전 06~12시', 6, 12),
  afternoon('오후 12~18시', 12, 18),
  night('야간 18~24시', 18, 24);

  const TimeBand(this.label, this.fromHour, this.toHour);

  final String label;
  final int? fromHour;
  final int? toHour;
}

String weekdayKo(DateTime d) => Fmt.weekday(d);

String formatDateKo(DateTime d) => Fmt.date(d);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 예약 탭: 날짜·지역·시간대를 고르면 실제로 그 시간에 예약 가능한 구장만 보여준다.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, this.today});

  /// 테스트에서 날짜 고정용
  final DateTime? today;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const int bookableDays = 14;

  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());
  late DateTime _selectedDate = _today;
  Region _region = kRegions.first;
  TimeBand _band = TimeBand.all;

  String get _queryKey => '${Fmt.isoDate(_selectedDate)}-${_region.label}-${_band.name}';

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('예약'),
        actions: [
          TextButton.icon(
            onPressed: () {
              if (!requireLogin(context)) return;
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyReservationsScreen()));
            },
            icon: const Icon(Icons.receipt_long_outlined, size: 20),
            label: const Text('내 예약'),
          ),
        ],
      ),
      body: PagedList<VenueCard>(
        key: ValueKey(_queryKey),
        fetch: (cursor) async {
          final page = cursor ?? 0;
          final r = await services.venues.search(
            regions: _region.codes,
            date: _selectedDate,
            fromHour: _band.fromHour,
            toHour: _band.toHour,
            page: page,
          );
          return (r.items, r.hasNext ? page + 1 : null);
        },
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('날짜 선택'),
            SizedBox(
              height: 76,
              child: ListView.separated(
                key: const Key('date_strip'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
                itemCount: bookableDays,
                separatorBuilder: (context, index) => const SizedBox(width: FmSpace.s),
                itemBuilder: (context, i) {
                  final day = _today.add(Duration(days: i));
                  return DateChip(
                    date: day,
                    isToday: i == 0,
                    selected: day == _selectedDate,
                    onTap: () => setState(() => _selectedDate = day),
                  );
                },
              ),
            ),
            const SectionTitle('지역'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
              child: Row(
                children: [
                  for (final r in kRegions)
                    Padding(
                      padding: const EdgeInsets.only(right: FmSpace.s),
                      child: ChoiceChip(
                        label: Text(r.label),
                        selected: _region == r,
                        onSelected: (_) => setState(() => _region = r),
                      ),
                    ),
                ],
              ),
            ),
            const SectionTitle('시간대'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
              child: Wrap(
                spacing: FmSpace.s,
                runSpacing: FmSpace.s,
                children: [
                  for (final b in TimeBand.values)
                    ChoiceChip(label: Text(b.label), selected: _band == b, onSelected: (_) => setState(() => _band = b)),
                ],
              ),
            ),
            SectionTitle(
              '예약 가능한 구장',
              trailing: Text(formatDateKo(_selectedDate),
                  key: const Key('selected_date_label'),
                  style: const TextStyle(fontSize: 14, color: FmColors.textSecondary)),
            ),
          ],
        ),
        itemBuilder: (context, v, i) => VenueTile(
          venue: v,
          showAvailability: true,
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => VenueDetailScreen(venueId: v.id, initialDate: _selectedDate))),
        ),
        empty: EmptyState(
          icon: Icons.event_busy_outlined,
          title: '예약 가능한 구장이 아직 없어요',
          message: '${_region.label} · ${_band.label} 조건으로 찾은 결과예요.\n'
              '예약 가능 시간은 구장 운영자가 등록한 실제 일정만 표시돼요.',
        ),
      ),
    );
  }
}

/// 날짜 선택 칩
class DateChip extends StatelessWidget {
  const DateChip({super.key, required this.date, required this.isToday, required this.selected, required this.onTap});

  final DateTime date;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSunday = date.weekday == DateTime.sunday;
    final isSaturday = date.weekday == DateTime.saturday;
    final weekdayColor = selected
        ? Colors.white
        : isSunday
            ? FmColors.danger
            : isSaturday
                ? const Color(0xFF2563EB)
                : FmColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: '${formatDateKo(date)}${isToday ? ', 오늘' : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? FmColors.brandDark : FmColors.surfaceMuted,
        borderRadius: BorderRadius.circular(FmRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(FmRadius.control),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(isToday ? '오늘' : weekdayKo(date),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: weekdayColor)),
                const SizedBox(height: FmSpace.xs),
                Text('${date.day}',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: selected ? Colors.white : FmColors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
