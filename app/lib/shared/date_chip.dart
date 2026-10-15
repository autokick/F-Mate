import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// 시간대 필터
enum TimeBand {
  all('전체', null, null),
  morning('오전', 6, 12),
  afternoon('오후', 12, 18),
  night('저녁 6시 이후', 18, 24);

  const TimeBand(this.label, this.fromHour, this.toHour);

  final String label;
  final int? fromHour;
  final int? toHour;
}

String weekdayKo(DateTime d) => Fmt.weekday(d);

String formatDateKo(DateTime d) => Fmt.date(d);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 날짜 선택 칩 (요일 + 날짜). 선택되면 검정 바탕.
class DateChip extends StatelessWidget {
  const DateChip({
    super.key,
    required this.date,
    required this.isToday,
    required this.selected,
    required this.onTap,
    this.width = 52,
  });

  final DateTime date;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final isSunday = date.weekday == DateTime.sunday;
    final isSaturday = date.weekday == DateTime.saturday;
    final weekdayColor = selected
        ? Colors.white
        : isSunday
            ? const Color(0xFFC8341F)
            : isSaturday
                ? const Color(0xFF1D5FD1)
                : FmColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: '${formatDateKo(date)}${isToday ? ', 오늘' : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? FmColors.ink : FmColors.surfaceMuted,
        borderRadius: BorderRadius.circular(FmRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(FmRadius.control),
          onTap: onTap,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(isToday ? '오늘' : weekdayKo(date),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: weekdayColor)),
                const SizedBox(height: 2),
                Text('${date.day}',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: selected ? Colors.white : FmColors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 가로로 넘기는 날짜 띠 (오늘부터 [days]일)
class DateStrip extends StatelessWidget {
  const DateStrip({
    super.key,
    required this.today,
    required this.selected,
    required this.onSelected,
    this.days = 14,
    this.height = 60,
  });

  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;
  final int days;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: FmSpace.page),
        itemCount: days,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final day = today.add(Duration(days: i));
          return DateChip(date: day, isToday: i == 0, selected: day == selected, onTap: () => onSelected(day));
        },
      ),
    );
  }
}
