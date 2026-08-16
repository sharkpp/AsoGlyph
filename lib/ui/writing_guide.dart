import 'package:flutter/material.dart';

/// 書き取り枠のマス目と十字補助線。
///
/// 字の大きさと位置が揃わないとフォントとして破綻するため、収集の質を
/// 左右する要素（SPEC 7.1）。漢字・かな用の正方枠。
class WritingGuide extends StatelessWidget {
  const WritingGuide({
    super.key,
    this.color = const Color(0xffd8d3c8),
    this.border = true,
  });

  final Color color;

  /// 外枠を引くか。すでに枠を持つ面へ敷くときは切る。
  final bool border;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GuidePainter(color, border),
        size: Size.infinite,
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.color, this.border);

  final Color color;
  final bool border;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (border) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, side, side),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final guide = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _dashedLine(canvas, Offset(side / 2, 0), Offset(side / 2, side), guide);
    _dashedLine(canvas, Offset(0, side / 2), Offset(side, side / 2), guide);
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 10.0;
    const gap = 8.0;
    final total = (to - from).distance;
    final direction = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = (travelled + dash).clamp(0.0, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled = end + gap;
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.color != color || old.border != border;
}
