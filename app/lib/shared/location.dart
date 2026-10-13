import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/services.dart';
import '../features/settings/policy_screen.dart';
import 'widgets.dart';

/// 현재 위치 가져오기: 위치정보 이용 동의(로그인한 경우) → OS 권한 → 현재 위치.
/// 실패하거나 사용자가 거부하면 안내 문구를 띄우고 null 을 돌려준다.
/// 위치는 검색에만 쓰고 서버에 저장하지 않는다.
Future<Position?> locateMe(BuildContext context) async {
  final s = AppScope.read(context);
  final me = s.session.me;
  if (me != null && me.consents['LOCATION'] != true) {
    final agree = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('위치정보 이용 동의'),
        content: const Text('내 주변 구장을 찾기 위해 현재 위치를 사용해요. 위치는 검색에만 쓰고 저장하지 않아요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx)
                  .push(MaterialPageRoute(builder: (_) => const PolicyScreen(kind: PolicyKind.location))),
              child: const Text('약관 보기')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('동의')),
        ],
      ),
    );
    if (agree != true || !context.mounted) return null;
    try {
      s.session.updateMe(await s.account.saveConsents({'LOCATION': true}));
    } catch (e) {
      if (context.mounted) showError(context, e);
      return null;
    }
  }
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) showFmSnack(context, '기기의 위치 서비스를 켜 주세요');
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (context.mounted) {
        showFmSnack(
            context,
            perm == LocationPermission.deniedForever
                ? '설정 > 앱 > 권한에서 위치 권한을 허용해 주세요'
                : '위치 권한이 없어 지역 선택으로 찾아 주세요');
      }
      return null;
    }
    return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
  } catch (_) {
    if (context.mounted) showFmSnack(context, '현재 위치를 확인하지 못했어요');
    return null;
  }
}
