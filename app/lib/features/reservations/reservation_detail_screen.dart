import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import '../venues/venue_detail_screen.dart';
import 'payment_screen.dart';
import 'reservation_result_screen.dart';

class ReservationDetailScreen extends StatefulWidget {
  const ReservationDetailScreen({super.key, required this.publicId});

  final String publicId;

  @override
  State<ReservationDetailScreen> createState() => _ReservationDetailScreenState();
}

class _ReservationDetailScreenState extends State<ReservationDetailScreen> {
  final _key = GlobalKey<AsyncBodyState<Reservation>>();

  Future<void> _cancel(Reservation r) async {
    final refund = r.refundIfCanceledNow;
    final paid = r.payment?.approvedAmount;
    final msg = r.status == 'PENDING_PAYMENT'
        ? '아직 결제 전이라 청구된 금액은 없어요.'
        : '지금 취소하면 ${Fmt.won(refund ?? 0)}이 환불돼요${paid != null ? ' (결제 ${Fmt.won(paid)})' : ''}.\n'
            '환불은 결제 수단으로 처리되며 카드사에 따라 며칠 걸릴 수 있어요.';
    final ok = await confirmDialog(context, title: '예약을 취소할까요?', message: msg, confirm: '예약 취소', destructive: true);
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).reservations.cancel(r.publicId, '사용자 취소', uuidV4());
      if (!mounted) return;
      showFmSnack(context, '예약을 취소했어요');
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _resumePayment(Reservation r) async {
    try {
      final order = await AppScope.read(context).reservations.createOrder(r.publicId, uuidV4());
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => PaymentScreen(order: order, reservationId: r.publicId)));
      await _key.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('예약 상세')),
      body: AsyncBody<Reservation>(
        key: _key,
        load: () => services.reservations.detail(widget.publicId),
        builder: (context, r, reload) {
          final pay = r.payment;
          final holdValid = r.status == 'PENDING_PAYMENT' && r.holdExpiresAt != null && r.holdExpiresAt!.isAfter(DateTime.now());
          final cancelable = (r.status == 'CONFIRMED' && r.startsAt.isAfter(DateTime.now())) ||
              (r.status == 'PENDING_PAYMENT' && pay?.status != 'IN_PROGRESS');
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.all(FmSpace.l),
              children: [
                Row(children: [
                  Expanded(child: Text(r.venueName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  reservationStatusChip(r.status),
                ]),
                const SizedBox(height: FmSpace.m),
                FmCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoRow('코트', '${r.courtName} (${r.courtIndoor ? '실내' : '실외'})'),
                      InfoRow('일시', '${Fmt.date(r.startsAt)} ${Fmt.range(r.startsAt, r.endsAt)}'),
                      InfoRow('주소', r.venueAddress),
                      if (r.venuePhone != null) InfoRow('연락처', r.venuePhone!),
                      InfoRow('예약 금액', Fmt.won(r.totalAmount), bold: true),
                      InfoRow('예약 번호', r.publicId.substring(0, 8).toUpperCase()),
                    ],
                  ),
                ),
                const SizedBox(height: FmSpace.s),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => VenueDetailScreen(venueId: r.venueId))),
                  icon: const Icon(Icons.place_outlined),
                  label: const Text('구장 정보 보기'),
                ),
                if (r.status == 'PENDING_PAYMENT') ...[
                  const SizedBox(height: FmSpace.s),
                  if (holdValid) ...[
                    Text('${Fmt.time(r.holdExpiresAt!)}까지 결제하지 않으면 자동으로 취소돼요',
                        style: const TextStyle(color: Color(0xFF92400E))),
                    const SizedBox(height: FmSpace.s),
                    if (pay?.status != 'IN_PROGRESS') LoadingButton(label: '결제하기', onPressed: () => _resumePayment(r)),
                  ] else
                    const Text('결제 확인 중이거나 결제 시간이 지났어요. 잠시 후 새로고침해 주세요.',
                        style: TextStyle(color: FmColors.textSecondary)),
                ],
                if (r.canceledAt != null) ...[
                  const SectionTitle('취소 정보'),
                  InfoRow('취소 일시', Fmt.dateTime(r.canceledAt!)),
                  InfoRow('취소 주체', switch (r.canceledBy) {
                    'USER' => '본인',
                    'OPERATOR' => '구장',
                    'ADMIN' => '운영팀',
                    _ => '시스템',
                  }),
                  if (r.cancelReason != null) InfoRow('사유', r.cancelReason!),
                ],
                if (pay != null) ...[
                  const SectionTitle('결제'),
                  if (pay.mode != 'LIVE') const Align(alignment: Alignment.centerLeft, child: TestModeBadge()),
                  InfoRow('상태', _payLabel(pay.status)),
                  if (pay.method != null) InfoRow('수단', pay.method!),
                  if (pay.approvedAmount != null) InfoRow('승인 금액', Fmt.won(pay.approvedAmount)),
                  if (pay.balanceAmount != null && pay.balanceAmount != pay.approvedAmount)
                    InfoRow('남은 금액', Fmt.won(pay.balanceAmount)),
                  if (pay.failureMessage != null) InfoRow('실패 사유', pay.failureMessage!),
                  if (pay.receiptUrl != null)
                    TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse(pay.receiptUrl!), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.receipt_outlined),
                      label: const Text('영수증 보기'),
                    ),
                ],
                if (r.refunds.isNotEmpty) ...[
                  const SectionTitle('환불'),
                  for (final f in r.refunds)
                    InfoRow(Fmt.won(f.amount), switch (f.status) {
                      'SUCCEEDED' => '환불 완료${f.completedAt == null ? '' : ' (${Fmt.date(f.completedAt!)})'}',
                      'REQUESTED' => '환불 처리 중',
                      _ => '확인 필요 (운영팀이 처리 중)',
                    }),
                ],
                if (r.status == 'CONFIRMED') ...[
                  const SectionTitle('취소·환불 정책'),
                  PolicyTable(rules: r.cancelPolicy),
                ],
                const SectionTitle('진행 기록'),
                for (final h in r.history)
                  InfoRow(h.at == null ? '' : Fmt.dateTime(h.at!), reservationStatusLabel(h.toStatus)),
                const SizedBox(height: FmSpace.xl),
                if (cancelable)
                  LoadingButton(
                    outlined: true,
                    label: r.status == 'CONFIRMED' ? '예약 취소 (환불 ${Fmt.won(r.refundIfCanceledNow ?? 0)})' : '예약 취소',
                    onPressed: () => _cancel(r),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _payLabel(String s) => switch (s) {
        'READY' => '결제 전',
        'IN_PROGRESS' => '승인 확인 중',
        'DONE' => '결제 완료',
        'PARTIAL_CANCELED' => '부분 환불',
        'CANCELED' => '전액 환불',
        'ABORTED' => '결제 실패',
        'EXPIRED' => '시간 만료',
        _ => s,
      };
}
