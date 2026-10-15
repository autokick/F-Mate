import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/widgets.dart';
import '../booking/booking_screen.dart';
import '../reservations/reservation_result_screen.dart';
import '../venues/venues_screen.dart' show kAllFacilities;
import 'operating_hours_screen.dart';
import 'operator_home_screen.dart';
import 'slot_manage_screen.dart';
import 'venue_apply_screen.dart';

/// 구장 관리: 예약 현황 · 코트/운영시간 · 휴무 · 정보
class OperatorVenueScreen extends StatelessWidget {
  const OperatorVenueScreen({super.key, required this.venueId});

  final int venueId;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return AsyncBody<VenueDetail>(
      load: () => services.operator.venue(venueId),
      builder: (context, v, reload) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: Text(v.name),
            bottom: const TabBar(
              isScrollable: true,
              tabs: [Tab(text: '예약 현황'), Tab(text: '코트·운영시간'), Tab(text: '휴무·대관'), Tab(text: '구장 정보')],
            ),
          ),
          body: Column(
            children: [
              if (v.verificationStatus != 'VERIFIED')
                Container(
                  width: double.infinity,
                  color: v.verificationStatus == 'REJECTED' ? FmColors.dangerSoft : const Color(0xFFFEF3C7),
                  padding: const EdgeInsets.all(FmSpace.m),
                  child: Text(
                    switch (v.verificationStatus) {
                      'PENDING_REVIEW' => '운영팀 심사 중이에요. 승인 전에는 이용자에게 노출되지 않지만 운영시간은 미리 설정할 수 있어요.',
                      'REJECTED' => '반려되었어요: ${v.rejectionReason ?? ''}\n구장 정보 탭에서 보완하면 다시 심사를 받아요.',
                      _ => '현재 상태: ${venueStatusLabel(v.verificationStatus)}',
                    },
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              Expanded(
                child: TabBarView(children: [
                  _ReservationsTab(venue: v),
                  _CourtsTab(venue: v, onChanged: reload),
                  _ClosuresTab(venue: v),
                  _InfoTab(venue: v, onSaved: reload),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- 예약 현황
class _ReservationsTab extends StatefulWidget {
  const _ReservationsTab({required this.venue});

  final VenueDetail venue;

  @override
  State<_ReservationsTab> createState() => _ReservationsTabState();
}

class _ReservationsTabState extends State<_ReservationsTab> {
  final DateTime _today = dateOnly(DateTime.now());
  late DateTime _date = _today;
  int _reload = 0;

  Future<void> _cancel(Map<String, dynamic> r) async {
    final reason = await promptDialog(context, title: '구장 사정으로 취소', hint: '이용자에게 전달될 사유 (예: 시설 점검)');
    if (reason == null || reason.isEmpty || !mounted) return;
    final ok = await confirmDialog(context,
        title: '예약을 취소할까요?', message: '이용자에게 결제 금액 전액이 환불되고 알림이 가요.', confirm: '취소하기', destructive: true);
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).operator.cancelReservation(asStr(r['publicId']), reason, uuidV4());
      if (mounted) setState(() => _reload++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Column(
      children: [
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(FmSpace.s),
            itemCount: 30,
            separatorBuilder: (context, i) => const SizedBox(width: FmSpace.s),
            itemBuilder: (context, i) {
              final d = _today.add(Duration(days: i - 1));
              return DateChip(date: d, isToday: d == _today, selected: d == _date, onTap: () => setState(() => _date = d));
            },
          ),
        ),
        Expanded(
          child: AsyncBody<List<Map<String, dynamic>>>(
            key: ValueKey('${Fmt.isoDate(_date)}-$_reload'),
            load: () => services.operator.reservations(widget.venue.id, _date),
            isEmpty: (l) => l.isEmpty,
            empty: EmptyState(icon: Icons.event_note_outlined, title: '${Fmt.date(_date)} 예약이 없어요'),
            builder: (context, list, reload) => RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                children: [
                  for (final r in list)
                    ListTile(
                      title: Text('${Fmt.range(asTime(r['startsAt'])!, asTime(r['endsAt'])!)} · ${asStr(r['courtName'])}'),
                      subtitle: Text('${asStr(r['userNickname'])} · ${Fmt.won(asInt(r['totalAmount']))}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          reservationStatusChip(asStr(r['status'])),
                          if (asStr(r['status']) == 'CONFIRMED')
                            IconButton(
                              tooltip: '구장 사정으로 취소',
                              icon: const Icon(Icons.cancel_outlined, color: FmColors.danger),
                              onPressed: () => _cancel(r),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- 코트·운영시간
class _CourtsTab extends StatelessWidget {
  const _CourtsTab({required this.venue, required this.onChanged});

  final VenueDetail venue;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(FmSpace.l),
      children: [
        for (final c in venue.courts)
          Padding(
            padding: const EdgeInsets.only(bottom: FmSpace.s),
            child: FmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text('${c.name} · ${c.isIndoor ? '실내' : '실외'} · ${c.sizeClass.replaceAll('V', ':')}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Switch(
                      value: c.isActive,
                      onChanged: (on) async {
                        try {
                          await services.operator.updateCourt(c.id, {'isActive': on});
                          await onChanged();
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                    ),
                  ]),
                  if (!c.isActive) const Text('예약을 받지 않는 코트예요', style: TextStyle(fontSize: 12, color: FmColors.textSecondary)),
                  const SizedBox(height: FmSpace.s),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => OperatingHoursScreen(court: c))),
                        child: const Text('운영시간·요금'),
                      ),
                    ),
                    const SizedBox(width: FmSpace.s),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => SlotManageScreen(court: c))),
                        child: const Text('날짜별 슬롯'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showCourtDialog(context);
            if (d == null) return;
            try {
              await services.operator.addCourt(venue.id, d.toJson());
              await onChanged();
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('코트 추가'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- 휴무·대관
class _ClosuresTab extends StatefulWidget {
  const _ClosuresTab({required this.venue});

  final VenueDetail venue;

  @override
  State<_ClosuresTab> createState() => _ClosuresTabState();
}

class _ClosuresTabState extends State<_ClosuresTab> {
  int _reload = 0;

  Future<void> _add() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context, firstDate: dateOnly(now), lastDate: now.add(const Duration(days: 180)), initialDate: dateOnly(now));
    if (date == null || !mounted) return;
    final start = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 0, minute: 0), helpText: '시작 시각');
    if (start == null || !mounted) return;
    final end = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 23, minute: 59), helpText: '종료 시각');
    if (end == null || !mounted) return;
    final reason = await promptDialog(context, title: '사유 (예: 정기 휴무, 단체 대관)');
    if (!mounted) return;
    final s = DateTime(date.year, date.month, date.day, start.hour, start.minute);
    var e = DateTime(date.year, date.month, date.day, end.hour, end.minute);
    if (!e.isAfter(s)) e = e.add(const Duration(days: 1));
    try {
      await AppScope.read(context).operator.addClosure(widget.venue.id, startsAt: s, endsAt: e, reason: reason);
      if (mounted) setState(() => _reload++);
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _add, icon: const Icon(Icons.block_rounded), label: const Text('휴무 추가')),
      body: AsyncBody<List<Map<String, dynamic>>>(
        key: ValueKey(_reload),
        load: () => services.operator.closures(widget.venue.id),
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(icon: Icons.event_available_outlined, title: '예정된 휴무가 없어요', message: '휴무·대관 시간에는 예약을 받지 않아요.'),
        builder: (context, list, reload) => ListView(
          children: [
            for (final c in list)
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: Text('${Fmt.dateTime(asTime(c['startsAt'])!)} ~ ${Fmt.time(asTime(c['endsAt'])!)}'),
                subtitle: Text(asStr(c['reason'], '사유 없음')),
                trailing: IconButton(
                  tooltip: '휴무 삭제',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    try {
                      await services.operator.deleteClosure(widget.venue.id, asInt(c['id']));
                      if (mounted) setState(() => _reload++);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- 구장 정보
class _InfoTab extends StatefulWidget {
  const _InfoTab({required this.venue, required this.onSaved});

  final VenueDetail venue;
  final Future<void> Function() onSaved;

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  late final _desc = TextEditingController(text: widget.venue.description ?? '');
  late final _phone = TextEditingController(text: widget.venue.phone ?? '');
  late final _rules = TextEditingController(text: widget.venue.rules ?? '');
  late List<PolicyRule> _policy = List.of(widget.venue.cancelPolicy);
  late final List<String> _photoKeys = [
    for (final p in widget.venue.photos)
      if (p.objectKey != null) p.objectKey!,
  ];
  late final Map<String, String?> _photoUrls = {
    for (final p in widget.venue.photos)
      if (p.objectKey != null) p.objectKey!: p.url,
  };
  final List<XFile> _newPhotos = [];
  late final Set<String> _facilities = {for (final f in widget.venue.facilities) f.code};
  double? _uploading;

  @override
  void didUpdateWidget(covariant _InfoTab old) {
    super.didUpdateWidget(old);
    if (!identical(old.venue, widget.venue)) {
      // 저장 후 다시 불러온 구장 정보로 사진 목록을 맞춘다
      _photoKeys
        ..clear()
        ..addAll([
          for (final p in widget.venue.photos)
            if (p.objectKey != null) p.objectKey!,
        ]);
      _photoUrls
        ..clear()
        ..addAll({
          for (final p in widget.venue.photos)
            if (p.objectKey != null) p.objectKey!: p.url,
        });
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2048, maxHeight: 2048);
      if (picked.isEmpty) return;
      setState(() {
        _newPhotos.addAll(picked);
        final room = 20 - _photoKeys.length;
        if (_newPhotos.length > room) _newPhotos.removeRange(room.clamp(0, _newPhotos.length), _newPhotos.length);
      });
    } catch (_) {
      if (mounted) showFmSnack(context, '사진을 불러오지 못했어요. 사진 접근 권한을 확인해 주세요');
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _phone.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppScope.read(context);
    try {
      var keys = List.of(_photoKeys);
      if (_newPhotos.isNotEmpty) {
        setState(() => _uploading = 0);
        final uploaded = await s.media.uploadFiles('VENUE_PHOTO', _newPhotos, onProgress: (p) {
          if (mounted) setState(() => _uploading = p);
        });
        keys = [...keys, ...uploaded];
      }
      _photoKeys
        ..clear()
        ..addAll(keys);
      await s.operator.updateVenue(widget.venue.id, {
        'description': _desc.text,
        'phone': _phone.text,
        'rules': _rules.text,
        'cancelPolicy': [for (final r in _policy) {'hoursBefore': r.hoursBefore, 'refundPercent': r.refundPercent}],
        'facilities': _facilities.toList(),
        'photoKeys': keys,
      });
      if (mounted) {
        setState(() {
          _uploading = null;
          _newPhotos.clear();
        });
      }
      await widget.onSaved();
      if (mounted) showFmSnack(context, '저장했어요');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FmSpace.l),
      children: [
        Row(children: [
          Text('사진 ${_photoKeys.length + _newPhotos.length}/20',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const Spacer(),
          TextButton.icon(
            onPressed: _photoKeys.length + _newPhotos.length >= 20 ? null : _pickPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
            label: const Text('사진 추가'),
          ),
        ]),
        const Text('첫 번째 사진이 목록의 대표 사진이 돼요. 길게 눌러 맨 앞으로 옮길 수 있어요.',
            style: TextStyle(fontSize: 12, color: FmColors.textSecondary)),
        const SizedBox(height: FmSpace.s),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _photoKeys.length; i++)
                _PhotoBox(
                  first: i == 0,
                  onRemove: () => setState(() => _photoKeys.removeAt(i)),
                  onMakeFirst: () => setState(() => _photoKeys.insert(0, _photoKeys.removeAt(i))),
                  child: _photoUrls[_photoKeys[i]] == null
                      ? Container(color: FmColors.photoPlaceholder)
                      : Image.network(_photoUrls[_photoKeys[i]]!, fit: BoxFit.cover,
                          errorBuilder: (context, e, st) => Container(color: FmColors.photoPlaceholder)),
                ),
              for (var i = 0; i < _newPhotos.length; i++)
                _PhotoBox(
                  first: _photoKeys.isEmpty && i == 0,
                  isNew: true,
                  onRemove: () => setState(() => _newPhotos.removeAt(i)),
                  child: Image.file(File(_newPhotos[i].path), fit: BoxFit.cover),
                ),
            ],
          ),
        ),
        if (_uploading != null) ...[
          const SizedBox(height: FmSpace.s),
          LinearProgressIndicator(value: _uploading),
        ],
        const SizedBox(height: FmSpace.l),
        const Text('편의시설', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: FmSpace.s),
        Wrap(
          spacing: FmSpace.s,
          runSpacing: FmSpace.s,
          children: [
            for (final e in kAllFacilities.entries)
              FilterChip(
                label: Text(e.value),
                selected: _facilities.contains(e.key),
                onSelected: (on) => setState(() => on ? _facilities.add(e.key) : _facilities.remove(e.key)),
              ),
          ],
        ),
        const SizedBox(height: FmSpace.xl),
        TextField(controller: _desc, maxLines: 4, maxLength: 1000, decoration: fmInputDecoration(label: '구장 소개')),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: fmInputDecoration(label: '전화번호')),
        const SizedBox(height: FmSpace.m),
        TextField(controller: _rules, maxLines: 4, maxLength: 2000, decoration: fmInputDecoration(label: '이용 규칙')),
        SectionTitle('취소·환불 정책', trailing: TextButton(
          onPressed: () => setState(() => _policy = [..._policy, PolicyRule(48, 80)]..sort((a, b) => b.hoursBefore.compareTo(a.hoursBefore))),
          child: const Text('구간 추가'),
        )),
        for (var i = 0; i < _policy.length; i++)
          Row(children: [
            const Text('이용 '),
            SizedBox(
              width: 64,
              child: TextFormField(
                initialValue: '${_policy[i].hoursBefore}',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) => _policy[i] = PolicyRule(int.tryParse(v) ?? 0, _policy[i].refundPercent),
              ),
            ),
            const Text('시간 전까지 '),
            SizedBox(
              width: 56,
              child: TextFormField(
                initialValue: '${_policy[i].refundPercent}',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) => _policy[i] = PolicyRule(_policy[i].hoursBefore, (int.tryParse(v) ?? 0).clamp(0, 100)),
              ),
            ),
            const Text('% 환불'),
            const Spacer(),
            IconButton(
                tooltip: '구간 삭제',
                icon: const Icon(Icons.remove_circle_outline_rounded),
                onPressed: _policy.length <= 1 ? null : () => setState(() => _policy.removeAt(i))),
          ]),
        const SizedBox(height: FmSpace.s),
        const Text('기존 예약에는 예약할 당시의 정책이 그대로 적용돼요. 이름·주소 변경은 운영팀에 요청해 주세요.',
            style: TextStyle(fontSize: 12, color: FmColors.textSecondary)),
        const SizedBox(height: FmSpace.l),
        LoadingButton(label: '저장', onPressed: _save),
      ],
    );
  }
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.child, required this.onRemove, this.onMakeFirst, this.first = false, this.isNew = false});

  final Widget child;
  final VoidCallback onRemove;
  final VoidCallback? onMakeFirst;
  final bool first;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: FmSpace.s),
      child: GestureDetector(
        onLongPress: onMakeFirst,
        child: SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(FmRadius.control), child: child),
              if (first || isNew)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Text(first ? '대표' : '새 사진',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              Positioned(
                right: 2,
                top: 2,
                child: Semantics(
                  button: true,
                  label: '사진 빼기',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                    ),
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
