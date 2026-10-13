import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../shorts/shorts_upload_screen.dart';

const Map<String, String> kVisibility = {'PUBLIC': '전체 공개', 'FOLLOWERS': '팔로워만', 'PRIVATE': '나만 보기'};

/// 사진·글 게시물 작성. 사진은 스토리지에 직접 올린 뒤 게시물을 만든다.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _caption = TextEditingController();
  final List<XFile> _images = [];
  String _visibility = 'PUBLIC';
  bool _highlight = false;
  double? _progress;
  late final String _idempotencyKey = uuidV4();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final media = AppScope.read(context).features.value.media;
    if (!media) {
      showFmSnack(context, '사진 업로드는 아직 준비 중이에요 (스토리지 미설정)');
      return;
    }
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2048, maxHeight: 2048);
      if (picked.isEmpty) return;
      setState(() {
        _images.addAll(picked);
        if (_images.length > 10) _images.removeRange(10, _images.length);
      });
    } catch (e) {
      if (mounted) showFmSnack(context, '사진을 불러오지 못했어요. 사진 접근 권한을 확인해 주세요');
    }
  }

  Future<void> _submit() async {
    final text = _caption.text.trim();
    if (_images.isEmpty && text.isEmpty) {
      showFmSnack(context, '사진이나 글을 입력해 주세요');
      return;
    }
    final s = AppScope.read(context);
    try {
      List<String> keys = [];
      if (_images.isNotEmpty) {
        setState(() => _progress = 0);
        keys = await s.media.uploadFiles('POST_IMAGE', _images, onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        });
      }
      await s.social.create({
        'kind': _images.isEmpty ? 'TEXT' : 'PHOTO',
        'caption': text,
        'visibility': _visibility,
        'isHighlight': _highlight,
        'images': [for (final k in keys) {'objectKey': k}],
      }, _idempotencyKey);
      if (!mounted) return;
      showFmSnack(context, '게시했어요');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _progress = null);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = AppScope.of(context).features.value;
    return Scaffold(
      appBar: AppBar(title: const Text('새 게시물')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FmSpace.l),
          children: [
            TextField(
              controller: _caption,
              maxLength: 2200,
              minLines: 4,
              maxLines: 10,
              decoration: fmInputDecoration(label: '내용', hint: '오늘 경기는 어땠나요? #해시태그 를 붙여 보세요'),
            ),
            const SizedBox(height: FmSpace.s),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_images.length < 10)
                    _AddTile(icon: Icons.add_photo_alternate_outlined, label: '사진 ${_images.length}/10', onTap: _pick),
                  for (var i = 0; i < _images.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: FmSpace.s),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(FmRadius.control),
                            child: Image.file(File(_images[i].path), width: 96, height: 96, fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: 2,
                            top: 2,
                            child: InkWell(
                              onTap: () => setState(() => _images.removeAt(i)),
                              child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54,
                                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: FmSpace.m),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.movie_creation_outlined),
              title: const Text('하이라이트 영상 올리기'),
              subtitle: Text(features.video ? '세로 영상 90초 이하' : '영상 업로드 준비 중'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final done = await Navigator.of(context)
                    .push<bool>(MaterialPageRoute(builder: (_) => const ShortsUploadScreen()));
                if (done == true && context.mounted) Navigator.of(context).pop(true);
              },
            ),
            const Divider(),
            Row(
              children: [
                const Text('공개 범위', style: TextStyle(fontSize: 15)),
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
            const SizedBox(height: FmSpace.l),
            if (_progress != null) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: FmSpace.s),
              Text('사진 올리는 중 ${(_progress! * 100).round()}%', textAlign: TextAlign.center),
              const SizedBox(height: FmSpace.s),
            ],
            LoadingButton(label: '게시하기', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FmRadius.control),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: FmColors.surfaceMuted,
          borderRadius: BorderRadius.circular(FmRadius.control),
          border: Border.all(color: FmColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: FmColors.textSecondary),
            const SizedBox(height: FmSpace.xs),
            Text(label, style: const TextStyle(fontSize: 12, color: FmColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
