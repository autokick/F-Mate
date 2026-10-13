import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import 'operator_venue_screen.dart';
import 'venue_apply_screen.dart';

String venueStatusLabel(String s) => switch (s) {
      'PENDING_REVIEW' => '심사 중',
      'VERIFIED' => '운영 중',
      'REJECTED' => '반려',
      'SUSPENDED' => '노출 중지',
      _ => s,
    };

/// 구장 운영자 홈: 내 구장 목록 + 입점 신청
class OperatorHomeScreen extends StatefulWidget {
  const OperatorHomeScreen({super.key});

  @override
  State<OperatorHomeScreen> createState() => _OperatorHomeScreenState();
}

class _OperatorHomeScreenState extends State<OperatorHomeScreen> {
  int _reload = 0;

  Future<void> _apply() async {
    if (!await requireVerified(context)) return;
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const VenueApplyScreen()));
    if (created == true && mounted) {
      await AppScope.read(context).session.refreshMe();
      setState(() => _reload++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!services.session.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('구장 운영자')),
        body: EmptyState(
          icon: Icons.storefront_outlined,
          title: '구장을 운영하고 계신가요?',
          message: '로그인 후 입점 신청을 하면 심사를 거쳐 F-Mate 에서 예약을 받을 수 있어요.',
          actionLabel: '로그인',
          onAction: () => requireLogin(context),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('구장 운영자')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _apply,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('입점 신청'),
      ),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_reload),
        load: services.operator.myVenues,
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(
          icon: Icons.storefront_outlined,
          title: '등록한 구장이 없어요',
          message: '입점 신청서와 사업자등록증을 제출하면 운영팀이 확인 후 승인해요.\n승인되면 운영시간과 요금을 설정해 예약을 받을 수 있어요.',
        ),
        builder: (context, venues, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(FmSpace.l),
            children: [
              for (final v in venues)
                Padding(
                  padding: const EdgeInsets.only(bottom: FmSpace.s),
                  child: FmCard(
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => OperatorVenueScreen(venueId: asInt(v['id'])))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(asStr(v['name']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text('${asStr(v['roadAddress'])} · 코트 ${asInt(v['courtCount'])}면',
                                  style: const TextStyle(fontSize: 13, color: FmColors.textSecondary)),
                              if (v['rejectionReason'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: FmSpace.xs),
                                  child: Text('반려 사유: ${v['rejectionReason']}',
                                      style: const TextStyle(fontSize: 13, color: FmColors.danger)),
                                ),
                            ],
                          ),
                        ),
                        StatusChip(
                          label: venueStatusLabel(asStr(v['verificationStatus'])),
                          color: asStr(v['verificationStatus']) == 'VERIFIED' ? FmColors.brandDark : FmColors.textSecondary,
                          background:
                              asStr(v['verificationStatus']) == 'VERIFIED' ? FmColors.brandSoft : FmColors.surfaceMuted,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
