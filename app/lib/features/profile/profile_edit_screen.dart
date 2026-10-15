import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../shared/widgets.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AppServices _s = AppScope.read(context);
  late final TextEditingController _nickname = TextEditingController(text: _s.session.me?.nickname ?? '');
  late final TextEditingController _bio = TextEditingController(text: _s.session.me?.bio ?? '');
  late String? _position = _s.session.me?.preferredPosition;
  late String? _region = _s.session.me?.regionCode;
  late bool _private = _s.session.me?.isPrivate ?? false;
  bool _uploading = false;

  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _changeAvatar() async {
    if (!_s.features.value.media) {
      showFmSnack(context, '사진 업로드는 아직 준비 중이에요');
      return;
    }
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1024, maxHeight: 1024);
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final keys = await _s.media.uploadFiles('AVATAR', [f]);
      _s.session.updateMe(await _s.account.setAvatar(keys.first));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      final me = await _s.account.updateProfile({
        'nickname': _nickname.text.trim(),
        'bio': _bio.text.trim(),
        'preferredPosition': _position ?? '',
        'regionCode': _region ?? '',
        'isPrivate': _private,
      });
      _s.session.updateMe(me);
      if (mounted) {
        showFmSnack(context, '저장했어요');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).session.me;
    return Scaffold(
      appBar: AppBar(title: const Text('프로필 편집')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(FmSpace.l),
          children: [
            Center(
              child: Stack(
                children: [
                  AppAvatar(url: me?.avatarUrl, name: me?.nickname ?? '', size: 96),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton.filled(
                      tooltip: '프로필 사진 바꾸기',
                      onPressed: _uploading ? null : _changeAvatar,
                      icon: _uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.camera_alt_outlined, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            if (me?.avatarUrl != null)
              TextButton(
                onPressed: () async {
                  try {
                    _s.session.updateMe(await _s.account.setAvatar(null));
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('기본 이미지로'),
              ),
            const SizedBox(height: FmSpace.l),
            TextFormField(
                controller: _nickname, maxLength: 20, decoration: fmInputDecoration(label: '닉네임'), validator: Validators.nickname),
            TextFormField(controller: _bio, maxLength: 300, maxLines: 3, decoration: fmInputDecoration(label: '소개')),
            const SizedBox(height: FmSpace.s),
            const Text('선호 포지션', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: FmSpace.s),
            Wrap(spacing: FmSpace.s, runSpacing: FmSpace.s, children: [
              for (final e in kPositions.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _position == e.key,
                  onSelected: (on) => setState(() => _position = on ? e.key : null),
                ),
            ]),
            const SizedBox(height: FmSpace.l),
            const Text('주 활동 지역', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: FmSpace.s),
            Wrap(spacing: FmSpace.s, runSpacing: FmSpace.s, children: [
              for (final r in kRegions.skip(1))
                ChoiceChip(
                  label: Text(r.label),
                  selected: _region != null && r.codes.contains(_region),
                  onSelected: (on) => setState(() => _region = on ? r.codes.last : null),
                ),
            ]),
            const SizedBox(height: FmSpace.m),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('비공개 계정'),
              subtitle: Text(AppConfig.firebaseMode
                  ? 'Firebase 무료 전시 모드에서는 비공개 계정이 지원되지 않습니다'
                  : '승인한 팔로워만 내 게시물을 볼 수 있어요'),
              value: _private,
              onChanged: AppConfig.firebaseMode ? null : (v) => setState(() => _private = v),
            ),
            const SizedBox(height: FmSpace.l),
            LoadingButton(label: '저장', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
