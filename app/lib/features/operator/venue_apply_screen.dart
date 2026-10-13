import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../venues/venues_screen.dart';

/// 입점 신청 시도 코드 (강원·전북은 특별자치도 코드)
const Map<String, String> kSidoCodes = {
  '서울': '11', '부산': '26', '대구': '27', '인천': '28', '광주': '29', '대전': '30', '울산': '31', '세종': '36',
  '경기': '41', '강원': '51', '충북': '43', '충남': '44', '전북': '52', '전남': '46', '경북': '47', '경남': '48', '제주': '50',
};

class CourtDraft {
  CourtDraft({required this.name, required this.isIndoor, required this.surface, required this.sizeClass});

  String name;
  bool isIndoor;
  String surface;
  String sizeClass;

  Map<String, dynamic> toJson() => {'name': name, 'isIndoor': isIndoor, 'surface': surface, 'sizeClass': sizeClass};
}

/// 코트 추가·수정 대화상자
Future<CourtDraft?> showCourtDialog(BuildContext context, {CourtDraft? initial}) {
  final name = TextEditingController(text: initial?.name ?? '');
  var indoor = initial?.isIndoor ?? true;
  var surface = initial?.surface ?? 'ARTIFICIAL_TURF';
  var size = initial?.sizeClass ?? '5V5';
  return showDialog<CourtDraft>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(initial == null ? '코트 추가' : '코트 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, maxLength: 50, decoration: const InputDecoration(labelText: '코트 이름 (예: A코트)')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('실내'),
                value: indoor,
                onChanged: (v) => set(() => indoor = v),
              ),
              Row(children: [
                const SizedBox(width: 48, child: Text('바닥')),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: surface,
                    items: [for (final e in kSurfaces.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => set(() => surface = v ?? surface),
                  ),
                ),
              ]),
              Row(children: [
                const SizedBox(width: 48, child: Text('규격')),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: size,
                    items: [
                      for (final s in const ['4V4', '5V5', '6V6', '7V7'])
                        DropdownMenuItem(value: s, child: Text(s.replaceAll('V', ':')))
                    ],
                    onChanged: (v) => set(() => size = v ?? size),
                  ),
                ),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('취소')),
          TextButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(CourtDraft(name: name.text.trim(), isIndoor: indoor, surface: surface, sizeClass: size));
            },
            child: const Text('확인'),
          ),
        ],
      ),
    ),
  );
}

class VenueApplyScreen extends StatefulWidget {
  const VenueApplyScreen({super.key});

  @override
  State<VenueApplyScreen> createState() => _VenueApplyScreenState();
}

class _VenueApplyScreenState extends State<VenueApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _detail = TextEditingController();
  final _phone = TextEditingController();
  final _bizNo = TextEditingController();
  final _desc = TextEditingController();
  final _rules = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  String _sido = '경기';
  final Set<String> _facilities = {};
  final List<CourtDraft> _courts = [];
  final List<XFile> _photos = [];
  XFile? _document;
  double? _progress;

  @override
  void dispose() {
    for (final c in [_name, _address, _detail, _phone, _bizNo, _desc, _rules, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) showFmSnack(context, '위치 권한이 없어요. 좌표를 직접 입력해 주세요');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      setState(() {
        _lat.text = p.latitude.toStringAsFixed(6);
        _lng.text = p.longitude.toStringAsFixed(6);
      });
    } catch (_) {
      if (mounted) showFmSnack(context, '현재 위치를 확인하지 못했어요');
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_document == null) {
      showFmSnack(context, '사업자등록증 사진을 첨부해 주세요');
      return;
    }
    if (_courts.isEmpty) {
      showFmSnack(context, '코트를 1개 이상 추가해 주세요');
      return;
    }
    final s = AppScope.read(context);
    if (!s.features.value.media) {
      showFmSnack(context, '파일 업로드가 아직 준비 중이라 신청할 수 없어요 (스토리지 미설정)');
      return;
    }
    try {
      setState(() => _progress = 0);
      final docKeys = await s.media.uploadFiles('VENUE_DOCUMENT', [_document!],
          onProgress: (p) {
            if (mounted) setState(() => _progress = p * 0.4);
          });
      final photoKeys = _photos.isEmpty
          ? <String>[]
          : await s.media.uploadFiles('VENUE_PHOTO', _photos, onProgress: (p) {
              if (mounted) setState(() => _progress = 0.4 + p * 0.5);
            });
      await s.operator.apply({
        'name': _name.text.trim(),
        'roadAddress': _address.text.trim(),
        'detailAddress': _detail.text.trim(),
        'regionCode': '${kSidoCodes[_sido]}000',
        'latitude': double.parse(_lat.text.trim()),
        'longitude': double.parse(_lng.text.trim()),
        'phone': _phone.text.trim(),
        'businessRegNo': _bizNo.text.trim(),
        'description': _desc.text.trim(),
        'rules': _rules.text.trim(),
        'facilities': _facilities.toList(),
        'photoKeys': photoKeys,
        'documentKeys': docKeys,
        'courts': [for (final c in _courts) c.toJson()],
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('입점 신청 완료'),
          content: const Text('운영팀이 서류를 확인한 뒤 승인 결과를 알림으로 알려 드려요. 그동안 운영시간과 요금을 미리 설정해 둘 수 있어요.'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('확인'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _progress = null);
        showError(context, e);
      }
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? '입력해 주세요' : null;

  String? _coord(String? v, double min, double max) {
    final d = double.tryParse((v ?? '').trim());
    if (d == null || d < min || d > max) return '올바른 좌표를 입력해 주세요';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('구장 입점 신청')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(FmSpace.l),
            children: [
              const SectionTitle('기본 정보'),
              TextFormField(controller: _name, maxLength: 100, decoration: fmInputDecoration(label: '구장 이름'), validator: _required),
              const SizedBox(height: FmSpace.s),
              Row(children: [
                const Text('지역'),
                const SizedBox(width: FmSpace.m),
                DropdownButton<String>(
                  value: _sido,
                  items: [for (final k in kSidoCodes.keys) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (v) => setState(() => _sido = v ?? _sido),
                ),
              ]),
              TextFormField(controller: _address, decoration: fmInputDecoration(label: '도로명 주소'), validator: _required),
              const SizedBox(height: FmSpace.s),
              TextFormField(controller: _detail, decoration: fmInputDecoration(label: '상세 주소 (선택)')),
              const SizedBox(height: FmSpace.s),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: fmInputDecoration(label: '위도'),
                    validator: (v) => _coord(v, 33, 39.5),
                  ),
                ),
                const SizedBox(width: FmSpace.s),
                Expanded(
                  child: TextFormField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: fmInputDecoration(label: '경도'),
                    validator: (v) => _coord(v, 124, 132),
                  ),
                ),
              ]),
              TextButton.icon(
                onPressed: _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('구장에 있다면: 현재 위치로 입력'),
              ),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: fmInputDecoration(label: '구장 전화번호')),
              const SizedBox(height: FmSpace.s),
              TextFormField(
                controller: _bizNo,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
                decoration: fmInputDecoration(label: '사업자등록번호 (10자리)'),
                validator: (v) => (v ?? '').replaceAll('-', '').length == 10 ? null : '10자리를 입력해 주세요',
              ),
              const SizedBox(height: FmSpace.s),
              TextFormField(controller: _desc, maxLines: 3, maxLength: 1000, decoration: fmInputDecoration(label: '구장 소개 (선택)')),
              TextFormField(controller: _rules, maxLines: 3, maxLength: 2000, decoration: fmInputDecoration(label: '이용 규칙 (선택)')),
              const SectionTitle('편의시설'),
              Wrap(
                spacing: FmSpace.s,
                runSpacing: FmSpace.s,
                children: [
                  for (final e in {...kFacilityFilters, 'LOCKER': '락커', 'VEST_RENTAL': '조끼 대여', 'RESTROOM': '화장실', 'WATER': '정수기'}.entries)
                    FilterChip(
                      label: Text(e.value),
                      selected: _facilities.contains(e.key),
                      onSelected: (on) => setState(() => on ? _facilities.add(e.key) : _facilities.remove(e.key)),
                    ),
                ],
              ),
              SectionTitle('코트', trailing: TextButton.icon(
                onPressed: () async {
                  final c = await showCourtDialog(context);
                  if (c != null) setState(() => _courts.add(c));
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('추가'),
              )),
              if (_courts.isEmpty) const Text('코트를 추가해 주세요', style: TextStyle(color: FmColors.textSecondary)),
              for (var i = 0; i < _courts.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_courts[i].name),
                  subtitle: Text('${_courts[i].isIndoor ? '실내' : '실외'} · ${kSurfaces[_courts[i].surface]} · ${_courts[i].sizeClass.replaceAll('V', ':')}'),
                  trailing: IconButton(
                      tooltip: '코트 삭제', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => setState(() => _courts.removeAt(i))),
                ),
              const SectionTitle('사진 · 서류'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(_document == null ? '사업자등록증 사진 첨부 (필수)' : '사업자등록증: ${_document!.name}'),
                subtitle: const Text('운영팀 확인용으로만 쓰이고 공개되지 않아요'),
                onTap: () async {
                  final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
                  if (f != null) setState(() => _document = f);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_library_outlined),
                title: Text('구장 사진 ${_photos.length}/20'),
                onTap: () async {
                  final list = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2048);
                  setState(() {
                    _photos.addAll(list);
                    if (_photos.length > 20) _photos.removeRange(20, _photos.length);
                  });
                },
              ),
              if (_photos.isNotEmpty)
                SizedBox(
                  height: 72,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final p in _photos)
                      Padding(
                        padding: const EdgeInsets.only(right: FmSpace.s),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(p.path), width: 72, height: 72, fit: BoxFit.cover),
                        ),
                      ),
                  ]),
                ),
              const SizedBox(height: FmSpace.l),
              const Text('취소 정책은 기본값(72시간 전 100%, 24시간 전 50%, 이후 0%)으로 시작하고, 승인 후 구장 관리에서 바꿀 수 있어요.',
                  style: TextStyle(fontSize: 13, color: FmColors.textSecondary)),
              const SizedBox(height: FmSpace.l),
              if (_progress != null) ...[LinearProgressIndicator(value: _progress), const SizedBox(height: FmSpace.s)],
              LoadingButton(label: '입점 신청하기', onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
