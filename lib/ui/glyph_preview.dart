import 'package:flutter/material.dart';

import '../font/geometry.dart';

/// 輪郭を塗りつぶしで表示する。
///
/// フォントに載る字形そのものを見せるため、運筆の線ではなく輪郭から描く。
/// ここで見えている形が、そのまま生成されるグリフになる。
class GlyphPreview extends StatelessWidget {
  const GlyphPreview({
    super.key,
    required this.contours,
    this.emSize = 1000,
    this.color = const Color(0xff1a1a1a),
  });

  final List<Contour> contours;
  final double emSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GlyphPainter(contours: contours, emSize: emSize, color: color),
        size: Size.infinite,
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({
    required this.contours,
    required this.emSize,
    required this.color,
  });

  final List<Contour> contours;
  final double emSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (contours.isEmpty) return;
    canvas.drawPath(
      contoursToPath(contours, emSize: emSize, pixelSize: size.shortestSide),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.contours != contours || old.color != color;
}

/// em 空間（y 上向き）の輪郭を、画面座標（y 下向き）のパスへ移す。
///
/// 塗り規則は nonzero。外周と穴で巻き方向が逆であることに依存する。
Path contoursToPath(
  List<Contour> contours, {
  required double emSize,
  required double pixelSize,
}) {
  final scale = pixelSize / emSize;
  Offset map(Pt p) => Offset(p.x * scale, (emSize - p.y) * scale);

  final path = Path()..fillType = PathFillType.nonZero;
  for (final contour in contours) {
    if (contour.isEmpty) continue;
    path.moveTo(map(contour.start).dx, map(contour.start).dy);
    for (final seg in contour.segs) {
      switch (seg) {
        case LineSeg(:final to):
          final p = map(to);
          path.lineTo(p.dx, p.dy);
        case CubicSeg(:final c1, :final c2, :final to):
          final a = map(c1);
          final b = map(c2);
          final p = map(to);
          path.cubicTo(a.dx, a.dy, b.dx, b.dy, p.dx, p.dy);
      }
    }
    path.close();
  }
  return path;
}
