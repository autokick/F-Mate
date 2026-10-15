import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/async.dart';
import '../../shared/location.dart';
import '../../shared/widgets.dart';
import 'venue_detail_screen.dart';

/// 내 주변 실제 풋살장 (카카오 로컬 검색, 실시간 조회·저장하지 않음).
/// F-Mate 와 예약 제휴된 구장이 아니므로 정보만 보여주고,
/// "예약 체험"은 시연용 구장의 시간표로 예약 과정을 보여준다 (화면에 명시).
class NearbyRealScreen extends StatefulWidget {
  const NearbyRealScreen({super.key, this.autoLocate = true});

  /// Test-only control for platform GPS startup; production continues locating.
  final bool autoLocate;

  @override
  State<NearbyRealScreen> createState() => _NearbyRealScreenState();
}

class _NearbyRealScreenState extends State<NearbyRealScreen> {
  final _area = TextEditingController();

  double? _lat;
  double? _lng;
  String? _areaQuery;

  final List<NearbyPlace> _items = [];
  String _attribution = '장소 정보 제공: 카카오';
  int _page = 1;
  bool _hasNext = false;
  bool _loading = false;
  bool _locating = false;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoLocate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useMyLocation());
    }
  }

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  bool get _hasSearch => (_lat != null && _lng != null) || (_areaQuery != null && _areaQuery!.isNotEmpty);

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final pos = await locateMe(context);
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos == null) return; // 위치를 못 쓰면 지역 검색으로 찾는다
    _lat = pos.latitude;
    _lng = pos.longitude;
    _areaQuery = null;
    _area.clear();
    await _load(reset: true);
  }

  Future<void> _searchArea(String v) async {
    final q = v.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    _areaQuery = q;
    _lat = null;
    _lng = null;
    await _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (!_hasSearch || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 1;
        _hasNext = false;
      }
    });
    try {
      final r = await AppScope.read(context).venues.nearbyReal(lat: _lat, lng: _lng, area: _areaQuery, page: _page);
      if (!mounted) return;
      setState(() {
        _items.addAll(r.items);
        _attribution = r.attribution;
        _hasNext = r.hasNext;
        _page += 1;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showFmSnack(context, '열 수 없어요');
  }

  /// 예약 체험: 같은 구장이 공공데이터로 들어와 있으면 그 구장을, 없으면 가장 가까운 구장의 예약 화면을 연다.
  /// 시간표·가격은 시연용이며 실제 예약이 아니다 (구장 설명과 안내 배너에 표시).
  Future<void> _tryBooking(NearbyPlace place) async {
    final s = AppScope.read(context);
    try {
      // 1) 같은 자리(300m 이내)에 있는 구장
      final same = await s.venues.search(lat: place.lat, lng: place.lng, radiusKm: 0.5);
      if (!mounted) return;
      final match = same.items.where((v) => _distanceKm(place.lat, place.lng, v.latitude, v.longitude) <= 0.3).toList();
      if (match.isNotEmpty) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VenueDetailScreen(venueId: match.first.id)));
        return;
      }
      // 2) 없으면 가까운 구장으로 예약 과정만 보여준다
      final near = await s.venues.search(lat: place.lat, lng: place.lng, radiusKm: 50);
      if (!mounted) return;
      if (near.items.isEmpty) {
        showFmSnack(context, '예약 체험에 쓸 구장이 아직 없어요 (서버에 공공데이터 구장을 넣어 주세요)');
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VenueDetailScreen(venueId: near.items.first.id, demoFor: place.name)));
    } on ApiError catch (e) {
      if (mounted) showError(context, e);
    }
  }

  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 주변 실제 풋살장')),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.only(bottom: FmSpace.xl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, 0),
              child: FmCard(
                color: FmColors.brandSoft,
                padding: const EdgeInsets.all(FmSpace.m),
                child: const Text(
                  '카카오에서 찾은 실제 풋살장이에요. 아직 F-Mate와 예약 제휴 전이라 정보만 보여드려요.\n'
                  '"예약 체험"을 누르면 시연용 시간표로 예약 과정을 보여드려요 (실제 예약 아님).',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.m, FmSpace.l, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('nearby_area'),
                      controller: _area,
                      textInputAction: TextInputAction.search,
                      decoration: fmInputDecoration(label: '지역으로 찾기 (예: 강남, 동탄)', prefixIcon: const Icon(Icons.search_rounded)),
                      onSubmitted: _searchArea,
                    ),
                  ),
                  const SizedBox(width: FmSpace.s),
                  IconButton.filledTonal(
                    tooltip: '내 위치로 찾기',
                    onPressed: _locating ? null : _useMyLocation,
                    icon: _locating
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FmSpace.s),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: FmSpace.xl),
                child: ErrorView(error: _error!, onRetry: () => _load(reset: true)),
              )
            else if (!_hasSearch && !_locating)
              const Padding(
                padding: EdgeInsets.only(top: FmSpace.xl),
                child: EmptyState(
                  icon: Icons.location_searching_rounded,
                  title: '어디서 찾을까요?',
                  message: '내 위치 버튼을 누르거나 지역 이름을 입력해 주세요.',
                ),
              )
            else if (_items.isEmpty && _loading)
              const Padding(padding: EdgeInsets.only(top: FmSpace.xl), child: LoadingState())
            else if (_items.isEmpty && !_loading && !_locating)
              const Padding(
                padding: EdgeInsets.only(top: FmSpace.xl),
                child: EmptyState(
                  icon: Icons.sports_soccer_outlined,
                  title: '주변에서 풋살장을 찾지 못했어요',
                  message: '다른 지역 이름으로 찾아보세요.',
                ),
              ),
            for (final p in _items)
              Padding(
                padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, 0),
                child: _PlaceCard(
                  place: p,
                  onCall: p.phone == null ? null : () => _open('tel:${p.phone}'),
                  onMap: p.placeUrl == null ? null : () => _open(p.placeUrl!),
                  onTryBooking: () => _tryBooking(p),
                ),
              ),
            if (_hasNext)
              Padding(
                padding: const EdgeInsets.only(top: FmSpace.s),
                child: Center(
                  child: TextButton(
                    onPressed: _loading ? null : () => _load(),
                    child: Text(_loading ? '불러오는 중' : '더 보기'),
                  ),
                ),
              ),
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.m, FmSpace.l, 0),
                child: Text(_attribution,
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: FmColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, this.onCall, this.onMap, required this.onTryBooking});

  final NearbyPlace place;
  final VoidCallback? onCall;
  final VoidCallback? onMap;
  final VoidCallback onTryBooking;

  @override
  Widget build(BuildContext context) {
    final p = place;
    final sub = [if (p.distanceLabel != null) p.distanceLabel!, if (p.displayAddress.isNotEmpty) p.displayAddress].join(' · ');
    final categoryTail = p.category.split('>').last.trim();
    return FmCard(
      padding: const EdgeInsets.all(FmSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (categoryTail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: FmSpace.s),
                  child: StatusChip(label: categoryTail),
                ),
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 13, color: FmColors.textSecondary)),
          ],
          const SizedBox(height: FmSpace.s),
          Row(
            children: [
              if (onCall != null)
                Padding(
                  padding: const EdgeInsets.only(right: FmSpace.s),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: onCall,
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('전화'),
                  ),
                ),
              if (onMap != null)
                Padding(
                  padding: const EdgeInsets.only(right: FmSpace.s),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: onMap,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('카카오맵'),
                  ),
                ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: onTryBooking,
                child: const Text('예약 체험'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
