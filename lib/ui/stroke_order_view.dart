import 'dart:math' as math;

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
    this.showNumbers = false,
    this.surface = const Color(0xffffffff),
    this.arrowColor = const Color(0xffe8863c),
  });

  final StrokeOrder order;
  final Animation<double> progress;
  final Color color;

  /// 番号の下に敷く色。これを描く面と同じ色にする。
  final Color surface;

  /// 矢印の色。字と別の色にする。線と同じ色だと端の跳ねに紛れる。
  final Color arrowColor;

  /// 引き終わったあと、画ごとの番号を出すか。
  ///
  /// 動いているあいだは順番を目で追えるが、引き終わった字はどこから書くのか
  /// 分からない。止まった時点で番号に引き継ぐ。
  final bool showNumbers;

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
        showNumbers: showNumbers,
        surface: surface,
        arrowColor: arrowColor,
      ),
    );
  }
}

class _StrokeOrderPainter extends CustomPainter {
  _StrokeOrderPainter({
    required this.order,
    required this.progress,
    required this.color,
    required this.showNumbers,
    required this.surface,
    required this.arrowColor,
  }) : super(repaint: progress);

  final StrokeOrder order;
  final Animation<double> progress;
  final Color color;
  final bool showNumbers;
  final Color surface;
  final Color arrowColor;

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

    if (showNumbers && progress.value >= 1) _paintArrows(canvas);

    canvas.restore();

    if (showNumbers && progress.value >= 1) _paintNumbers(canvas, scale);
  }

  /// 書き始めの少し先に、進む向きの矢印を置く。
  ///
  /// 番号だけでは、どちらへ引くのか分からない画がある。0 は始点と終点が
  /// 重なるので、番号を見ても左回りか右回りか決まらない。
  void _paintArrows(Canvas canvas) {
    const length = 8.0;
    const spread = 0.55;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = arrowColor;

    for (var i = 0; i < order.strokeCount; i++) {
      final mark = order.directionMark(i);
      // 進む向きの逆へ、左右に開いた 2 本を引く。
      final back = mark.angle + math.pi;
      canvas.drawPath(
        Path()
          ..moveTo(
            mark.position.dx + math.cos(back - spread) * length,
            mark.position.dy + math.sin(back - spread) * length,
          )
          ..lineTo(mark.position.dx, mark.position.dy)
          ..lineTo(
            mark.position.dx + math.cos(back + spread) * length,
            mark.position.dy + math.sin(back + spread) * length,
          ),
        paint,
      );
    }
  }

  /// 番号は拡大せず、画面の解像度で描く。字形と一緒に引き伸ばすと潰れる。
  void _paintNumbers(Canvas canvas, double scale) {
    final fontSize = (StrokeOrder.viewBox * scale * 0.11).clamp(10.0, 28.0);

    for (var i = 0; i < order.strokeCount; i++) {
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: fontSize,
            height: 1,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final anchor = order.numberAnchor(i) * scale;
      final at = anchor - Offset(label.width / 2, label.height / 2);

      // 書き始めが線の上に来る画があるので、下に枠の地色を敷いて読めるようにする。
      canvas.drawCircle(anchor, label.height * 0.62, Paint()..color = surface);
      label.paint(canvas, at);
    }
  }

  @override
  bool shouldRepaint(_StrokeOrderPainter old) =>
      old.order != order ||
      old.progress != progress ||
      old.color != color ||
      old.showNumbers != showNumbers ||
      old.surface != surface ||
      old.arrowColor != arrowColor;
}
