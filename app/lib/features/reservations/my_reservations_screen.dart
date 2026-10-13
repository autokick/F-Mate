import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import 'reservation_detail_screen.dart';
import 'reservation_result_screen.dart';

class MyReservationsScreen extends StatefulWidget {
  const MyReservationsScreen({super.key});

  @override
  State<MyReservationsScreen> createState() => _MyReservationsScreenState();
}

class _MyReservationsScreenState extends State<MyReservationsScreen> {
  static const _filters = <(String, String?)>[
    ('전체', null),
    ('확정', 'CONFIRMED'),
    ('결제 대기', 'PENDING_PAYMENT'),
    ('이용 완료', 'COMPLETED'),
    ('취소·환불', 'CANCELED'),
  ];
  int _filter = 0;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final status = _filters[_filter].$2;
    return Scaffold(
      appBar: AppBar(title: const Text('내 예약')),
      body: PagedList<ReservationListItem>(
        key: ValueKey('$_filter-$_reload'),
        fetch: (cursor) async {
          final page = cursor ?? 0;
          var list = await services.reservations.list(status: status, page: page);
          if (status == 'CANCELED') {
            // 환불 완료도 함께
            final refunded = page == 0 ? await services.reservations.list(status: 'REFUNDED') : <ReservationListItem>[];
            list = [...list, ...refunded];
          }
          return (list, list.length >= 20 ? page + 1 : null);
        },
        header: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, FmSpace.s),
          child: Row(
            children: [
              for (var i = 0; i < _filters.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: FmSpace.s),
                  child: ChoiceChip(
                    label: Text(_filters[i].$1),
                    selected: _filter == i,
                    onSelected: (_) => setState(() => _filter = i),
                  ),
                ),
            ],
          ),
        ),
        itemBuilder: (context, r, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: FmSpace.l, vertical: FmSpace.xs),
          child: FmCard(
            onTap: () async {
              await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ReservationDetailScreen(publicId: r.publicId)));
              if (mounted) setState(() => _reload++);
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.venueName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${r.courtName} · ${Fmt.date(r.startsAt)} ${Fmt.range(r.startsAt, r.endsAt)}',
                          style: const TextStyle(fontSize: 13, color: FmColors.textSecondary)),
                      const SizedBox(height: FmSpace.xs),
                      Text(Fmt.won(r.totalAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                reservationStatusChip(r.status),
              ],
            ),
          ),
        ),
        empty: const EmptyState(icon: Icons.event_note_outlined, title: '예약 내역이 없어요', message: '예약 탭에서 구장을 찾아 예약해 보세요.'),
      ),
    );
  }
}
