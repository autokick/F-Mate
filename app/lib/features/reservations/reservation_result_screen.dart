import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'reservation_detail_screen.dart';

/// 결제 후 결과. 결과를 확정하지 못했으면(응답 지연) "확인 중"으로 안내 — 중복 결제는 서버가 막는다.
class ReservationResultScreen extends StatelessWidget {
  const ReservationResultScreen({super.key, required this.reservationId, required this.status});

  final String reservationId;
  final PaymentStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final confirmed = s?.isConfirmed == true;
    final pending = s == null || s.isPending;
    final IconData icon;
    final String title;
    final String message;
    final Color color;
    if (confirmed) {
      icon = Icons.check_circle_rounded;
      title = '예약이 확정되었어요';
      message = '경기 시작 전에 구장 이용 규칙을 확인해 주세요.';
      color = FmColors.brandDark;
    } else if (pending) {
      icon = Icons.hourglass_top_rounded;
      title = '결제 결과를 확인하고 있어요';
      message = '확정되면 알림으로 알려 드려요. 같은 예약에 두 번 결제되지 않으니 안심하세요.';
      color = const Color(0xFF92400E);
    } else {
      icon = Icons.error_outline_rounded;
      title = '결제가 완료되지 않았어요';
      message = s.failureMessage ?? '결제가 취소되었거나 실패했어요. 결제 시간이 남아 있으면 내 예약에서 다시 결제할 수 있어요.';
      color = FmColors.danger;
    }
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('예약 결과')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FmSpace.xl),
          child: Column(
            children: [
              const Spacer(),
              Icon(icon, size: 80, color: color),
              const SizedBox(height: FmSpace.l),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: FmSpace.s),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.5, color: FmColors.textSecondary)),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => ReservationDetailScreen(publicId: reservationId))),
                child: const Text('예약 내역 보기'),
              ),
              const SizedBox(height: FmSpace.s),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 예약 상태 문구 + 색 칩
Widget reservationStatusChip(String status) => StatusChip.reservation(reservationStatusLabel(status), status);
