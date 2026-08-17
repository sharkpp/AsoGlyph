import 'package:flutter/material.dart';

import '../ink/stroke.dart';
import '../trace/stroke_rasterizer.dart';

/// 書いた運筆をそのまま見せる。
///
/// フォントの字形（輪郭）ではなく、子供が引いた線を出す。版を選び直すときは
/// 「どの日にどう書いたか」を見比べたいので、線のほうが分かりやすい。
class StrokePreview extends StatelessWidget {
  const StrokePreview({
    super.key,
    required this.strokes,
    this.emSize = 1000,
    this.color = const Color(0xff1a1a1a),
  });

  final List<Stroke> strokes;
  final double emSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _StrokePainter(strokes: strokes, emSize: emSize, color: color),
        size: Size.infinite,
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter({
    required this.strokes,
    required this.emSize,
    required this.color,
  });

  final List<Stroke> strokes;
  final double emSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 練習画面・フォント生成と同じ描き方を通す（SPEC 8.1）。
    paintStrokes(
      canvas: canvas,
      strokes: strokes,
      pixelSize: size.shortestSide,
      emSize: emSize,
      style: const StrokeStyle(),
      color: color,
    );
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.strokes != strokes || old.color != color;
}
