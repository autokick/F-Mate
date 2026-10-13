import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';

const List<String> kDays = ['일', '월', '화', '수', '목', '금', '토']; // 0=일요일 (서버 day_of_week 와 같음)

/// 운영시간 구간 하나 (여러 요일에 같은 설정)
class HoursBlock {
  HoursBlock({required this.days, required this.open, required this.close, required this.slot, required this.price});

  Set<int> days;
  int open; // 분 (0~1439)
  int close; // 분 (1~1440)
  int slot; // 30/60/90/120
  int price;
}

String minuteLabel(int m) => m == 1440 ? '24:00' : '${Fmt.two(m ~/ 60)}:${Fmt.two(m % 60)}';

/// 주간 운영시간·요금 편집. 저장하면 앞으로 30일치 예약 슬롯이 다시 만들어진다(이미 예약된 시간은 유지).
class OperatingHoursScreen extends StatefulWidget {
  const OperatingHoursScreen({super.key, required this.court});

  final Court court;

  @override
  State<OperatingHoursScreen> createState() => _OperatingHoursScreenState();
}

class _OperatingHoursScreenState extends State<OperatingHoursScreen> {
  List<HoursBlock>? _blocks;

  Future<List<HoursBlock>> _load() async {
    final rows = await AppScope.read(context).operator.hours(widget.court.id);
    // 같은 시간·슬롯·요금을 가진 요일을 하나의 구간으로 묶어 보여준다
    final map = <String, HoursBlock>{};
    for (final r in rows) {
      final key = '${r['openMinute']}-${r['closeMinute']}-${r['slotMinutes']}-${r['pricePerSlot']}';
      map.putIfAbsent(
          key,
          () => HoursBlock(
              days: {},
              open: asInt(r['openMinute']),
              close: asInt(r['closeMinute']),
              slot: asInt(r['slotMinutes']),
              price: asInt(r['pricePerSlot'])));
      map[key]!.days.add(asInt(r['dayOfWeek']));
    }
    _blocks = map.values.toList();
    return _blocks!;
  }

  Future<void> _save() async {
    final blocks = _blocks ?? [];
    final rows = <Map<String, dynamic>>[];
    for (final b in blocks) {
      if (b.days.isEmpty) continue;
      if (b.close <= b.open || (b.close - b.open) % b.slot != 0) {
        showFmSnack(context, '${minuteLabel(b.open)}~${minuteLabel(b.close)} 구간이 슬롯 길이(${b.slot}분)로 나누어 떨어지지 않아요');
        return;
      }
      for (final d in b.days) {
        rows.add({'dayOfWeek': d, 'openMinute': b.open, 'closeMinute': b.close, 'slotMinutes': b.slot, 'pricePerSlot': b.price});
      }
    }
    try {
      final n = await AppScope.read(context).operator.replaceHours(widget.court.id, rows);
      if (!mounted) return;
      showFmSnack(context, '저장했어요. 예약 슬롯 $n개를 새로 만들었어요');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<int?> _pickMinute(int current, {bool allowEnd = false}) {
    final options = [for (var m = 0; m <= (allowEnd ? 1440 : 1410); m += 30) m];
    return showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            for (final m in options)
              ListTile(
                title: Text(minuteLabel(m)),
                selected: m == current,
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.court.name} 운영시간')),
      body: AsyncBody<List<HoursBlock>>(
        load: _load,
        builder: (context, _, reload) {
          final blocks = _blocks!;
          return ListView(
            padding: const EdgeInsets.all(FmSpace.l),
            children: [
              const Text('요일별 운영 시간과 1슬롯(예약 단위) 요금을 정해요. 시간대별로 요금이 다르면 구간을 나눠 추가하세요.',
                  style: TextStyle(fontSize: 13, color: FmColors.textSecondary, height: 1.5)),
              const SizedBox(height: FmSpace.m),
              for (var i = 0; i < blocks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: FmSpace.m),
                  child: FmCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(spacing: 4, children: [
                          for (var d = 0; d < 7; d++)
                            FilterChip(
                              label: Text(kDays[d]),
                              selected: blocks[i].days.contains(d),
                              onSelected: (on) => setState(() => on ? blocks[i].days.add(d) : blocks[i].days.remove(d)),
                            ),
                        ]),
                        Row(children: [
                          TextButton(
                            onPressed: () async {
                              final m = await _pickMinute(blocks[i].open);
                              if (m != null) setState(() => blocks[i].open = m);
                            },
                            child: Text('시작 ${minuteLabel(blocks[i].open)}'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final m = await _pickMinute(blocks[i].close, allowEnd: true);
                              if (m != null) setState(() => blocks[i].close = m);
                            },
                            child: Text('종료 ${minuteLabel(blocks[i].close)}'),
                          ),
                          const Spacer(),
                          DropdownButton<int>(
                            value: blocks[i].slot,
                            items: [for (final s in const [60, 90, 120, 30]) DropdownMenuItem(value: s, child: Text('$s분'))],
                            onChanged: (v) => setState(() => blocks[i].slot = v ?? 60),
                          ),
                        ]),
                        Row(children: [
                          const Text('슬롯당 요금'),
                          const SizedBox(width: FmSpace.m),
                          Expanded(
                            child: TextFormField(
                              initialValue: '${blocks[i].price}',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(suffixText: '원'),
                              onChanged: (v) => blocks[i].price = int.tryParse(v.replaceAll(',', '')) ?? 0,
                            ),
                          ),
                          IconButton(
                            tooltip: '구간 삭제',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => setState(() => blocks.removeAt(i)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => setState(() => blocks.add(
                    HoursBlock(days: {0, 1, 2, 3, 4, 5, 6}, open: 360, close: 1440, slot: 60, price: 60000))),
                icon: const Icon(Icons.add_rounded),
                label: const Text('운영 구간 추가'),
              ),
              const SizedBox(height: FmSpace.l),
              LoadingButton(label: '저장하고 슬롯 만들기', onPressed: _save),
              const SizedBox(height: FmSpace.s),
              const Text('이미 예약이 들어온 시간은 바뀌지 않아요. 특정 날짜만 바꾸려면 "날짜별 슬롯"에서 수정하세요.',
                  style: TextStyle(fontSize: 12, color: FmColors.textSecondary)),
            ],
          );
        },
      ),
    );
  }
}
