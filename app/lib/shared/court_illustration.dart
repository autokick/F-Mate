import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 구장 사진이 없을 때 보여주는 풋살 코트 일러스트 (위에서 내려다본 모습).
/// 실제 사진처럼 보이지 않게 그림으로 그리고, 큰 화면에서는 "일러스트" 표시를 붙인다.
/// 같은 구장은 항상 같은 색으로 나오도록 seed(구장 id)로 색을 고른다.
class CourtIllustration extends StatelessWidget {
  const CourtIllustration({super.key, required this.seed, required this.indoor, this.showLabel = false});

  final int seed;
  final bool indoor;

  /// 상세 화면처럼 크게 보일 때 왼쪽 아래에 "일러스트" 표시
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: indoor ? '실내 풋살 코트 일러스트' : '실외 풋살 코트 일러스트',
      image: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _CourtPainter(seed: seed, indoor: indoor)),
          if (showLabel)
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.brush_outlined, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(indoor ? '실내 코트 일러스트' : '실외 코트 일러스트',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CourtPainter extends CustomPainter {
  _CourtPainter({required this.seed, required this.indoor});

  final int seed;
  final bool indoor;

  // (코트 색, 바깥 색, 줄무늬 색)
  static const _outdoor = [
    (Color(0xFF2E7D32), Color(0xFF1B5E20), Color(0xFF388E3C)),
    (Color(0xFF33691E), Color(0xFF1F3F12), Color(0xFF3F7D25)),
    (Color(0xFF15803D), Color(0xFF14532D), Color(0xFF16A34A)),
  ];
  static const _indoor = [
    (Color(0xFF1E66B4), Color(0xFF0F3D6E), Color(0xFF2474C8)), // 파란 우레탄
    (Color(0xFF0F766E), Color(0xFF134E4A), Color(0xFF14857B)), // 청록 우레탄
    (Color(0xFFB7793F), Color(0xFF7A4A21), Color(0xFFC2884F)), // 마루
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final palette = (indoor ? _indoor : _outdoor)[rnd.nextInt(3)];
    final (court, outside, stripe) = palette;
    final w = size.width, h = size.height;

    // 바깥(코트 밖) 바닥
    canvas.drawRect(Offset.zero & size, Paint()..color = outside);

    // 코트 영역 (가로로 긴 직사각형, 비율 약 2:1)
    final margin = math.min(w, h) * 0.1;
    var cw = w - margin * 2, ch = h - margin * 2;
    if (cw / ch > 2.0) cw = ch * 2.0;
    if (cw / ch < 1.35) ch = cw / 1.35;
    final r = Rect.fromCenter(center: Offset(w / 2, h / 2), width: cw, height: ch);
    canvas.drawRect(r, Paint()..color = court);

    // 잔디 줄무늬(실외) / 바닥 결(실내)
    final stripes = indoor ? 14 : 8 + rnd.nextInt(3) * 2;
    final sw = r.width / stripes;
    final sp = Paint()..color = stripe.withValues(alpha: indoor ? 0.35 : 0.7);
    for (var i = 0; i < stripes; i += 2) {
      canvas.drawRect(Rect.fromLTWH(r.left + i * sw, r.top, sw, r.height), sp);
    }

    // 실내: 위쪽에 조명 빛 번짐
    if (indoor) {
      final glow = Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.18), Colors.transparent])
            .createShader(Rect.fromCircle(center: Offset(w / 2, r.top), radius: r.width * 0.6));
      canvas.drawRect(r, glow);
    }

    // 라인
    final lw = math.max(1.2, math.min(w, h) * 0.012);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = lw;
    canvas.drawRect(r, line);
    canvas.drawLine(Offset(r.center.dx, r.top), Offset(r.center.dx, r.bottom), line);
    final cr = r.height * 0.18;
    canvas.drawCircle(r.center, cr, line);
    canvas.drawCircle(r.center, lw * 1.2, Paint()..color = Colors.white.withValues(alpha: 0.85));

    // 페널티 구역 (풋살: 골대 앞 반원 모양)
    final pr = r.height * 0.32;
    canvas.drawArc(Rect.fromCircle(center: Offset(r.left, r.center.dy), radius: pr), -math.pi / 2, math.pi, false, line);
    canvas.drawArc(Rect.fromCircle(center: Offset(r.right, r.center.dy), radius: pr), math.pi / 2, math.pi, false, line);
    for (final x in [r.left + r.width * 0.12, r.right - r.width * 0.12]) {
      canvas.drawCircle(Offset(x, r.center.dy), lw, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }

    // 골대
    final gh = r.height * 0.22, gd = math.max(3.0, margin * 0.55);
    final goal = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = lw * 1.3;
    canvas.drawRect(Rect.fromLTWH(r.left - gd, r.center.dy - gh / 2, gd, gh), goal);
    canvas.drawRect(Rect.fromLTWH(r.right, r.center.dy - gh / 2, gd, gh), goal);

    // 공 (자리만 살짝 다르게)
    final ball = Offset(r.center.dx + (rnd.nextDouble() - 0.5) * r.width * 0.5,
        r.center.dy + (rnd.nextDouble() - 0.5) * r.height * 0.5);
    final br = math.max(2.5, math.min(w, h) * 0.035);
    canvas.drawCircle(ball.translate(br * 0.25, br * 0.35), br, Paint()..color = Colors.black.withValues(alpha: 0.25));
    canvas.drawCircle(ball, br, Paint()..color = Colors.white);
    canvas.drawCircle(ball, br * 0.42, Paint()..color = const Color(0xFF1F2937));
  }

  @override
  bool shouldRepaint(_CourtPainter old) => old.seed != seed || old.indoor != indoor;
}
