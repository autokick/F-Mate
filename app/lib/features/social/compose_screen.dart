import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

const Map<String, String> kVisibility = {'PUBLIC': '전체 공개', 'FOLLOWERS': '팔로워만', 'PRIVATE': '나만 보기'};

const List<String> kSuggestedTags = ['풋살', '하이라이트', '골', '팀원모집', '주말풋살', '풋살일기'];

enum _Stage { edit, uploading, posting, processing, done }

/// 새 게시물: 영상(숏폼) 또는 사진 + 설명 · 해시태그 · 구장 태그 · 공개 범위.
/// 사진·영상은 스토리지에 직접 올린 뒤 게시물을 만든다.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.startWithVideo = false, this.venue});

  /// 열자마자 영상 고르기
  final bool startWithVideo;

  /// 미리 태그할 구장
  final ({int id, String name})? venue;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _caption = TextEditingController();
  final List<XFile> _images = [];
  XFile? _video;
  int _videoBytes = 0;
  String _visibility = 'PUBLIC';
  bool _highlight = true;
  ({int id, String name})? _venue;
  _Stage _stage = _Stage.edit;
  double _progress = 0;
  String? _error;
  CancelToken? _cancel;
  int? _videoId;
  Timer? _poll;
  // 시도마다 새 키: 실패 후 다시 올리면 새 게시물을 만들어야 한다
  String _idempotencyKey = uuidV4();

  static const int maxVideoBytes = 500 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _venue = widget.venue;
    if (widget.startWithVideo) WidgetsBinding.instance.addPostFrameCallback((_) => _pickVideo());
  }

  @override
  void dispose() {
    _caption.dispose();
    _cancel?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  bool get _hasMedia => _video != null || _images.isNotEmpty;

  Future<void> _pickVideo() async {
    final features = AppScope.read(context).features.value;
    if (!features.video) {
      showFmSnack(context, '지금은 영상을 올릴 수 없어요. 잠시 후 다시 시도해 주세요');
      return;
    }
    try {
      final f = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 90));
      if (f == null) return;
      final size = await f.length();
      if (size > maxVideoBytes) {
        if (mounted) showFmSnack(context, '500MB 이하 영상만 올릴 수 있어요');
        return;
      }
      setState(() {
        _video = f;
        _videoBytes = size;
        _images.clear();
        _error = null;
      });
    } catch (_) {
      if (mounted) showFmSnack(context, '영상을 불러오지 못했어요. 사진·동영상 접근 권한을 확인해 주세요');
    }
  }

  Future<void> _pickPhotos() async {
    final features = AppScope.read(context).features.value;
    if (!features.media) {
      showFmSnack(context, '지금은 사진을 올릴 수 없어요. 잠시 후 다시 시도해 주세요');
      return;
    }
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2048, maxHeight: 2048);
      if (picked.isEmpty) return;
      setState(() {
        _video = null;
        _images.addAll(picked);
        if (_images.length > 10) _images.removeRange(10, _images.length);
        _error = null;
      });
    } catch (_) {
      if (mounted) showFmSnack(context, '사진을 불러오지 못했어요. 사진 접근 권한을 확인해 주세요');
    }
  }

  void _addTag(String tag) {
    final t = '#$tag';
    final text = _caption.text;
    if (text.contains(t)) return;
    final next = text.isEmpty || text.endsWith(' ') ? '$text$t ' : '$text $t ';
    _caption.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    setState(() {});
  }

  Future<void> _chooseVenue() async {
    final picked = await showModalBottomSheet<({int id, String name})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const VenuePickerSheet(),
    );
    if (picked != null && mounted) setState(() => _venue = picked);
  }

  Future<void> _chooseVisibility() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in kVisibility.entries)
            ListTile(
              title: Text(e.value),
              trailing: e.key == _visibility ? const Icon(Icons.check_rounded, color: FmColors.brandDark) : null,
              onTap: () => Navigator.of(ctx).pop(e.key),
            ),
        ]),
      ),
    );
    if (v != null && mounted) setState(() => _visibility = v);
  }

  Future<void> _submit() async {
    final text = _caption.text.trim();
    if (!_hasMedia && text.isEmpty) {
      showFmSnack(context, '영상·사진을 고르거나 글을 입력해 주세요');
      return;
    }
    final s = AppScope.read(context);
    _idempotencyKey = uuidV4();
    setState(() {
      _error = null;
      _progress = 0;
      _stage = _hasMedia ? _Stage.uploading : _Stage.posting;
    });
    try {
      final body = <String, dynamic>{
        'caption': text,
        'visibility': _visibility,
        'isHighlight': _highlight,
        if (_venue != null) 'venueId': _venue!.id,
      };
      if (_video != null) {
        _cancel = CancelToken();
        _videoId = await s.media.uploadVideo(_video!, cancelToken: _cancel, onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        });
        if (!mounted) return;
        setState(() => _stage = _Stage.posting);
        await s.social.create({...body, 'kind': 'VIDEO', 'videoId': _videoId}, _idempotencyKey);
        if (!mounted) return;
        setState(() => _stage = _Stage.processing);
        _poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkVideo());
        return;
      }
      List<String> keys = [];
      if (_images.isNotEmpty) {
        keys = await s.media.uploadFiles('POST_IMAGE', _images, onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        });
      }
      if (!mounted) return;
      setState(() => _stage = _Stage.posting);
      await s.social.create({
        ...body,
        'kind': _images.isEmpty ? 'TEXT' : 'PHOTO',
        'images': [for (final k in keys) {'objectKey': k}],
      }, _idempotencyKey);
      if (!mounted) return;
      showFmSnack(context, '게시했어요');
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.edit;
        _error = e.code == 'CANCELED' ? null : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.edit;
        _error = ApiError.from(e).message;
      });
    }
  }

  Future<void> _checkVideo() async {
    final id = _videoId;
    if (id == null) return;
    try {
      final s = AppScope.read(context);
      final v = await s.media.videoStatus(id);
      if (!mounted) return;
      if (v.status == 'READY') {
        _poll?.cancel();
        setState(() => _stage = _Stage.done);
      } else if (v.status == 'FAILED') {
        _poll?.cancel();
        final reason = await s.media.videoFailureReason(id);
        if (mounted) {
          setState(() {
            _stage = _Stage.edit;
            _error = reason ?? '영상 처리에 실패했어요. 다른 영상으로 다시 시도해 주세요';
          });
        }
      }
    } catch (_) {
      // 일시적 네트워크 오류: 다음 주기에 다시 확인
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _stage != _Stage.edit;
    return PopScope(
      canPop: _stage != _Stage.uploading,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '닫기',
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              if (_stage == _Stage.uploading) {
                _cancel?.cancel();
                return;
              }
              Navigator.of(context).pop(_stage == _Stage.processing || _stage == _Stage.done);
            },
          ),
          title: const Text('새 게시물', style: TextStyle(fontSize: 17)),
          centerTitle: true,
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
        ),
        body: SafeArea(
          child: busy ? _progressView() : _form(),
        ),
      ),
    );
  }

  Widget _progressView() {
    switch (_stage) {
      case _Stage.uploading:
        return Padding(
          padding: const EdgeInsets.all(FmSpace.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('올리는 중 ${(_progress * 100).round()}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: FmSpace.l),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: _progress, minHeight: 8),
              ),
              if (_video != null) ...[
                const SizedBox(height: FmSpace.s),
                Text('${(_videoBytes / 1024 / 1024).toStringAsFixed(1)}MB',
                    style: const TextStyle(color: FmColors.textSecondary)),
              ],
              const SizedBox(height: FmSpace.xl),
              if (_video != null) OutlinedButton(onPressed: () => _cancel?.cancel(), child: const Text('취소')),
            ],
          ),
        );
      case _Stage.posting:
        return const LoadingState(label: '게시물을 만드는 중');
      case _Stage.processing:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const EmptyState(
              icon: Icons.hourglass_top_rounded,
              title: '영상을 다듬고 있어요',
              message: '1~2분 뒤 피드에 올라가요.\n이 화면을 닫아도 괜찮아요.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FmSpace.xl),
              child: OutlinedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('닫기')),
            ),
          ]),
        );
      case _Stage.done:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const EmptyState(icon: Icons.check_circle_rounded, title: '게시되었어요!'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FmSpace.xl),
              child: FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('확인')),
            ),
          ]),
        );
      case _Stage.edit:
        return const SizedBox.shrink();
    }
  }

  Widget _form() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.l, FmSpace.page, FmSpace.l),
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(FmSpace.m),
                  decoration:
                      BoxDecoration(color: FmColors.dangerSoft, borderRadius: BorderRadius.circular(FmRadius.control)),
                  child: Text(_error!, style: const TextStyle(color: FmColors.danger)),
                ),
                const SizedBox(height: FmSpace.m),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MediaPreview(
                    video: _video,
                    images: _images,
                    onPickVideo: _pickVideo,
                    onPickPhotos: _pickPhotos,
                    onClear: () => setState(() {
                      _video = null;
                      _images.clear();
                    }),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      key: const Key('compose_caption'),
                      controller: _caption,
                      maxLength: AppConfig.firebaseMode ? 400 : 2200,
                      minLines: 6,
                      maxLines: 10,
                      style: const TextStyle(fontSize: 16, height: 1.55),
                      decoration: const InputDecoration(
                        hintText: '오늘 경기는 어땠나요?',
                        border: InputBorder.none,
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FmSpace.m),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final t in kSuggestedTags)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Material(
                          color: FmColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(FmRadius.chip),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(FmRadius.chip),
                            onTap: () => _addTag(t),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              child: Text('#$t',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D4652))),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: FmSpace.l),
              const Divider(),
              _OptionRow(
                icon: Icons.location_on_outlined,
                iconColor: FmColors.brandOnSoft,
                iconBackground: FmColors.brandSoft,
                label: '구장 태그',
                value: _venue?.name ?? '함께 뛴 구장을 태그해 보세요',
                muted: _venue == null,
                onTap: _chooseVenue,
                trailing: _venue == null
                    ? null
                    : IconButton(
                        tooltip: '구장 태그 지우기',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => setState(() => _venue = null),
                      ),
              ),
              _OptionRow(
                icon: Icons.public_rounded,
                label: '공개 범위',
                value: kVisibility[_visibility]!,
                onTap: _chooseVisibility,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: FmColors.brandDark,
                title: const Text('하이라이트에 추가', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                subtitle: const Text('프로필의 하이라이트 탭에 모여요'),
                value: _highlight,
                onChanged: (v) => setState(() => _highlight = v),
              ),
              const SizedBox(height: FmSpace.s),
              if (AppConfig.firebaseMode)
                const Text('Firebase 무료 전시 모드에서는 공개 텍스트 게시물만 지원합니다. '
                    '사진·영상 업로드와 비공개 공개 범위는 아직 지원하지 않습니다.',
                    style: TextStyle(fontSize: 12, color: FmColors.textTertiary)),
              const Text('타인의 영상·음악 등 저작물을 무단으로 올리면 삭제될 수 있어요.',
                  style: TextStyle(fontSize: 12, color: FmColors.textTertiary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(FmSpace.page, FmSpace.s, FmSpace.page, FmSpace.l),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('compose_submit'),
              onPressed: _submit,
              child: const Text('올리기'),
            ),
          ),
        ),
      ],
    );
  }
}

/// 왼쪽 미리보기 칸: 비어 있으면 [영상] [사진] 고르기
class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.video,
    required this.images,
    required this.onPickVideo,
    required this.onPickPhotos,
    required this.onClear,
  });

  final XFile? video;
  final List<XFile> images;
  final VoidCallback onPickVideo;
  final VoidCallback onPickPhotos;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    const w = 108.0, h = 152.0;
    if (video == null && images.isEmpty) {
      Widget pick(IconData icon, String label, VoidCallback onTap) => Expanded(
            child: Material(
              color: FmColors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: FmColors.textPrimary),
                    const SizedBox(height: 2),
                    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          );
      return SizedBox(
        width: w,
        height: h,
        child: Column(children: [
          pick(Icons.videocam_outlined, '영상', onPickVideo),
          const SizedBox(height: 6),
          pick(Icons.photo_outlined, '사진', onPickPhotos),
        ]),
      );
    }
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: video != null
                ? Container(
                    color: const Color(0xFF17221D),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 40),
                  )
                : Image.file(File(images.first.path), fit: BoxFit.cover),
          ),
          if (images.length > 1)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: Text('${images.length}장', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          Positioned(
            right: 4,
            top: 4,
            child: Semantics(
              button: true,
              label: '선택 지우기',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: onClear,
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
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.iconColor = const Color(0xFF3D4652),
    this.iconBackground = FmColors.surfaceMuted,
    this.muted = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color iconColor;
  final Color iconBackground;
  final bool muted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: FmColors.divider))),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: iconBackground, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13, color: FmColors.textSecondary)),
                  Text(value,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
                          color: muted ? FmColors.textTertiary : FmColors.textPrimary)),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right_rounded, color: FmColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 구장 고르기 (가까운 순 + 이름 검색)
class VenuePickerSheet extends StatefulWidget {
  const VenuePickerSheet({super.key});

  @override
  State<VenuePickerSheet> createState() => _VenuePickerSheetState();
}

class _VenuePickerSheetState extends State<VenuePickerSheet> {
  String _q = '';
  Future<List<VenueCard>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<VenueCard>> _load() async {
    final s = AppScope.read(context);
    final r = await s.venues.search(
      q: _q,
      lat: AppConfig.defaultLat,
      lng: AppConfig.defaultLng,
      radiusKm: 50,
      pageSize: 30,
    );
    return r.items;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(FmSpace.page, 0, FmSpace.page, FmSpace.m),
            child: TextField(
              autofocus: false,
              textInputAction: TextInputAction.search,
              decoration: fmInputDecoration(label: '구장 이름 검색', prefixIcon: const Icon(Icons.search_rounded)),
              onSubmitted: (v) => setState(() {
                _q = v.trim();
                _future = _load();
              }),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<VenueCard>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LoadingState();
                final list = snap.data ?? const <VenueCard>[];
                if (list.isEmpty) return const EmptyState(icon: Icons.search_off_rounded, title: '구장을 찾지 못했어요');
                return ListView.builder(
                  controller: scroll,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final v = list[i];
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(v.name),
                      subtitle: Text(v.roadAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pop((id: v.id, name: v.name)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
