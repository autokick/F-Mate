import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../firebase_exhibition/payment/toss_test_checkout.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../venues/venue_detail_screen.dart';
import 'payment_screen.dart';

/// 예약 확인 → (서버) 10분 선점 → 결제 주문 생성 → 결제창
class ReservationConfirmScreen extends StatefulWidget {
  const ReservationConfirmScreen({super.key, required this.venue, required this.court, required this.slots});

  final VenueDetail venue;
  final Court court;
  final List<Slot> slots;

  @override
  State<ReservationConfirmScreen> createState() => _ReservationConfirmScreenState();
}

class _ReservationConfirmScreenState extends State<ReservationConfirmScreen> {
  bool _agreed = false;
  // 같은 화면에서 버튼을 여러 번 눌러도 예약·주문은 한 번만 만들어진다 (서버 멱등 처리)
  final String _holdKey = uuidV4();
  final String _orderKey = uuidV4();

  int get _total => widget.slots.fold<int>(0, (a, s) => a + s.price);

  Future<void> _pay() async {
    if (!_agreed) {
      showFmSnack(context, '취소·환불 정책을 확인하고 동의해 주세요');
      return;
    }
    final s = AppScope.read(context);
    try {
      final r = await s.reservations.create(widget.court.id, widget.slots.first.startsAt, widget.slots.last.endsAt, _holdKey);
      if (r.totalAmount != _total) {
        // 서버가 계산한 금액이 화면과 다르면(요금 변경 등) 사용자에게 알린다
        if (!mounted) return;
        final ok = await confirmDialog(context,
            title: '요금이 변경되었어요', message: '최종 결제 금액은 ${Fmt.won(r.totalAmount)}이에요. 계속할까요?', confirm: '계속');
        if (!ok) {
          await s.reservations.cancel(r.publicId, '요금 변경으로 취소', uuidV4());
          return;
        }
      }
      if (AppConfig.firebaseMode) {
        if (!mounted) return;
        // Keep collaborator booking UI; open real Toss TEST widget afterwards.
        // No server-side payment confirmation or real booking takes place.
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => TossTestCheckout(
            venueName: widget.venue.name,
            amount: r.totalAmount,
          )),
          result: true,
        );
        return;
      }
      final order = await s.reservations.createOrder(r.publicId, _orderKey);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PaymentScreen(order: order, reservationId: r.publicId)),
        result: true,
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'SLOT_TAKEN' || e.code == 'SLOT_UNAVAILABLE') {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('예약할 수 없는 시간이에요'),
            content: Text(e.code == 'SLOT_TAKEN' ? '방금 다른 분이 먼저 예약했어요. 다른 시간을 선택해 주세요.' : e.message),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('확인'))],
          ),
        );
        if (mounted) Navigator.of(context).pop(true); // 슬롯 목록을 새로 불러오게
      } else {
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.slots.first.startsAt;
    final end = widget.slots.last.endsAt;
    return Scaffold(
      appBar: AppBar(title: const Text('예약 확인')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FmSpace.l),
          children: [
            FmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.venue.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: FmSpace.s),
                  InfoRow('코트', '${widget.court.name} (${widget.court.isIndoor ? '실내' : '실외'} · ${widget.court.sizeClass.replaceAll('V', ':')})'),
                  InfoRow('날짜', Fmt.date(start)),
                  InfoRow('시간', Fmt.range(start, end)),
                  InfoRow('주소', widget.venue.roadAddress),
                  const Divider(height: FmSpace.xl),
                  InfoRow('결제 금액', Fmt.won(_total), bold: true),
                ],
              ),
            ),
            const SectionTitle('취소·환불 정책'),
            PolicyTable(rules: widget.venue.cancelPolicy),
            const SizedBox(height: FmSpace.m),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('취소·환불 정책과 이용 규칙을 확인했어요', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: FmSpace.s),
            Text(AppConfig.firebaseMode
                ? '시연용 가상 풋살장입니다. 예약 시간은 Firestore에 저장되지만 실제 대관이 아닙니다. '
                  '토스페이먼츠 테스트 결제창에서 인증을 체험하며 실제 금액은 청구되지 않습니다. '
                  '서버 결제 승인 및 실제 예약 확정은 수행하지 않습니다.'
                : '결제하기를 누르면 10분 동안 이 시간이 다른 사람에게 예약되지 않도록 잡아 둬요. '
                  '10분 안에 결제하지 않으면 자동으로 풀려요.',
                style: const TextStyle(fontSize: 13, height: 1.5, color: FmColors.textSecondary)),
            const SizedBox(height: FmSpace.l),
            LoadingButton(label: AppConfig.firebaseMode
                ? 'TEST 결제 체험 · ${Fmt.won(_total)} (청구 없음)'
                : '${Fmt.won(_total)} 결제하기', onPressed: _pay),
          ],
        ),
      ),
    );
  }
}
