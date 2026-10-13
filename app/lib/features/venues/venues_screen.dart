import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/location.dart';
import '../../shared/widgets.dart';
import '../operator/operator_home_screen.dart';
import 'nearby_real_screen.dart';
import 'venue_detail_screen.dart';
import 'venue_tile.dart';

enum VenueView { list, map }

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
  const VenuesScreen({super.key});

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends State<VenuesScreen> {
  final _search = TextEditingController();
  String _query = '';
  VenueFilter _filter = const VenueFilter();
  VenueView _view = VenueView.list;
  Position? _here;
  bool _locating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _key => '$_query|${_filter.key}|${_here?.latitude}';

  Future<({List<VenueCard> items, bool hasNext})> _page(AppServices s, int page, {int pageSize = 20}) {
    return s.venues.search(
      q: _query,
      regions: _filter.regionCodes,
      indoor: _filter.indoor,
      size: _filter.size,
      facilities: _filter.facilities.toList(),
      lat: _here?.latitude,
      lng: _here?.longitude,
      radiusKm: _here == null ? null : 10,
      page: page,
      pageSize: pageSize,
    );
  }

  /// 내 주변: 위치정보 이용 동의(약관) → OS 권한 → 현재 위치 (shared/location.dart)
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

  void _open(VenueCard v) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => VenueDetailScreen(venueId: v.id)));
  }

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<VenueFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => VenueFilterSheet(initial: _filter),
    );
    if (result != null && mounted) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final mapsOn = AppConfig.mapsEnabled && services.features.value.maps;
    final f = _filter;
    return Scaffold(
      appBar: AppBar(
        title: const Text('풋살장'),
        actions: [
          IconButton(
            tooltip: '구장 운영자',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OperatorHomeScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.s, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('venue_search'),
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: fmInputDecoration(
                      label: '구장 이름 또는 주소 검색',
                      prefixIcon: const Icon(Icons.search_rounded),
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
                    ),
                    onSubmitted: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: FmSpace.xs),
                Badge(
                  isLabelVisible: f.count > 0,
                  label: Text('${f.count}'),
                  offset: const Offset(-4, 4),
                  child: IconButton(
                    key: const Key('venue_filter_button'),
                    tooltip: '필터',
                    iconSize: 26,
                    style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                    onPressed: _openFilter,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
          // 내 주변 + 적용된 필터 (눌러서 하나씩 해제)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, 0),
              children: [
                _chipPad(FilterChip(
                  avatar: _locating
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 16),
                  label: const Text('내 주변'),
                  selected: _here != null,
                  onSelected: (_) => _nearMe(),
                )),
                for (final r in f.regions)
                  _chipPad(InputChip(
                    label: Text(r),
                    onDeleted: () => setState(() => _filter = f.copyWith(regions: {...f.regions}..remove(r))),
                  )),
                if (f.indoor != null)
                  _chipPad(InputChip(
                    label: Text(f.indoor! ? '실내' : '실외'),
                    onDeleted: () => setState(() => _filter = f.copyWith(indoor: null)),
                  )),
                if (f.size != null)
                  _chipPad(InputChip(
                    label: Text(f.size!.replaceAll('V', ':')),
                    onDeleted: () => setState(() => _filter = f.copyWith(size: null)),
                  )),
                for (final code in f.facilities)
                  _chipPad(InputChip(
                    label: Text(kAllFacilities[code] ?? code),
                    onDeleted: () => setState(() => _filter = f.copyWith(facilities: {...f.facilities}..remove(code))),
                  )),
                if (f.count == 0)
                  _chipPad(ActionChip(
                    avatar: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text('지역·시설로 찾기'),
                    onPressed: _openFilter,
                  )),
              ],
            ),
          ),
          if (services.features.value.places)
            Padding(
              padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.xs, FmSpace.l, 0),
              child: FmCard(
                key: const Key('nearby_real_entry'),
                color: FmColors.brandSoft,
                padding: const EdgeInsets.symmetric(horizontal: FmSpace.m, vertical: FmSpace.s),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NearbyRealScreen())),
                child: const Row(
                  children: [
                    Icon(Icons.travel_explore_rounded, color: FmColors.brandDark),
                    SizedBox(width: FmSpace.s),
                    Expanded(
                      child: Text('내 주변 실제 풋살장 보기',
                          style: TextStyle(fontWeight: FontWeight.w700, color: FmColors.brandDark)),
                    ),
                    Icon(Icons.chevron_right_rounded, color: FmColors.brandDark),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, FmSpace.xs),
            child: SegmentedButton<VenueView>(
              segments: const [
                ButtonSegment(value: VenueView.list, label: Text('목록'), icon: Icon(Icons.view_list_rounded)),
                ButtonSegment(value: VenueView.map, label: Text('지도'), icon: Icon(Icons.map_outlined)),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          Expanded(child: _results(services, mapsOn)),
        ],
      ),
    );
  }

  Widget _chipPad(Widget chip) => Padding(padding: const EdgeInsets.only(right: FmSpace.s), child: chip);

  Widget _empty() => EmptyState(
        icon: Icons.sports_soccer_outlined,
        title: _query.isEmpty && _here == null && _filter.count == 0 ? '등록된 풋살장이 아직 없어요' : '조건에 맞는 구장이 없어요',
        message: _filter.count > 0 || _query.isNotEmpty
            ? '필터나 검색어를 바꿔 보세요.'
            : '풋살장을 운영하고 계신가요?\n입점하면 F-Mate 에서 바로 예약을 받을 수 있어요.',
        actionLabel: _filter.count > 0 ? '필터 초기화' : '구장 입점 신청',
        onAction: _filter.count > 0
            ? () => setState(() => _filter = const VenueFilter())
            : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OperatorHomeScreen())),
      );

  Widget _results(AppServices services, bool mapsOn) {
    if (_view == VenueView.map && !mapsOn) {
      return ListView(children: const [
        EmptyState(
          icon: Icons.map_outlined,
          title: '지도는 준비 중이에요',
          message: '지도 키가 연결되면 구장 위치를 지도에서 볼 수 있어요.\n지금은 목록에서 "지도 앱" 버튼으로 위치를 확인해 주세요.',
        ),
      ]);
    }
    if (_view == VenueView.map) {
      // 지도: 조건에 맞는 구장 최대 50곳
      return AsyncBody<List<VenueCard>>(
        key: ValueKey('$_key-map'),
        load: () async => (await _page(services, 0, pageSize: 50)).items,
        isEmpty: (l) => l.isEmpty,
        empty: _empty(),
        builder: (context, venues, reload) => GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _here != null
                ? LatLng(_here!.latitude, _here!.longitude)
                : LatLng(venues.first.latitude, venues.first.longitude),
            zoom: 11,
          ),
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
      );
    }
    // 목록: 끝까지 내리면 다음 페이지를 이어서 불러온다
    return PagedList<VenueCard>(
      key: ValueKey('$_key-list'),
      padding: const EdgeInsets.only(bottom: FmSpace.xl),
      fetch: (cursor) async {
        final page = cursor ?? 0;
        final r = await _page(services, page);
        return (r.items, r.hasNext ? page + 1 : null);
      },
      itemBuilder: (context, v, i) => VenueTile(venue: v, onTap: () => _open(v)),
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
