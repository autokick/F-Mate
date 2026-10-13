import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../social/compose_screen.dart';

/// 숏폼 업로드: 영상 선택 → 스토리지 직접 업로드(진행률·취소·재시도) → 게시물 작성 → 서버 인코딩 대기
class ShortsUploadScreen extends StatefulWidget {
  const ShortsUploadScreen({super.key});

  @override
  State<ShortsUploadScreen> createState() => _ShortsUploadScreenState();
}

enum _Stage { pick, uploading, failed, posting, processing, done }

class _ShortsUploadScreenState extends State<ShortsUploadScreen> {
  final _caption = TextEditingController();
  XFile? _file;
  int _size = 0;
  _Stage _stage = _Stage.pick;
  double _progress = 0;
  String? _error;
  String _visibility = 'PUBLIC';
  bool _highlight = true;
  CancelToken? _cancel;
  int? _videoId;
  Timer? _poll;
  // 시도마다 새 키: 실패 후 다시 올리면 새 영상으로 새 게시물을 만들어야 한다
  String _idempotencyKey = uuidV4();

  static const int maxBytes = 500 * 1024 * 1024;

  @override
  void dispose() {
    _caption.dispose();
    _cancel?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final f = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 90));
      if (f == null) return;
      final size = await f.length();
      if (size > maxBytes) {
        if (mounted) showFmSnack(context, '500MB 이하 영상만 올릴 수 있어요');
        return;
      }
      setState(() {
        _file = f;
        _size = size;
        _error = null;
      });
    } catch (e) {
      if (mounted) showFmSnack(context, '영상을 불러오지 못했어요. 사진·동영상 접근 권한을 확인해 주세요');
    }
  }

  Future<void> _start() async {
    final f = _file;
    if (f == null) return;
    final s = AppScope.read(context);
    _cancel = CancelToken();
    _idempotencyKey = uuidV4();
    setState(() {
      _stage = _Stage.uploading;
      _progress = 0;
      _error = null;
    });
    try {
      _videoId = await s.media.uploadVideo(f, cancelToken: _cancel, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() => _stage = _Stage.posting);
      await s.social.create({
        'kind': 'VIDEO',
        'videoId': _videoId,
        'caption': _caption.text.trim(),
        'visibility': _visibility,
        'isHighlight': _highlight,
      }, _idempotencyKey);
      if (!mounted) return;
      setState(() => _stage = _Stage.processing);
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _checkStatus());
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = e.code == 'CANCELED' ? _Stage.pick : _Stage.failed;
        _error = e.code == 'CANCELED' ? null : e.message;
      });
    }
  }

  Future<void> _checkStatus() async {
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
            _stage = _Stage.failed;
            _error = reason ?? '영상 처리에 실패했어요';
          });
        }
      }
    } catch (_) {
      // 일시적 네트워크 오류: 다음 주기에 다시 확인
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = AppScope.of(context).features.value;
    return Scaffold(
      appBar: AppBar(title: const Text('하이라이트 영상 올리기')),
      body: SafeArea(
        child: !features.video
            ? const EmptyState(
                icon: Icons.construction_rounded,
                title: '영상 업로드는 준비 중이에요',
                message: '영상 저장소와 인코딩 서버가 연결되면 올릴 수 있어요.',
              )
            : ListView(
                padding: const EdgeInsets.all(FmSpace.l),
                children: [
                  if (_stage == _Stage.pick || _stage == _Stage.failed) ..._form(),
                  if (_stage == _Stage.uploading) ...[
                    const SizedBox(height: FmSpace.xl),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: FmSpace.m),
                    Text('업로드 중 ${(_progress * 100).round()}%  (${(_size / 1024 / 1024).toStringAsFixed(1)}MB)',
                        textAlign: TextAlign.center),
                    const SizedBox(height: FmSpace.l),
                    OutlinedButton(onPressed: () => _cancel?.cancel(), child: const Text('업로드 취소')),
                  ],
                  if (_stage == _Stage.posting) const LoadingState(label: '게시물을 만드는 중'),
                  if (_stage == _Stage.processing)
                    const EmptyState(
                      icon: Icons.hourglass_top_rounded,
                      title: '영상을 처리하고 있어요',
                      message: '화질 변환이 끝나면 자동으로 게시되고 알림을 보내 드려요.\n이 화면을 나가도 괜찮아요.',
                    ),
                  if (_stage == _Stage.done) ...[
                    const EmptyState(icon: Icons.check_circle_rounded, title: '게시되었어요!'),
                    FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('확인')),
                  ],
                ],
              ),
      ),
    );
  }

  List<Widget> _form() => [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(FmSpace.m),
            decoration: BoxDecoration(color: FmColors.dangerSoft, borderRadius: BorderRadius.circular(FmRadius.control)),
            child: Text(_error!, style: const TextStyle(color: FmColors.danger)),
          ),
          const SizedBox(height: FmSpace.m),
        ],
        FmCard(
          onTap: _stage == _Stage.pick || _stage == _Stage.failed ? _pick : null,
          child: Row(
            children: [
              const Icon(Icons.video_library_outlined, size: 32, color: FmColors.brandDark),
              const SizedBox(width: FmSpace.m),
              Expanded(
                child: Text(
                  _file == null ? '영상 선택 (90초 이하, mp4·mov, 500MB 이하)' : '${_file!.name}\n${(_size / 1024 / 1024).toStringAsFixed(1)}MB',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FmSpace.m),
        TextField(
          controller: _caption,
          maxLength: 2200,
          minLines: 2,
          maxLines: 5,
          decoration: fmInputDecoration(label: '캡션', hint: '#골 #풋살 해시태그를 붙여 보세요'),
        ),
        Row(
          children: [
            const Text('공개 범위'),
            const Spacer(),
            DropdownButton<String>(
              value: _visibility,
              underline: const SizedBox.shrink(),
              items: [for (final e in kVisibility.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _visibility = v ?? 'PUBLIC'),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('프로필 하이라이트에 표시'),
          value: _highlight,
          onChanged: (v) => setState(() => _highlight = v),
        ),
        const SizedBox(height: FmSpace.m),
        FilledButton(
          onPressed: _file == null ? null : _start,
          child: Text(_stage == _Stage.failed ? '다시 올리기' : '올리기'),
        ),
        const SizedBox(height: FmSpace.s),
        const Text('타인의 영상·음악 등 저작물을 무단으로 올리면 삭제될 수 있어요.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: FmColors.textSecondary)),
      ];
}
