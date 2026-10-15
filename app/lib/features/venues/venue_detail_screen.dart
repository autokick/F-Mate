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
import '../../shared/court_illustration.dart';
import '../../shared/date_chip.dart';
import '../../shared/report_sheet.dart';
import '../../shared/widgets.dart';
import '../profile/post_grid.dart';
import '../reservations/reservation_confirm_screen.dart';
import '../shorts/shorts_screen.dart';
import 'venue_slots.dart';

/// 편의시설 코드 → 아이콘
const Map<String, IconData> kFacilityIcons = {
  'PARKING': Icons.local_parking_rounded,
  'SHOWER': Icons.shower_outlined,
  'LOCKER': Icons.lock_outline_rounded,
  'CHANGING_ROOM': Icons.checkroom_rounded,
  'BALL_RENTAL': Icons.sports_soccer_outlined,
  'VEST_RENTAL': Icons.dry_cleaning_outlined,
  'SHOE_RENTAL': Icons.directions_run_rounded,
  'NIGHT_LIGHTING': Icons.lightbulb_outline_rounded,
  'RESTROOM': Icons.wc_rounded,
  'WATER': Icons.water_drop_outlined,
  'SPECTATOR_SEATS': Icons.event_seat_outlined,
  'CAFE': Icons.local_cafe_outlined,
  'WIFI': Icons.wifi_rounded,
};

/// 구장 상세 + 날짜별 실제 예약 가능 시간 선택
class VenueDetailScreen extends StatelessWidget {
  const VenueDetailScreen({super.key, required this.venueId, this.initialDate, this.initialTime, this.demoFor});

  final int venueId;
  final DateTime? initialDate;

  /// 목록에서 시간 칩을 눌러 들어온 경우 그 시간을 미리 골라 둔다
  final DateTime? initialTime;

  /// (이전 버전 호환용, 사용하지 않음)
  final String? demoFor;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: AsyncBody<VenueDetail>(
                load: () => services.venues.detail(venueId),
                builder: (context, v, reload) => _VenueDetailView(
                  venue: v,
                  initialDate: initialDate,
                  initialTime: initialTime,
                ),
              ),
            ),
            Positioned(
              top: top + 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _CircleButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: '뒤로',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  _CircleButton(
                    icon: Icons.ios_share_rounded,
                    tooltip: '공유',
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: 'https://fmate.app/v/$venueId'));
                      if (context.mounted) showFmSnack(context, '구장 링크를 복사했어요');
                    },
                  ),
                  const SizedBox(width: 8),
                  _CircleButton(
                    icon: Icons.flag_outlined,
                    tooltip: '구장 정보 신고',
                    onTap: () {
                      if (requireLogin(context)) showReportSheet(context, 'VENUE', venueId);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xEBFFFFFF),
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: FmColors.ink)),
        ),
      ),
    );
  }
}

class _VenueDetailView extends StatefulWidget {
  const _VenueDetailView({required this.venue, this.initialDate, this.initialTime});

  final VenueDetail venue;
  final DateTime? initialDate;
  final DateTime? initialTime;

  @override
  State<_VenueDetailView> createState() => _VenueDetailViewState();
}

class _VenueDetailViewState extends State<_VenueDetailView> {
  final DateTime _today = dateOnly(DateTime.now());
  late DateTime _date = dateOnly(widget.initialDate ?? DateTime.now());
  late Future<List<CourtAvailability>> _availability;
  DateTime? _pendingTime;
  int _photo = 0;

  int? _courtId;
  final List<Slot> _selected = [];

  VenueDetail get v => widget.venue;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _pendingTime = widget.initialTime;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _loadAvailability();
    }
  }

  void _loadAvailability() {
    final services = AppScope.read(context);
    _availability = services.venues.availability(v.id, _date).then((courts) {
      // 목록에서 고른 시간이 있으면 미리 선택
      final t = _pendingTime;
      _pendingTime = null;
      if (t != null && mounted) {
        for (final c in courts) {
          final hit = c.slots.where((s) => s.available && s.startsAt == t).firstOrNull;
          if (hit != null) {
            setState(() {
              _courtId = c.courtId;
              _selected
                ..clear()
                ..add(hit);
            });
            break;
          }
        }
      }
      return courts;
    });
  }

  void _pickDate(DateTime d) {
    setState(() {
      _date = d;
      _courtId = null;
      _selected.clear();
      _loadAvailability();
    });
  }

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
        } else if (_selected.length == 1) {
          _selected.clear();
          _courtId = null;
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

  Future<void> _book() async {
    final courtId = _courtId;
    if (courtId == null || _selected.isEmpty) return;
    if (!await requireVerified(context)) return;
    if (!mounted) return;
    final features = AppScope.read(context).features.value;
    if (!features.paymentEnabled) {
      showFmSnack(context, '결제를 연결하는 중이에요. 잠시 후 다시 시도해 주세요');
      return;
    }
    final court = v.courts.firstWhere((c) => c.id == courtId);
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ReservationConfirmScreen(venue: v, court: court, slots: List.of(_selected)),
    ));
    if (!mounted) return;
    // 예약했든 아니든 최신 시간표로 다시 불러온다 (다른 사람이 먼저 잡았을 수 있음)
    VenueSlots.clear();
    setState(() {
      if (ok == true) {
        _selected.clear();
        _courtId = null;
      }
      _loadAvailability();
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final mapsOn = AppConfig.mapsEnabled && services.features.value.maps;
    final hasIndoor = v.courts.any((c) => c.isIndoor);
    final hasOutdoor = v.courts.any((c) => !c.isIndoor);
    final sizes = {for (final c in v.courts) c.sizeClass.replaceAll('V', ':')}.toList()..sort();

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _photos()),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -20),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    padding: const EdgeInsets.fromLTRB(FmSpace.page, 22, FmSpace.page, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 6, children: [
                          if (hasIndoor) const _Tag('실내', strong: true),
                          if (hasOutdoor) const _Tag('실외', strong: true),
                          if (sizes.isNotEmpty) _Tag(sizes.join(' · ')),
                        ]),
                        const SizedBox(height: 8),
                        Text(v.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onLongPress: () async {
                            await Clipboard.setData(ClipboardData(text: v.roadAddress));
                            if (context.mounted) showFmSnack(context, '주소를 복사했어요');
                          },
                          child: Text('${v.roadAddress}${v.detailAddress == null ? '' : ' ${v.detailAddress}'}',
                              style: const TextStyle(fontSize: 14, color: FmColors.textSecondary)),
                        ),
                        const SizedBox(height: FmSpace.m),
                        Row(children: [
                          if (v.phone != null) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => launchUrl(Uri(scheme: 'tel', path: v.phone)),
                                icon: const Icon(Icons.call_outlined, size: 18),
                                label: const Text('전화'),
                              ),
                            ),
                            const SizedBox(width: FmSpace.s),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => launchUrl(
                                  Uri.parse(
                                      'https://map.kakao.com/link/map/${Uri.encodeComponent(v.name)},${v.latitude},${v.longitude}'),
                                  mode: LaunchMode.externalApplication),
                              icon: const Icon(Icons.map_outlined, size: 18),
                              label: const Text('길찾기'),
                            ),
                          ),
                        ]),
                        if (v.facilities.isNotEmpty) ...[
                          const SizedBox(height: FmSpace.l),
                          _FacilityGrid(facilities: v.facilities),
                        ],
                        if (v.description != null && v.description!.trim().isNotEmpty) ...[
                          const SizedBox(height: FmSpace.l),
                          Text(v.description!, style: const TextStyle(fontSize: 15, height: 1.6)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _VenueVideos(venueId: v.id)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.l, FmSpace.page, FmSpace.m),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('시간 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(width: FmSpace.s),
                      Text(formatDateKo(_date), style: const TextStyle(fontSize: 14, color: FmColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: DateStrip(today: _today, selected: _date, onSelected: _pickDate, height: 58),
              ),
              SliverToBoxAdapter(child: _slots()),
              if (mapsOn)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.xl, FmSpace.page, 0),
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
                ),
              if (v.rules != null && v.rules!.trim().isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionTitle('이용 규칙')),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: FmSpace.page),
                    child: Text(v.rules!, style: const TextStyle(fontSize: 14, height: 1.6)),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SectionTitle('취소·환불 정책')),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FmSpace.page),
                  child: PolicyTable(rules: v.cancelPolicy),
                ),
              ),
              if (v.isPublicData)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(FmSpace.page, FmSpace.xl, FmSpace.page, 0),
                    child: Text(
                      '시설 기본 정보 출처: 국민체육진흥공단 전국체육시설 정보(공공데이터포털)',
                      key: Key('public_data_source'),
                      style: TextStyle(fontSize: 11, color: FmColors.textTertiary),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: FmSpace.xxl)),
            ],
          ),
        ),
        _BookingBar(
          courtName: v.courts.where((c) => c.id == _courtId).map((c) => c.name).firstOrNull,
          selected: _selected,
          onBook: _book,
        ),
      ],
    );
  }

  Widget _photos() {
    const height = 300.0;
    if (v.photos.isEmpty) {
      return SizedBox(height: height, child: CourtIllustration(seed: v.id, indoor: v.courts.any((c) => c.isIndoor)));
    }
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: v.photos.length,
            onPageChanged: (i) => setState(() => _photo = i),
            itemBuilder: (context, i) => v.photos[i].url == null
                ? Container(color: FmColors.photoPlaceholder)
                : Image.network(v.photos[i].url!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    semanticLabel: '${v.name} 사진 ${i + 1}',
                    errorBuilder: (context, e, s) => Container(color: FmColors.photoPlaceholder)),
          ),
          if (v.photos.length > 1)
            Positioned(
              right: FmSpace.l,
              bottom: 34,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xB80F1419), borderRadius: BorderRadius.circular(FmRadius.chip)),
                child: Text('${_photo + 1} / ${v.photos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slots() {
    return FutureBuilder<List<CourtAvailability>>(
      future: _availability,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(FmSpace.xl), child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return ErrorState(
            title: '시간표를 불러오지 못했어요',
            onRetry: () => setState(_loadAvailability),
          );
        }
        final courts = snap.data ?? const <CourtAvailability>[];
        if (courts.every((c) => c.slots.isEmpty)) {
          return const EmptyState(
            icon: Icons.event_busy_outlined,
            title: '이 날은 예약 가능한 시간이 없어요',
            message: '다른 날짜를 선택해 보세요.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final court in courts) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.l, FmSpace.page, FmSpace.s),
                child: Text(
                    '${court.courtName} · ${court.isIndoor ? '실내' : '실외'} · ${court.sizeClass.replaceAll('V', ':')}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (court.slots.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: FmSpace.page),
                  child: Text('이 날은 운영하지 않아요', style: TextStyle(color: FmColors.textSecondary)),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FmSpace.page),
                  child: GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.3,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final s in court.slots)
                        _SlotChip(
                          slot: s,
                          selected: _courtId == court.courtId && _selected.any((x) => x.id == s.id),
                          onTap: s.available && s.startsAt.isAfter(DateTime.now()) ? () => _tap(court, s) : null,
                        ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: strong ? FmColors.brandSoft : FmColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: strong ? FmColors.brandOnSoft : const Color(0xFF3D4652))),
    );
  }
}

/// 편의시설 아이콘 격자 (5칸)
class _FacilityGrid extends StatelessWidget {
  const _FacilityGrid({required this.facilities});

  final List<Facility> facilities;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: FmColors.divider)),
      ),
      child: GridView.count(
        crossAxisCount: 5,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
        padding: EdgeInsets.zero,
        children: [
          for (final f in facilities)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(kFacilityIcons[f.code] ?? Icons.check_circle_outline_rounded, size: 24, color: FmColors.ink),
                const SizedBox(height: 4),
                Text(f.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF3D4652))),
              ],
            ),
        ],
      ),
    );
  }
}

/// "이 구장에서 올라온 영상" (로그인했고 게시물이 있을 때만)
class _VenueVideos extends StatelessWidget {
  const _VenueVideos({required this.venueId});

  final int venueId;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.session.isLoggedIn) return const SizedBox.shrink();
    return FutureBuilder<CursorPage<Post>>(
      future: s.social.venuePosts(venueId),
      builder: (context, snap) {
        final posts = (snap.data?.items ?? const <Post>[]).where((p) => p.video == null || p.video!.ready).toList();
        if (posts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('이 구장에서 올라온 영상'),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: FmSpace.page),
                itemCount: posts.length,
                separatorBuilder: (context, i) => const SizedBox(width: 8),
                itemBuilder: (context, i) => SizedBox(
                  width: 108,
                  child: PostThumb(
                    post: posts[i],
                    radius: 14,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ShortsScreen(initialPosts: posts, initialIndex: i),
                    )),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 아래 고정 예약 바: 선택한 시간 · 합계 · 예약하기
class _BookingBar extends StatelessWidget {
  const _BookingBar({required this.courtName, required this.selected, required this.onBook});

  final String? courtName;
  final List<Slot> selected;
  final Future<void> Function() onBook;

  @override
  Widget build(BuildContext context) {
    final total = selected.fold<int>(0, (a, s) => a + s.price);
    final minutes = selected.isEmpty ? 0 : selected.last.endsAt.difference(selected.first.startsAt).inMinutes;
    final duration = '${minutes ~/ 60}시간${minutes % 60 == 0 ? '' : ' ${minutes % 60}분'}';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: FmColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.m, FmSpace.page, FmSpace.m),
          child: Row(
            children: [
              Expanded(
                child: selected.isEmpty
                    ? const Text('시간을 선택해 주세요',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FmColors.textSecondary))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${courtName ?? ''} · ${Fmt.range(selected.first.startsAt, selected.last.endsAt)} · $duration',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: FmColors.textSecondary),
                          ),
                          Text(Fmt.won(total),
                              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                        ],
                      ),
              ),
              const SizedBox(width: FmSpace.m),
              SizedBox(
                width: 150,
                child: LoadingButton(
                  key: const Key('book_button'),
                  label: '예약하기',
                  onPressed: selected.isEmpty ? null : onBook,
                ),
              ),
            ],
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: FmColors.surfaceMuted,
        borderRadius: BorderRadius.circular(FmRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(
                  child: Text(r.hoursBefore == 0 ? '그 이후' : '이용 ${r.hoursBefore}시간 전까지',
                      style: const TextStyle(fontSize: 14, color: FmColors.textSecondary)),
                ),
                Text('${r.refundPercent}% 환불', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
            ),
          const SizedBox(height: 4),
          const Text('구장 사정으로 취소되면 전액 환불돼요. 이용 시작 후에는 취소할 수 없어요.',
              style: TextStyle(fontSize: 12, color: FmColors.textSecondary)),
        ],
      ),
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
    final fg = selected ? Colors.white : (disabled ? FmColors.textTertiary : FmColors.textPrimary);
    return Semantics(
      button: true,
      enabled: !disabled,
      selected: selected,
      label: '${Fmt.range(slot.startsAt, slot.endsAt)} ${disabled ? '예약 불가' : Fmt.won(slot.price)}',
      excludeSemantics: true,
      child: Material(
        color: selected ? FmColors.ink : (disabled ? FmColors.surfaceMuted : Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FmRadius.control),
          side: BorderSide(color: selected || disabled ? Colors.transparent : const Color(0xFFDDE1E6)),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FmRadius.control)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(Fmt.time(slot.startsAt),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: fg,
                      decoration: disabled ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 1),
              Text(disabled ? '마감' : Fmt.won(slot.price),
                  style: TextStyle(
                      fontSize: 11, color: selected ? const Color(0xFFC9D1D9) : FmColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
