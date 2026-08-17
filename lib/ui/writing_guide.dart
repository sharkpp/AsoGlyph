import 'package:flutter/material.dart';

import '../model/char_set.dart';

/// 書き取り枠のマス目と十字補助線。
///
/// 字の大きさと位置が揃わないとフォントとして破綻するため、収集の質を
/// 左右する要素（SPEC 7.1）。漢字・かな用の正方枠。
class WritingGuide extends StatelessWidget {
  const WritingGuide({
    super.key,
    this.color = const Color(0xffd8d3c8),
    this.border = true,
    this.small = false,
  });

  final Color color;

  /// 外枠を引くか。すでに枠を持つ面へ敷くときは切る。
  final bool border;

  /// 小書きの字の枠を出すか。
  ///
  /// 書き取り面は em 空間にそのまま対応しており、書いた大きさがそのまま
  /// フォントの字形になる。小書きの字だけは枠を小さくして、その中に
  /// 書かせる（SPEC 5.3）。
  final bool small;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GuidePainter(color, border, small),
        size: Size.infinite,
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.color, this.border, this.small);

  final Color color;
  final bool border;
  final bool small;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final full = Rect.fromLTWH(0, 0, side, side);
    // 小書きの枠は左右中央・下揃え。大きい字と下端を揃える。
    final inner = small
        ? Rect.fromLTWH(
            side * (1 - smallKanaScale) / 2,
            side * (1 - smallKanaScale),
            side * smallKanaScale,
            side * smallKanaScale,
          )
        : full;

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (border) canvas.drawRect(full, line);

    if (small) {
      // 枠の外を薄く伏せる。線を足すより、書く場所が一目で分かる。
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(full),
          Path()..addRect(inner),
        ),
        Paint()..color = color.withValues(alpha: 0.3),
      );
      canvas.drawRect(inner, line);
    }

    // 十字は書く枠の中央に置く。小書きでは小さいほうの枠が基準になる。
    final guide = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _dashedLine(
      canvas,
      Offset(inner.center.dx, inner.top),
      Offset(inner.center.dx, inner.bottom),
      guide,
    );
    _dashedLine(
      canvas,
      Offset(inner.left, inner.center.dy),
      Offset(inner.right, inner.center.dy),
      guide,
    );
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
      old.color != color || old.border != border || old.small != small;
}
