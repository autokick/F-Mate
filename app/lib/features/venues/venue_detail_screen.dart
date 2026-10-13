import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/report_sheet.dart';
import '../../shared/court_illustration.dart';
import '../../shared/widgets.dart';
import '../booking/booking_screen.dart';
import '../reservations/reservation_confirm_screen.dart';

/// 구장 상세 + 날짜별 실제 예약 가능 시간 선택
class VenueDetailScreen extends StatefulWidget {
  const VenueDetailScreen({super.key, required this.venueId, this.initialDate, this.demoFor});

  final int venueId;
  final DateTime? initialDate;

  /// "예약 체험"으로 들어온 경우 실제 구장 이름. 시연용 시간표라는 안내를 맨 위에 띄운다.
  final String? demoFor;

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  late DateTime _date = dateOnly(widget.initialDate ?? DateTime.now());
  final DateTime _today = dateOnly(DateTime.now());
  int _photo = 0;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('구장 정보'),
        actions: [
          IconButton(
            tooltip: '구장 정보 신고',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () {
              if (requireLogin(context)) showReportSheet(context, 'VENUE', widget.venueId);
            },
          ),
        ],
      ),
      body: AsyncBody<VenueDetail>(
        load: () => services.venues.detail(widget.venueId),
        builder: (context, v, reload) => ListView(
          padding: const EdgeInsets.only(bottom: FmSpace.xxl),
          children: [
            if (widget.demoFor != null)
              Container(
                key: const Key('demo_booking_banner'),
                color: const Color(0xFFFFF7ED),
                padding: const EdgeInsets.symmetric(horizontal: FmSpace.l, vertical: FmSpace.m),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 20, color: Color(0xFF9A3412)),
                    const SizedBox(width: FmSpace.s),
                    Expanded(
                      child: Text(
                        '예약 체험 중 · "${widget.demoFor}"은(는) 아직 F-Mate에 등록되지 않아, '
                        '가까운 구장의 시연용 시간표로 예약 과정을 보여드려요. 실제 예약이 아니에요.',
                        style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF9A3412)),
                      ),
                    ),
                  ],
                ),
              ),
            _photos(v),
            Padding(
              padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.l, FmSpace.l, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: FmSpace.xs),
                  InkWell(
                    onLongPress: () async {
                      await Clipboard.setData(ClipboardData(text: v.roadAddress));
                      if (context.mounted) showFmSnack(context, '주소를 복사했어요');
                    },
                    child: Text('${v.roadAddress}${v.detailAddress == null ? '' : ' ${v.detailAddress}'}',
                        style: const TextStyle(fontSize: 14, color: FmColors.textSecondary)),
                  ),
                  if (v.isPublicData) ...[
                    const SizedBox(height: FmSpace.m),
                    Container(
                      key: const Key('public_data_notice'),
                      padding: const EdgeInsets.all(FmSpace.m),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(FmRadius.control),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.verified_outlined, size: 20, color: Color(0xFF1D4ED8)),
                          SizedBox(width: FmSpace.s),
                          Expanded(
                            child: Text(
                              '공공데이터에 등록된 실제 시설이에요. 아직 F-Mate 제휴 전이라 '
                              '사진은 일러스트, 편의시설·시간표·가격은 시연용 예시예요. 실제로 예약되지 않아요.\n'
                              '정보 출처: 국민체육진흥공단 전국체육시설 정보(공공데이터포털)',
                              style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF1E3A8A)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (v.description != null) ...[
                    const SizedBox(height: FmSpace.m),
                    Text(v.description!, style: const TextStyle(fontSize: 15, height: 1.5)),
                  ],
                  const SizedBox(height: FmSpace.m),
                  Row(
                    children: [
                      if (v.phone != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => launchUrl(Uri(scheme: 'tel', path: v.phone)),
                            icon: const Icon(Icons.call_outlined, size: 18),
                            label: const Text('전화'),
                          ),
                        ),
                      if (v.phone != null) const SizedBox(width: FmSpace.s),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => launchUrl(
                              Uri.parse('https://map.kakao.com/link/map/${Uri.encodeComponent(v.name)},${v.latitude},${v.longitude}'),
                              mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('지도 앱'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (AppConfig.mapsEnabled && services.features.value.maps)
              Padding(
                padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.m, FmSpace.l, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FmRadius.card),
                  child: SizedBox(
                    height: 160,
                    child: GoogleMap(
                      liteModeEnabled: true,
                      initialCameraPosition: CameraPosition(target: LatLng(v.latitude, v.longitude), zoom: 15),
                      markers: {Marker(markerId: MarkerId('v${v.id}'), position: LatLng(v.latitude, v.longitude))},
                    ),
                  ),
                ),
              ),
            if (v.facilities.isNotEmpty) ...[
              SectionTitle('편의시설',
                  trailing: v.isPublicData
                      ? const Text('시연용 예시', style: TextStyle(fontSize: 12, color: FmColors.textSecondary))
                      : null),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
                child: Wrap(
                  spacing: FmSpace.s,
                  runSpacing: FmSpace.s,
                  children: [for (final f in v.facilities) Chip(label: Text(f.label))],
                ),
              ),
            ],
            const SectionTitle('코트'),
            for (final c in v.courts)
              ListTile(
                dense: true,
                leading: Icon(c.isIndoor ? Icons.roofing_rounded : Icons.wb_sunny_outlined, color: FmColors.brandDark),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  c.isIndoor ? '실내' : '실외',
                  kSurfaces[c.surface] ?? c.surface,
                  c.sizeClass.replaceAll('V', ':'),
                  if (c.widthM != null && c.lengthM != null) '${c.widthM}×${c.lengthM}m',
                ].join(' · ')),
              ),
            const SectionTitle('날짜 선택'),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
                itemCount: 14,
                separatorBuilder: (context, index) => const SizedBox(width: FmSpace.s),
                itemBuilder: (context, i) {
                  final day = _today.add(Duration(days: i));
                  return DateChip(
                    date: day,
                    isToday: i == 0,
                    selected: day == _date,
                    onTap: () => setState(() => _date = day),
                  );
                },
              ),
            ),
            SlotPicker(key: ValueKey('${v.id}-${Fmt.isoDate(_date)}'), venue: v, date: _date),
            if (v.rules != null) ...[
              const SectionTitle('이용 규칙'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
                child: Text(v.rules!, style: const TextStyle(fontSize: 14, height: 1.6)),
              ),
            ],
            const SectionTitle('취소·환불 정책'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: FmSpace.l), child: PolicyTable(rules: v.cancelPolicy)),
          ],
        ),
      ),
    );
  }

  Widget _photos(VenueDetail v) {
    if (v.photos.isEmpty) {
      // 사진이 없으면 코트 일러스트 (실제 사진처럼 보이지 않게 "일러스트" 표시)
      return SizedBox(
        height: 200,
        child: CourtIllustration(seed: v.id, indoor: v.courts.any((c) => c.isIndoor), showLabel: true),
      );
    }
    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: v.photos.length,
            onPageChanged: (i) => setState(() => _photo = i),
            itemBuilder: (context, i) => v.photos[i].url == null
                ? Container(color: FmColors.surfaceMuted)
                : Image.network(v.photos[i].url!, fit: BoxFit.cover, width: double.infinity,
                    semanticLabel: '${v.name} 사진 ${i + 1}',
                    errorBuilder: (context, e, s) => Container(color: FmColors.surfaceMuted)),
          ),
          Positioned(
            right: FmSpace.m,
            bottom: FmSpace.m,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(FmRadius.chip)),
              child: Text('${_photo + 1}/${v.photos.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 취소 정책 표 (예: 72시간 전 100% / 24시간 전 50% / 이후 0%)
class PolicyTable extends StatelessWidget {
  const PolicyTable({super.key, required this.rules});

  final List<PolicyRule> rules;

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) return const Text('구장에 문의해 주세요');
    return Column(
      children: [
        for (final r in rules)
          InfoRow(r.hoursBefore == 0 ? '그 이후' : '이용 ${r.hoursBefore}시간 전까지', '${r.refundPercent}% 환불'),
        const SizedBox(height: FmSpace.xs),
        const Text('구장 사정으로 취소되면 전액 환불돼요. 이용 시작 후에는 취소할 수 없어요.',
            style: TextStyle(fontSize: 12, color: FmColors.textSecondary)),
      ],
    );
  }
}

/// 코트별 슬롯 선택. 같은 코트에서 연속된 예약 가능 슬롯만 이어서 고를 수 있다(최대 6시간).
class SlotPicker extends StatefulWidget {
  const SlotPicker({super.key, required this.venue, required this.date});

  final VenueDetail venue;
  final DateTime date;

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  int? _courtId;
  final List<Slot> _selected = [];

  void _tap(CourtAvailability court, Slot slot) {
    setState(() {
      if (_courtId != court.courtId || _selected.isEmpty) {
        _courtId = court.courtId;
        _selected
          ..clear()
          ..add(slot);
        return;
      }
      final first = _selected.first;
      final last = _selected.last;
      if (_selected.any((s) => s.id == slot.id)) {
        // 끝을 누르면 줄이고, 가운데를 누르면 그 슬롯만 선택
        if (slot.id == last.id && _selected.length > 1) {
          _selected.removeLast();
        } else if (slot.id == first.id && _selected.length > 1) {
          _selected.removeAt(0);
        } else {
          _selected
            ..clear()
            ..add(slot);
        }
        return;
      }
      final total = _selected.fold<int>(0, (a, s) => a + s.endsAt.difference(s.startsAt).inMinutes) +
          slot.endsAt.difference(slot.startsAt).inMinutes;
      if (slot.startsAt == last.endsAt && total <= 360) {
        _selected.add(slot);
      } else if (slot.endsAt == first.startsAt && total <= 360) {
        _selected.insert(0, slot);
      } else {
        _selected
          ..clear()
          ..add(slot);
      }
    });
  }

  Future<void> _book(CourtAvailability court) async {
    if (!await requireVerified(context)) return;
    if (!mounted) return;
    final features = AppScope.read(context).features.value;
    if (!features.paymentEnabled) {
      showFmSnack(context, '결제 기능이 아직 준비 중이라 예약할 수 없어요');
      return;
    }
    final court0 = widget.venue.courts.firstWhere((c) => c.id == court.courtId);
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ReservationConfirmScreen(venue: widget.venue, court: court0, slots: List.of(_selected)),
    ));
    if (ok == true && mounted) setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return AsyncBody<List<CourtAvailability>>(
      load: () => services.venues.availability(widget.venue.id, widget.date),
      isEmpty: (list) => list.every((c) => c.slots.isEmpty),
      empty: const EmptyState(
        icon: Icons.event_busy_outlined,
        title: '이 날은 예약 가능한 시간이 없어요',
        message: '다른 날짜를 선택해 보세요.',
      ),
      builder: (context, courts, reload) {
        final CourtAvailability? selectedCourt = courts.where((c) => c.courtId == _courtId).firstOrNull;
        final total = _selected.fold<int>(0, (a, s) => a + s.price);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final court in courts) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.m, FmSpace.l, FmSpace.s),
                child: Text('${court.courtName} · ${court.isIndoor ? '실내' : '실외'} · ${court.sizeClass.replaceAll('V', ':')}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (court.slots.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: FmSpace.l),
                  child: Text('운영 시간이 없어요', style: TextStyle(color: FmColors.textSecondary)),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
                  child: Wrap(
                    spacing: FmSpace.s,
                    runSpacing: FmSpace.s,
                    children: [
                      for (final s in court.slots)
                        _SlotChip(
                          slot: s,
                          selected: _courtId == court.courtId && _selected.any((x) => x.id == s.id),
                          onTap: s.available ? () => _tap(court, s) : null,
                        ),
                    ],
                  ),
                ),
            ],
            if (_selected.isNotEmpty && selectedCourt != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.l, FmSpace.l, 0),
                child: FmCard(
                  color: FmColors.brandSoft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${selectedCourt.courtName} · ${Fmt.date(_selected.first.startsAt)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${Fmt.range(_selected.first.startsAt, _selected.last.endsAt)} '
                          '(${_selected.last.endsAt.difference(_selected.first.startsAt).inMinutes ~/ 60}시간'
                          '${_selected.last.endsAt.difference(_selected.first.startsAt).inMinutes % 60 == 0 ? '' : ' ${_selected.last.endsAt.difference(_selected.first.startsAt).inMinutes % 60}분'})'),
                      const SizedBox(height: FmSpace.s),
                      Text(Fmt.won(total),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: FmColors.brandDark)),
                      const SizedBox(height: FmSpace.m),
                      LoadingButton(label: '예약하기', onPressed: () => _book(selectedCourt)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.selected, this.onTap});

  final Slot slot;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      selected: selected,
      label: '${Fmt.range(slot.startsAt, slot.endsAt)} ${disabled ? '예약 불가' : Fmt.won(slot.price)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FmRadius.control),
        child: Container(
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: FmSpace.s),
          decoration: BoxDecoration(
            color: selected ? FmColors.brandDark : (disabled ? FmColors.surfaceMuted : Colors.white),
            borderRadius: BorderRadius.circular(FmRadius.control),
            border: Border.all(color: selected ? FmColors.brandDark : FmColors.border),
          ),
          child: Column(
            children: [
              Text(Fmt.time(slot.startsAt),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : (disabled ? FmColors.textSecondary : FmColors.textPrimary),
                      decoration: disabled ? TextDecoration.lineThrough : null)),
              Text(disabled ? '마감' : Fmt.won(slot.price),
                  style: TextStyle(fontSize: 12, color: selected ? Colors.white : FmColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
