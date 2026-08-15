import 'package:flutter/material.dart';

import '../kanjivg/stroke_order.dart';

/// 書き順を再生するお手本。
///
/// [progress] が 0 から 1 へ動くあいだに、1 画目から順に線が伸びていく。
/// いつ再生するかは呼び出し側が決める。
class StrokeOrderView extends StatelessWidget {
  const StrokeOrderView({
    super.key,
    required this.order,
    required this.progress,
    this.color = const Color(0xff6f665c),
  });

  final StrokeOrder order;
  final Animation<double> progress;
  final Color color;

  /// 1 画あたりの再生時間。子供が目で追える速さにする。
  static const perStroke = Duration(milliseconds: 700);

  /// [order] を頭から終わりまで再生するのにかかる時間。
  static Duration playbackOf(StrokeOrder order) => perStroke * order.strokeCount;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StrokeOrderPainter(
        order: order,
        progress: progress,
        color: color,
      ),
    );
  }
}

class _StrokeOrderPainter extends CustomPainter {
  _StrokeOrderPainter({
    required this.order,
    required this.progress,
    required this.color,
  }) : super(repaint: progress);

  final StrokeOrder order;
  final Animation<double> progress;
  final Color color;

  /// KanjiVG の座標系での線幅。太めのほうが幼児には見やすい。
  static const _strokeWidth = 5.5;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / StrokeOrder.viewBox;
    canvas
      ..save()
      ..scale(scale);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    // 進み具合を「何画目のどこまで」に読み替える。
    final head = progress.value * order.strokeCount;
    for (var i = 0; i < order.strokeCount; i++) {
      final drawn = (head - i).clamp(0.0, 1.0);
      if (drawn == 0) break;
      canvas.drawPath(
        drawn == 1 ? order.strokes[i] : order.partial(i, drawn),
        paint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokeOrderPainter old) =>
      old.order != order || old.progress != progress || old.color != color;
}
