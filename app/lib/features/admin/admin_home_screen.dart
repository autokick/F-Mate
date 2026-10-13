import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import '../operator/operator_home_screen.dart';
import '../reservations/reservation_result_screen.dart';

/// 운영 관리 (MODERATOR 이상). 결제·구장 승인·권한 변경은 서버가 ADMIN 만 허용한다.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final isAdmin = s.session.me?.isAdmin == true;
    Widget menu(IconData icon, String title, Widget page, {bool adminOnly = false}) => ListTile(
          enabled: !adminOnly || isAdmin,
          leading: Icon(icon),
          title: Text(title),
          subtitle: adminOnly && !isAdmin ? const Text('관리자 전용') : null,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('운영 관리')),
      body: AsyncBody<Map<String, dynamic>>(
        load: s.admin.dashboard,
        builder: (context, d, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.only(bottom: FmSpace.xl),
            children: [
              Padding(
                padding: const EdgeInsets.all(FmSpace.l),
                child: Wrap(
                  spacing: FmSpace.s,
                  runSpacing: FmSpace.s,
                  children: [
                    _Stat('전체 회원', '${asInt(d['users_total'])}', sub: '7일 +${asInt(d['users_new_7d'])}'),
                    _Stat('운영 구장', '${asInt(d['venues_verified'])}', sub: '심사 대기 ${asInt(d['venues_pending'])}', alert: asInt(d['venues_pending']) > 0),
                    _Stat('오늘 예약', '${asInt(d['reservations_today'])}', sub: '7일 ${asInt(d['reservations_7d'])}'),
                    _Stat('7일 결제', Fmt.won(asInt(d['approved_amount_7d']))),
                    _Stat('미처리 신고', '${asInt(d['reports_open'])}', alert: asInt(d['reports_open']) > 0),
                    _Stat('환불 대기', '${asInt(d['refunds_pending'])}', sub: '반복 실패 ${asInt(d['refunds_failing'])}', alert: asInt(d['refunds_failing']) > 0),
                    _Stat('결제 확인 지연', '${asInt(d['payments_stuck'])}', alert: asInt(d['payments_stuck']) > 0),
                    _Stat('서버 오류(24h)', '${asInt(d['errors_24h'])}', alert: asInt(d['errors_24h']) > 0),
                  ],
                ),
              ),
              menu(Icons.storefront_outlined, '구장 입점 심사', const AdminVenuesScreen()),
              menu(Icons.flag_outlined, '신고 처리', const AdminReportsScreen()),
              menu(Icons.people_outline_rounded, '회원 관리', const AdminUsersScreen()),
              menu(Icons.event_note_outlined, '예약 관리', const AdminReservationsScreen()),
              menu(Icons.payments_outlined, '결제·환불', const AdminPaymentsScreen(), adminOnly: true),
              menu(Icons.receipt_long_outlined, '감사·오류 로그', const AdminLogsScreen(), adminOnly: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.sub, this.alert = false});

  final String label;
  final String value;
  final String? sub;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - FmSpace.l * 2 - FmSpace.s) / 2,
      child: FmCard(
        color: alert ? FmColors.dangerSoft : Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: FmColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: alert ? FmColors.danger : FmColors.textPrimary)),
          if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12, color: FmColors.textSecondary)),
        ]),
      ),
    );
  }
}

// ============================================================ 구장 심사
class AdminVenuesScreen extends StatefulWidget {
  const AdminVenuesScreen({super.key});

  @override
  State<AdminVenuesScreen> createState() => _AdminVenuesScreenState();
}

class _AdminVenuesScreenState extends State<AdminVenuesScreen> {
  String? _status = 'PENDING_REVIEW';
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('구장 입점 심사')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(FmSpace.s),
          child: Row(children: [
            for (final (label, value) in const [('심사 대기', 'PENDING_REVIEW'), ('운영 중', 'VERIFIED'), ('반려', 'REJECTED'), ('중지', 'SUSPENDED'), ('전체', null)])
              Padding(
                padding: const EdgeInsets.only(right: FmSpace.s),
                child: ChoiceChip(label: Text(label), selected: _status == value, onSelected: (_) => setState(() => _status = value)),
              ),
          ]),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey('$_status-$_reload'),
            load: () => s.admin.list('venues', query: {'status': _status}),
            isEmpty: (l) => l.isEmpty,
            empty: const EmptyState(icon: Icons.inbox_outlined, title: '해당하는 구장이 없어요'),
            builder: (context, list, reload) => ListView(children: [
              for (final v in list)
                ListTile(
                  title: Text(asStr(v['name'])),
                  subtitle: Text('${asStr(v['road_address'])}\n운영자: ${asStr(v['owners'], '-')} · 사업자 ${asStr(v['business_reg_no'], '-')}'),
                  isThreeLine: true,
                  trailing: Text(venueStatusLabel(asStr(v['verification_status']))),
                  onTap: () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => AdminVenueDetailScreen(venueId: asInt(v['id']))));
                    if (mounted) setState(() => _reload++);
                  },
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class AdminVenueDetailScreen extends StatelessWidget {
  const AdminVenueDetailScreen({super.key, required this.venueId});

  final int venueId;

  Future<void> _decide(BuildContext context, String decision) async {
    String? reason;
    if (decision != 'APPROVE') {
      reason = await promptDialog(context, title: decision == 'REJECT' ? '반려 사유 (운영자에게 전달)' : '중지 사유');
      if (reason == null || reason.isEmpty) return;
    } else if (!await confirmDialog(context, title: '입점을 승인할까요?', message: '서류와 현장 사진을 확인했는지 다시 한번 확인해 주세요.', confirm: '승인')) {
      return;
    }
    if (!context.mounted) return;
    try {
      await AppScope.read(context).admin.action('venues/$venueId/decision', {'decision': decision, 'reason': reason});
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('구장 심사')),
      body: AsyncBody<Map<String, dynamic>>(
        load: () => s.admin.one('venues/$venueId'),
        builder: (context, v, reload) => ListView(padding: const EdgeInsets.all(FmSpace.l), children: [
          Text(asStr(v['name']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: FmSpace.s),
          InfoRow('상태', venueStatusLabel(asStr(v['verification_status']))),
          InfoRow('주소', '${asStr(v['road_address'])} ${asStr(v['detail_address'])}'),
          InfoRow('좌표', '${v['latitude']}, ${v['longitude']}'),
          InfoRow('지역 코드', asStr(v['region_code'])),
          InfoRow('전화', asStr(v['phone'], '-')),
          InfoRow('사업자번호', asStr(v['business_reg_no'], '-')),
          if (v['rejection_reason'] != null) InfoRow('반려 사유', asStr(v['rejection_reason'])),
          const SectionTitle('제출 서류'),
          for (final d in asList(v['documents']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(asStr(asMap(d)['kind'])),
              subtitle: const Text('10분 동안 열람 가능한 링크'),
              onTap: asMap(d)['viewUrl'] == null
                  ? null
                  : () => launchUrl(Uri.parse(asStr(asMap(d)['viewUrl'])), mode: LaunchMode.externalApplication),
            ),
          const SectionTitle('운영자'),
          for (final o in asList(v['operators']))
            InfoRow(asStr(asMap(o)['role']), '${asStr(asMap(o)['nickname'])} (${asStr(asMap(o)['email'], '-')})'),
          const SectionTitle('코트'),
          for (final c in asList(v['courts']))
            InfoRow(asStr(asMap(c)['name']), '${asMap(c)['is_indoor'] == true ? '실내' : '실외'} · ${asStr(asMap(c)['size_class'])}'),
          const SizedBox(height: FmSpace.xl),
          Row(children: [
            Expanded(child: FilledButton(onPressed: () => _decide(context, 'APPROVE'), child: const Text('승인'))),
            const SizedBox(width: FmSpace.s),
            Expanded(child: OutlinedButton(onPressed: () => _decide(context, 'REJECT'), child: const Text('반려'))),
          ]),
          TextButton(onPressed: () => _decide(context, 'SUSPEND'), child: const Text('노출 중지', style: TextStyle(color: FmColors.danger))),
        ]),
      ),
    );
  }
}

// ============================================================ 신고
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  int _reload = 0;

  Future<void> _resolve(Map<String, dynamic> r) async {
    final type = asStr(r['target_type']);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: const Text('문제없음 (신고 기각, 숨김 해제)'), onTap: () => Navigator.of(ctx).pop('DISMISS')),
          if (type == 'POST' || type == 'COMMENT') ListTile(title: const Text('숨김'), onTap: () => Navigator.of(ctx).pop('HIDE')),
          if (type != 'USER' && type != 'VENUE')
            ListTile(title: const Text('삭제', style: TextStyle(color: FmColors.danger)), onTap: () => Navigator.of(ctx).pop('DELETE')),
          if (type == 'VENUE') ListTile(title: const Text('구장 노출 중지'), onTap: () => Navigator.of(ctx).pop('HIDE')),
          if (r['owner_user_id'] != null)
            ListTile(title: const Text('작성자 7일 정지 + 콘텐츠 삭제'), onTap: () => Navigator.of(ctx).pop('SUSPEND')),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final note = await promptDialog(context, title: '처리 메모 (작성자에게 안내될 수 있어요)');
    if (!mounted) return;
    final body = <String, dynamic>{'action': action == 'SUSPEND' ? (type == 'USER' ? 'DISMISS' : 'DELETE') : action, 'note': note};
    if (action == 'SUSPEND') {
      body['action'] = type == 'USER' ? 'HIDE' : 'DELETE';
      body['sanction'] = {'kind': 'SUSPENSION', 'days': 7, 'reason': note == null || note.isEmpty ? '운영정책 위반' : note};
    }
    try {
      await AppScope.read(context).admin.action('reports/$type/${asInt(r['target_id'])}/resolve', body);
      if (mounted) setState(() => _reload++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('신고 처리')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_reload),
        load: () => s.admin.list('reports'),
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.verified_user_outlined, title: '처리할 신고가 없어요'),
        builder: (context, list, reload) => ListView(children: [
          for (final r in list)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: asInt(r['reporter_count']) >= 5 ? FmColors.dangerSoft : FmColors.surfaceMuted,
                child: Text('${asInt(r['reporter_count'])}'),
              ),
              title: Text('${asStr(r['target_type'])} #${asInt(r['target_id'])} · ${asStr(r['reasons'])}'),
              subtitle: Text(asStr(r['preview'], '(내용 없음)'), maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => _resolve(r),
            ),
        ]),
      ),
    );
  }
}

// ============================================================ 회원
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('회원 관리')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(FmSpace.m),
          child: TextField(
            decoration: fmInputDecoration(label: '이메일·닉네임 검색', prefixIcon: const Icon(Icons.search_rounded)),
            onSubmitted: (v) => setState(() => _q = v.trim()),
          ),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey(_q),
            load: () => s.admin.list('users', query: {'q': _q}),
            isEmpty: (l) => l.isEmpty,
            empty: const EmptyState(icon: Icons.person_search_outlined, title: '검색 결과가 없어요'),
            builder: (context, list, reload) => ListView(children: [
              for (final u in list)
                ListTile(
                  title: Text('${asStr(u['nickname'], '(프로필 없음)')} · ${asStr(u['role'])}'),
                  subtitle: Text('${asStr(u['email'], '(이메일 없음)')} · ${asStr(u['status'])} · 신고 ${asInt(u['reported_count'])}'),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => AdminUserScreen(userId: asInt(u['id'])))),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class AdminUserScreen extends StatefulWidget {
  const AdminUserScreen({super.key, required this.userId});

  final int userId;

  @override
  State<AdminUserScreen> createState() => _AdminUserScreenState();
}

class _AdminUserScreenState extends State<AdminUserScreen> {
  int _reload = 0;

  Future<void> _sanction(String kind) async {
    final reason = await promptDialog(context, title: '사유 (회원에게 안내돼요)');
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      await AppScope.read(context).admin.action('users/${widget.userId}/sanctions',
          {'kind': kind, 'days': kind == 'SUSPENSION' ? 7 : null, 'reason': reason});
      if (mounted) setState(() => _reload++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _lift() async {
    try {
      await AppScope.read(context).admin.action('users/${widget.userId}/sanctions/lift', {'reason': '관리자 해제'});
      if (mounted) setState(() => _reload++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final isAdmin = s.session.me?.isAdmin == true;
    return Scaffold(
      appBar: AppBar(title: const Text('회원 상세')),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_reload),
        load: () => s.admin.one('users/${widget.userId}'),
        builder: (context, u, reload) => ListView(padding: const EdgeInsets.all(FmSpace.l), children: [
          InfoRow('닉네임', asStr(u['nickname'], '-')),
          InfoRow('이메일', asStr(u['email'], '-')),
          InfoRow('권한', asStr(u['role'])),
          InfoRow('상태', '${asStr(u['status'])}${u['suspended_until'] != null ? ' (~${asStr(u['suspended_until']).substring(0, 10)})' : ''}'),
          InfoRow('가입일', asStr(u['created_at']).length >= 10 ? asStr(u['created_at']).substring(0, 10) : '-'),
          const SectionTitle('제재 이력'),
          if (asList(u['sanctions']).isEmpty) const Text('없음', style: TextStyle(color: FmColors.textSecondary)),
          for (final x in asList(u['sanctions'])) InfoRow(asStr(asMap(x)['kind']), asStr(asMap(x)['reason'])),
          const SectionTitle('조치'),
          Wrap(spacing: FmSpace.s, runSpacing: FmSpace.s, children: [
            OutlinedButton(onPressed: () => _sanction('WARNING'), child: const Text('경고')),
            OutlinedButton(onPressed: () => _sanction('SUSPENSION'), child: const Text('7일 정지')),
            if (isAdmin)
              OutlinedButton(
                  onPressed: () => _sanction('PERMANENT_BAN'),
                  child: const Text('영구 정지', style: TextStyle(color: FmColors.danger))),
            if (asStr(u['status']) == 'SUSPENDED') FilledButton(onPressed: _lift, child: const Text('제재 해제')),
          ]),
          if (isAdmin) ...[
            const SectionTitle('권한 변경 (관리자)'),
            Wrap(spacing: FmSpace.s, children: [
              for (final role in const ['USER', 'MODERATOR', 'ADMIN'])
                ChoiceChip(
                  label: Text(role),
                  selected: asStr(u['role']) == role,
                  onSelected: (_) async {
                    if (!await confirmDialog(context, title: '$role 권한으로 바꿀까요?', confirm: '변경')) return;
                    if (!context.mounted) return;
                    try {
                      await s.admin.action('users/${widget.userId}/role', {'role': role});
                      if (mounted) setState(() => _reload++);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ============================================================ 예약
class AdminReservationsScreen extends StatefulWidget {
  const AdminReservationsScreen({super.key});

  @override
  State<AdminReservationsScreen> createState() => _AdminReservationsScreenState();
}

class _AdminReservationsScreenState extends State<AdminReservationsScreen> {
  String _q = '';
  int _reload = 0;

  Future<void> _cancel(Map<String, dynamic> r) async {
    final reason = await promptDialog(context, title: '운영팀 취소 사유 (전액 환불)');
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      await AppScope.read(context).admin.action('reservations/${asStr(r['public_id'])}/cancel', {'reason': reason});
      if (mounted) setState(() => _reload++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final isAdmin = s.session.me?.isAdmin == true;
    return Scaffold(
      appBar: AppBar(title: const Text('예약 관리')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(FmSpace.m),
          child: TextField(
            decoration: fmInputDecoration(label: '예약 번호(UUID) 검색', prefixIcon: const Icon(Icons.search_rounded)),
            onSubmitted: (v) => setState(() => _q = v.trim()),
          ),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey('$_q-$_reload'),
            load: () => s.admin.list('reservations', query: {'q': _q}),
            isEmpty: (l) => l.isEmpty,
            empty: const EmptyState(icon: Icons.event_note_outlined, title: '예약이 없어요'),
            builder: (context, list, reload) => ListView(children: [
              for (final r in list)
                ListTile(
                  title: Text('${asStr(r['venue'])} ${asStr(r['court'])}'),
                  subtitle: Text('${asTime(r['starts_at']) == null ? '' : Fmt.dateTime(asTime(r['starts_at'])!)} · '
                      '${asStr(r['user_nickname'])} · ${Fmt.won(asInt(r['total_amount']))}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    reservationStatusChip(asStr(r['status'])),
                    if (isAdmin && (asStr(r['status']) == 'CONFIRMED' || asStr(r['status']) == 'PENDING_PAYMENT'))
                      IconButton(tooltip: '운영팀 취소', icon: const Icon(Icons.cancel_outlined), onPressed: () => _cancel(r)),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ============================================================ 결제·환불 (ADMIN)
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('결제·환불')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(FmSpace.s),
          child: Row(children: [
            for (final (label, value) in const [('전체', null), ('확인 지연', 'IN_PROGRESS'), ('완료', 'DONE'), ('부분 환불', 'PARTIAL_CANCELED'), ('환불', 'CANCELED'), ('실패', 'ABORTED')])
              Padding(
                padding: const EdgeInsets.only(right: FmSpace.s),
                child: ChoiceChip(label: Text(label), selected: _status == value, onSelected: (_) => setState(() => _status = value)),
              ),
          ]),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey(_status),
            load: () => s.admin.list('payments', query: {'status': _status}),
            isEmpty: (l) => l.isEmpty,
            empty: const EmptyState(icon: Icons.payments_outlined, title: '결제 내역이 없어요'),
            builder: (context, list, reload) => ListView(children: [
              for (final p in list)
                ListTile(
                  title: Text('${asStr(p['order_id'])} · ${asStr(p['status'])}'),
                  subtitle: Text('${asStr(p['mode'])} · ${Fmt.won(asInt(p['amount']))}${p['failure_code'] != null ? ' · ${p['failure_code']}' : ''}'),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => AdminPaymentScreen(orderId: asStr(p['order_id'])))),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class AdminPaymentScreen extends StatefulWidget {
  const AdminPaymentScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<AdminPaymentScreen> createState() => _AdminPaymentScreenState();
}

class _AdminPaymentScreenState extends State<AdminPaymentScreen> {
  int _reload = 0;

  Future<void> _act(String path) async {
    try {
      await AppScope.read(context).admin.action(path, null);
      if (mounted) {
        showFmSnack(context, '처리했어요');
        setState(() => _reload++);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('결제 상세')),
      body: AsyncBody<Map<String, dynamic>>(
        key: ValueKey(_reload),
        load: () => s.admin.one('payments/${widget.orderId}'),
        builder: (context, p, reload) => ListView(padding: const EdgeInsets.all(FmSpace.l), children: [
          InfoRow('주문번호', asStr(p['order_id'])),
          InfoRow('모드', asStr(p['mode'])),
          InfoRow('상태', asStr(p['status'])),
          InfoRow('요청 금액', Fmt.won(asInt(p['amount']))),
          InfoRow('승인 금액', p['approved_amount'] == null ? '-' : Fmt.won(asInt(p['approved_amount']))),
          InfoRow('잔액', p['balance_amount'] == null ? '-' : Fmt.won(asInt(p['balance_amount']))),
          InfoRow('예약', asStr(p['reservation_public_id'])),
          if (asStr(p['status']) == 'IN_PROGRESS')
            FilledButton(onPressed: () => _act('payments/${widget.orderId}/reconcile'), child: const Text('토스에 결제 상태 조회해 확정')),
          const SectionTitle('환불'),
          for (final r in asList(p['refunds']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${Fmt.won(asInt(asMap(r)['amount']))} · ${asStr(asMap(r)['status'])} · 시도 ${asInt(asMap(r)['attempt_count'])}회'),
              subtitle: Text('${asStr(asMap(r)['reason'])}${asMap(r)['failure_code'] != null ? '\n실패: ${asMap(r)['failure_code']} ${asStr(asMap(r)['failure_message'])}' : ''}'),
              trailing: asStr(asMap(r)['status']) == 'REQUESTED'
                  ? TextButton(onPressed: () => _act('refunds/${asInt(asMap(r)['id'])}/retry'), child: const Text('재시도'))
                  : null,
            ),
          const SectionTitle('처리 기록'),
          for (final l in asList(p['auditLogs']))
            InfoRow(asStr(asMap(l)['action']),
                '${asStr(asMap(l)['outcome'])} ${asStr(asMap(l)['provider_code'])} ${asStr(asMap(l)['created_at']).replaceAll('T', ' ').split('.').first}'),
        ]),
      ),
    );
  }
}

// ============================================================ 로그 (ADMIN)
class AdminLogsScreen extends StatelessWidget {
  const AdminLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('감사·오류 로그'),
          bottom: const TabBar(tabs: [Tab(text: '관리자 작업'), Tab(text: '서버 오류')]),
        ),
        body: TabBarView(children: [
          AsyncBody<List<Map<String, dynamic>>>(
            load: () => s.admin.list('audit-logs'),
            isEmpty: (l) => l.isEmpty,
            empty: const EmptyState(icon: Icons.history_rounded, title: '기록이 없어요'),
            builder: (context, list, reload) => ListView(children: [
              for (final a in list)
                ListTile(
                  title: Text('${asStr(a['action'])} · ${asStr(a['target_type'])} #${asStr(a['target_id'])}'),
                  subtitle: Text('${asStr(a['actor_nickname'])}(${asStr(a['actor_role'])}) · ${asStr(a['reason'])}\n'
                      '${asStr(a['created_at']).replaceAll('T', ' ').split('.').first}'),
                  isThreeLine: true,
                ),
            ]),
          ),
          AsyncBody<List<Map<String, dynamic>>>(
            load: () => s.admin.list('error-logs'),
            isEmpty: (l) => l.isEmpty,
            empty: const EmptyState(icon: Icons.check_circle_outline_rounded, title: '오류가 없어요'),
            builder: (context, list, reload) => ListView(children: [
              for (final e in list)
                ListTile(
                  title: Text('${asStr(e['method'])} ${asStr(e['path'])}'),
                  subtitle: Text('${asStr(e['error_class']).split('.').last}: ${asStr(e['message'])}\n'
                      'requestId ${asStr(e['request_id'])} · ${asStr(e['created_at']).replaceAll('T', ' ').split('.').first}'),
                  isThreeLine: true,
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
