import 'package:flutter/material.dart';

import '../social/compose_screen.dart';

/// 하이라이트 영상 올리기 = 새 게시물 화면에서 영상 고르기부터 시작
class ShortsUploadScreen extends StatelessWidget {
  const ShortsUploadScreen({super.key});

  @override
  Widget build(BuildContext context) => const ComposeScreen(startWithVideo: true);
}
