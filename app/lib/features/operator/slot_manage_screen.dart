import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import '../booking/booking_screen.dart';

/// 날짜별 슬롯: 개별 시간 닫기/열기, 요금 변경. 예약이 걸린 슬롯은 서버가 변경을 막는다.
class SlotManageScreen extends StatefulWidget {
  const SlotManageScreen({super.key, required this.court});

  final Court court;

  @override
  State<SlotManageScreen> createState() => _SlotManageScreenState();
}

class _SlotManageScreenState extends State<SlotManageScreen> {
  final DateTime _today = dateOnly(DateTime.now());
  late DateTime _date = _today;
  int _reload = 0;

  Future<void> _update(int slotId, {String? status, int? price}) async {
    try {
      await AppScope.read(context).operator.updateSlot(slotId, status: status, price: price);
      if (mounted) setState(() => _reload++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.court.name} 슬롯')),
      body: Column(
        children: [
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(FmSpace.s),
              itemCount: 30,
              separatorBuilder: (context, i) => const SizedBox(width: FmSpace.s),
              itemBuilder: (context, i) {
                final d = _today.add(Duration(days: i));
                return DateChip(date: d, isToday: i == 0, selected: d == _date, onTap: () => setState(() => _date = d));
              },
            ),
          ),
          Expanded(
            child: AsyncBody<List<Map<String, dynamic>>>(
              key: ValueKey('${Fmt.isoDate(_date)}-$_reload'),
              load: () => services.operator.slots(widget.court.id, _date),
              isEmpty: (l) => l.isEmpty,
              empty: const EmptyState(
                icon: Icons.schedule_rounded,
                title: '이 날의 슬롯이 없어요',
                message: '운영시간·요금을 먼저 설정하면 30일치 슬롯이 자동으로 만들어져요.',
              ),
              builder: (context, slots, reload) => ListView(
                children: [
                  for (final s in slots)
                    ListTile(
                      title: Text(Fmt.range(asTime(s['startsAt'])!, asTime(s['endsAt'])!)),
                      subtitle: Text([
                        Fmt.won(asInt(s['price'])),
                        if (s['reservationStatus'] != null)
                          '${s['reservationStatus'] == 'CONFIRMED' ? '예약 확정' : '결제 대기'} · ${asStr(s['reservedBy'])}',
                      ].join(' · ')),
                      trailing: s['reservationStatus'] != null
                          ? const Icon(Icons.lock_rounded, color: FmColors.textSecondary)
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: '요금 변경',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  final v = await promptDialog(context, title: '이 슬롯 요금 (원)', maxLength: 9);
                                  final price = int.tryParse((v ?? '').replaceAll(',', ''));
                                  if (price != null) await _update(asInt(s['id']), price: price);
                                },
                              ),
                              Switch(
                                value: asStr(s['status']) == 'OPEN',
                                onChanged: (on) => _update(asInt(s['id']), status: on ? 'OPEN' : 'CLOSED'),
                              ),
                            ]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
