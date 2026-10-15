import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/date_chip.dart';
import '../../shared/location.dart';
import '../../shared/widgets.dart';
import '../reservations/my_reservations_screen.dart';
import 'venue_detail_screen.dart';
import 'venue_tile.dart';

/// 자주 쓰는 편의시설 (입점 신청 화면에서도 사용). 코드는 서버 facilities.code 와 같다.
const Map<String, String> kFacilityFilters = {
  'PARKING': '주차',
  'SHOWER': '샤워실',
  'NIGHT_LIGHTING': '야간 조명',
  'BALL_RENTAL': '공 대여',
  'CHANGING_ROOM': '탈의실',
};

/// 필터 화면에 보여줄 전체 편의시설
const Map<String, String> kAllFacilities = {
  'PARKING': '주차',
  'SHOWER': '샤워실',
  'CHANGING_ROOM': '탈의실',
  'LOCKER': '락커',
  'RESTROOM': '화장실',
  'WATER': '정수기',
  'BALL_RENTAL': '공 대여',
  'VEST_RENTAL': '조끼 대여',
  'SHOE_RENTAL': '풋살화 대여',
  'NIGHT_LIGHTING': '야간 조명',
  'SPECTATOR_SEATS': '관람석',
  'CAFE': '매점·카페',
  'WIFI': '와이파이',
};

const List<String> kCourtSizes = ['4V4', '5V5', '6V6', '7V7'];

/// 풋살장 검색 조건
class VenueFilter {
  const VenueFilter({this.regions = const {}, this.indoor, this.size, this.facilities = const {}});

  /// 선택한 지역 이름 (kRegions 의 label)
  final Set<String> regions;
  final bool? indoor;
  final String? size;
  final Set<String> facilities;

  int get count => regions.length + (indoor == null ? 0 : 1) + (size == null ? 0 : 1) + facilities.length;

  List<String> get regionCodes =>
      [for (final r in kRegions) if (regions.contains(r.label)) ...r.codes];

  String get key => '${regions.join(',')}|$indoor|$size|${facilities.join(',')}';

  VenueFilter copyWith({Set<String>? regions, Object? indoor = _keep, Object? size = _keep, Set<String>? facilities}) =>
      VenueFilter(
        regions: regions ?? this.regions,
        indoor: identical(indoor, _keep) ? this.indoor : indoor as bool?,
        size: identical(size, _keep) ? this.size : size as String?,
        facilities: facilities ?? this.facilities,
      );

  static const _keep = Object();
}

class VenuesScreen extends StatefulWidget {
  const VenuesScreen({super.key, this.today});

  /// 테스트에서 날짜 고정용
  final DateTime? today;

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen> {
  final _search = TextEditingController();
  String _query = '';
  VenueFilter _filter = const VenueFilter();
  TimeBand _band = TimeBand.all;
  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());
  late DateTime _date = _today;
  bool _map = false;
  Position? _here;
  bool _locating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _key => '$_query|${_filter.key}|${_band.name}|${_date.toIso8601String()}|${_here?.latitude}';

  double get _lat => _here?.latitude ?? AppConfig.defaultLat;
  double get _lng => _here?.longitude ?? AppConfig.defaultLng;

  Future<({List<VenueCard> items, bool hasNext})> _page(AppServices s, int page, {int pageSize = 20}) {
    return s.venues.search(
      q: _query,
      regions: _filter.regionCodes,
      indoor: _filter.indoor,
      size: _filter.size,
      facilities: _filter.facilities.toList(),
      lat: _lat,
      lng: _lng,
      radiusKm: _here == null ? 40.0 : 15.0,
      date: _date,
      fromHour: _band.fromHour,
      toHour: _band.toHour,
      page: page,
      pageSize: pageSize,
    );
  }

  /// 내 위치: 위치정보 이용 동의(약관) → OS 권한 → 현재 위치 (shared/location.dart)
  Future<void> _nearMe() async {
    if (_here != null) {
      setState(() => _here = null);
      return;
    }
    setState(() => _locating = true);
    try {
      final pos = await locateMe(context);
      if (mounted && pos != null) setState(() => _here = pos);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _open(VenueCard v, {DateTime? time}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VenueDetailScreen(venueId: v.id, initialDate: _date, initialTime: time),
    ));
  }

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<VenueFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VenueFilterSheet(initial: _filter),
    );
    if (result != null && mounted) setState(() => _filter = result);
  }

  void _toggleFacility(String code) {
    final f = {..._filter.facilities};
    f.contains(code) ? f.remove(code) : f.add(code);
    setState(() => _filter = _filter.copyWith(facilities: f));
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final mapsOn = AppConfig.mapsEnabled && services.features.value.maps;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.m, FmSpace.s, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('구장 찾기',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  ),
                  if (mapsOn)
                    IconButton(
                      tooltip: _map ? '목록으로 보기' : '지도로 보기',
                      icon: Icon(_map ? Icons.view_agenda_outlined : Icons.map_outlined),
                      onPressed: () => setState(() => _map = !_map),
                    ),
                  IconButton(
                    key: const Key('my_reservations_button'),
                    tooltip: '내 예약',
                    icon: const Icon(Icons.event_note_outlined),
                    onPressed: () {
                      if (!requireLogin(context)) return;
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyReservationsScreen()));
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.s, FmSpace.page, 0),
              child: TextField(
                key: const Key('venue_search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '구장 이름이나 동네 검색',
                  filled: true,
                  fillColor: FmColors.surfaceMuted,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: FmColors.textSecondary),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '검색어 지우기',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(FmRadius.control), borderSide: BorderSide.none),
                ),
                onSubmitted: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(child: _results(services, mapsOn)),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    final f = _filter;
    Widget pad(Widget chip) => Padding(padding: const EdgeInsets.only(right: FmSpace.s), child: chip);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: FmSpace.l),
        DateStrip(
          key: const Key('date_strip'),
          today: _today,
          selected: _date,
          onSelected: (d) => setState(() => _date = d),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.m, FmSpace.page, 0),
            children: [
              pad(Badge(
                isLabelVisible: f.count > 0,
                label: Text('${f.count}'),
                backgroundColor: FmColors.brandDark,
                child: ActionChip(
                  key: const Key('venue_filter_button'),
                  tooltip: '필터',
                  avatar: const Icon(Icons.tune_rounded, size: 18, color: FmColors.textPrimary),
                  label: const Text('필터'),
                  onPressed: _openFilter,
                ),
              )),
              pad(FilterChip(
                avatar: _locating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.near_me_outlined, size: 16, color: _here != null ? Colors.white : FmColors.textPrimary),
                label: const Text('내 위치'),
                selected: _here != null,
                onSelected: (_) => _nearMe(),
              )),
              for (final r in f.regions)
                pad(InputChip(
                  label: Text(r),
                  selected: true,
                  deleteIconColor: Colors.white,
                  onDeleted: () => setState(() => _filter = f.copyWith(regions: {...f.regions}..remove(r))),
                )),
              for (final b in TimeBand.values.where((b) => b != TimeBand.all))
                pad(FilterChip(
                  label: Text(b.label),
                  selected: _band == b,
                  onSelected: (on) => setState(() => _band = on ? b : TimeBand.all),
                )),
              pad(FilterChip(
                label: const Text('실내'),
                selected: f.indoor == true,
                onSelected: (on) => setState(() => _filter = f.copyWith(indoor: on ? true : null)),
              )),
              pad(FilterChip(
                label: const Text('실외'),
                selected: f.indoor == false,
                onSelected: (on) => setState(() => _filter = f.copyWith(indoor: on ? false : null)),
              )),
              for (final code in const ['SHOWER', 'PARKING'])
                pad(FilterChip(
                  label: Text(kAllFacilities[code]!),
                  selected: f.facilities.contains(code),
                  onSelected: (_) => _toggleFacility(code),
                )),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.l, FmSpace.page, FmSpace.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text('예약 가능한 구장', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              Text(
                '${formatDateKo(_date)} · ${_here == null ? '${AppConfig.defaultAreaName} 기준' : '내 위치 기준'}',
                key: const Key('selected_date_label'),
                style: const TextStyle(fontSize: 13, color: FmColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.only(top: FmSpace.l),
        child: EmptyState(
          icon: Icons.event_busy_outlined,
          title: _query.isEmpty && _filter.count == 0 && _band == TimeBand.all
              ? '이 날은 예약 가능한 구장이 없어요'
              : '조건에 맞는 구장이 없어요',
          message: '다른 날짜나 조건으로 찾아보세요.',
          actionLabel: _filter.count > 0 || _band != TimeBand.all ? '조건 초기화' : null,
          onAction: () => setState(() {
            _filter = const VenueFilter();
            _band = TimeBand.all;
          }),
        ),
      );

  Widget _results(AppServices services, bool mapsOn) {
    if (_map && mapsOn) {
      return Column(
        children: [
          _controls(),
          Expanded(
            child: AsyncBody<List<VenueCard>>(
              key: ValueKey('$_key-map'),
              load: () async => (await _page(services, 0, pageSize: 50)).items,
              isEmpty: (l) => l.isEmpty,
              empty: _empty(),
              builder: (context, venues, reload) => GoogleMap(
                initialCameraPosition: CameraPosition(target: LatLng(_lat, _lng), zoom: 12.5),
                myLocationEnabled: _here != null,
                markers: {
                  for (final v in venues)
                    Marker(
                      markerId: MarkerId('${v.id}'),
                      position: LatLng(v.latitude, v.longitude),
                      infoWindow: InfoWindow(title: v.name, snippet: v.roadAddress, onTap: () => _open(v)),
                    ),
                },
              ),
            ),
          ),
        ],
      );
    }
    // 목록: 끝까지 내리면 다음 페이지를 이어서 불러온다
    return PagedList<VenueCard>(
      key: ValueKey('$_key-list'),
      header: _controls(),
      padding: const EdgeInsets.only(bottom: FmSpace.xl),
      fetch: (cursor) async {
        final page = cursor ?? 0;
        final r = await _page(services, page);
        return (r.items, r.hasNext ? page + 1 : null);
      },
      itemBuilder: (context, v, i) => VenueTile(
        venue: v,
        date: _date,
        fromHour: _band.fromHour,
        toHour: _band.toHour,
        onTap: () => _open(v),
        onTimeTap: (t) => _open(v, time: t),
      ),
      empty: _empty(),
    );
  }
}

/// 필터 바텀시트: 지역(여러 개) · 실내/실외 · 코트 크기 · 편의시설(모두 갖춘 곳)
class VenueFilterSheet extends StatefulWidget {
  const VenueFilterSheet({super.key, required this.initial});

  final VenueFilter initial;

  @override
  State<VenueFilterSheet> createState() => _VenueFilterSheetState();
}

class _VenueFilterSheetState extends State<VenueFilterSheet> {
  late Set<String> _regions = {...widget.initial.regions};
  late bool? _indoor = widget.initial.indoor;
  late String? _size = widget.initial.size;
  late Set<String> _facilities = {...widget.initial.facilities};

  Widget _title(String t, [String? hint]) => Padding(
        padding: const EdgeInsets.only(top: FmSpace.l, bottom: FmSpace.s),
        child: Row(
          children: [
            Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (hint != null) ...[
              const SizedBox(width: FmSpace.s),
              Text(hint, style: const TextStyle(fontSize: 12, color: FmColors.textSecondary)),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final regions = kRegions.where((r) => r.codes.isNotEmpty).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
            child: Row(
              children: [
                const Text('필터', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _regions = {};
                    _indoor = null;
                    _size = null;
                    _facilities = {};
                  }),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('초기화'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: FmSpace.l),
              children: [
                _title('지역', '여러 곳 선택 가능'),
                Wrap(
                  spacing: FmSpace.s,
                  runSpacing: FmSpace.s,
                  children: [
                    for (final r in regions)
                      FilterChip(
                        label: Text(r.label),
                        selected: _regions.contains(r.label),
                        onSelected: (on) => setState(() => on ? _regions.add(r.label) : _regions.remove(r.label)),
                      ),
                  ],
                ),
                _title('실내 / 실외'),
                Wrap(
                  spacing: FmSpace.s,
                  children: [
                    for (final (label, value) in const [('전체', null), ('실내', true), ('실외', false)])
                      ChoiceChip(
                        label: Text(label),
                        selected: _indoor == value,
                        onSelected: (_) => setState(() => _indoor = value),
                      ),
                  ],
                ),
                _title('코트 크기'),
                Wrap(
                  spacing: FmSpace.s,
                  children: [
                    ChoiceChip(label: const Text('전체'), selected: _size == null, onSelected: (_) => setState(() => _size = null)),
                    for (final s in kCourtSizes)
                      ChoiceChip(
                        label: Text(s.replaceAll('V', ':')),
                        selected: _size == s,
                        onSelected: (_) => setState(() => _size = s),
                      ),
                  ],
                ),
                _title('편의시설', '모두 갖춘 곳만'),
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
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, FmSpace.l),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('venue_filter_apply'),
                  onPressed: () => Navigator.of(context).pop(VenueFilter(
                    regions: _regions,
                    indoor: _indoor,
                    size: _size,
                    facilities: _facilities,
                  )),
                  child: const Text('적용하기'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
