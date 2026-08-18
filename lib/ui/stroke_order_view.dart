import 'package:flutter/material.dart';

import '../kanjivg/stroke_order.dart';

/// 書き順を再生するお手本。
///
/// [progress] が 0 から 1 へ動くあいだに、1 画目から順に線が伸びていく。
/// いつ再生するかは呼び出し側が決める。
///
/// **画ごとに色を変える。** どこで 1 画が終わってどこから次が始まるのかは、
/// 同じ色で引くと分からない。交わる画（「あ」の 2 画目と 3 画目）では、
/// 引き終わった字を見ても切れ目が読めなくなる。番号と矢印も同じ色にして、
/// 番号とその画を目で結べるようにする。
class StrokeOrderView extends StatelessWidget {
  const StrokeOrderView({
    super.key,
    required this.order,
    required this.progress,
    this.showNumbers = false,
    this.surface = const Color(0xffffffff),
    this.faded = false,
  });

  final StrokeOrder order;
  final Animation<double> progress;

  /// 番号の下に敷く色。これを描く面と同じ色にする。
  final Color surface;

  /// なぞる下敷きとして薄く敷くか。
  ///
  /// 上から子供が書くので、下敷きは自分の線より弱くないといけない。
  /// 色は変えず、薄さだけを変える。1 画目が赤なら、なぞる下敷きも薄い赤。
  final bool faded;

  /// 画ごとの色。1 画目から順に使い、足りなければ先頭へ戻る。
  ///
  /// かなは多くても 4 画、漢字（L5）でも 20 画ほど。隣り合う画が同じ色に
  /// ならないことだけを守れればよいので、6 色で足りる。
  ///
  /// 順番そのものは番号が持っている。色は「どこで切れているか」を見せる
  /// ためのもので、色が読めなくても書き順は分かる。
  static const strokeColors = [
    Color(0xffd94f4f),
    Color(0xff3f7fd9),
    Color(0xff4f9e4f),
    Color(0xffe0862c),
    Color(0xff8a5fd0),
    Color(0xff2c9c9c),
  ];

  /// [index] 画目の色。
  Color colorOf(int index) {
    final color = strokeColors[index % strokeColors.length];
    return faded ? color.withValues(alpha: 0.28) : color;
  }

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
        colorOf: colorOf,
        showNumbers: showNumbers,
        surface: surface,
      ),
    );
  }
}

class _StrokeOrderPainter extends CustomPainter {
  _StrokeOrderPainter({
    required this.order,
    required this.progress,
    required this.colorOf,
    required this.showNumbers,
    required this.surface,
  }) : super(repaint: progress);

  final StrokeOrder order;
  final Animation<double> progress;
  final Color Function(int index) colorOf;
  final bool showNumbers;
  final Color surface;

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
      ..strokeJoin = StrokeJoin.round;

    // 進み具合を「何画目のどこまで」に読み替える。
    final head = progress.value * order.strokeCount;
    for (var i = 0; i < order.strokeCount; i++) {
      final drawn = (head - i).clamp(0.0, 1.0);
      if (drawn == 0) break;
      canvas.drawPath(
        drawn == 1 ? order.strokes[i] : order.partial(i, drawn),
        paint..color = colorOf(i),
      );
    }

    canvas.restore();

    if (showNumbers && progress.value >= 1) _paintOrderMarks(canvas, scale);
  }

  /// 画ごとの番号と、書き始める向きの矢印。
  ///
  /// 番号だけでは、どちらへ引くのか分からない画がある。0 は始点と終点が
  /// 重なるので、番号を見ても左回りか右回りか決まらない。
  ///
  /// 矢印は番号に添える。字の上ではなく外に出しておかないと、字形の一部に
  /// 見えて、なぞる子がその形ごと書いてしまう。
  ///
  /// 番号も矢印も拡大せず画面の解像度で描く。字形と一緒に引き伸ばすと潰れる。
  void _paintOrderMarks(Canvas canvas, double scale) {
    final fontSize = (StrokeOrder.viewBox * scale * 0.11).clamp(10.0, 28.0);

    for (var i = 0; i < order.strokeCount; i++) {
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: fontSize,
            height: 1,
            fontWeight: FontWeight.w700,
            color: colorOf(i),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final anchor = order.numberAnchor(i) * scale;
      final radius = label.height * 0.62;

      // 書き始めが線の上に来る画があるので、下に枠の地色を敷いて読めるようにする。
      canvas.drawCircle(anchor, radius, Paint()..color = surface);
      label.paint(canvas, anchor - Offset(label.width / 2, label.height / 2));

      _paintArrow(
        canvas,
        from: anchor,
        direction: order.startDirection(i),
        clearance: radius,
        size: fontSize,
        color: colorOf(i),
      );
    }
  }

  /// 番号のわきから、進む向きへ短い矢印を引く。軸と、塗った三角の頭。
  ///
  /// 色はその画と同じにする。番号・矢印・線の 3 つが同じ色で結び付く。
  void _paintArrow(
    Canvas canvas, {
    required Offset from,
    required Offset direction,
    required double clearance,
    required double size,
    required Color color,
  }) {
    final tail = from + direction * (clearance + size * 0.15);
    final tip = tail + direction * (size * 0.95);

    final head = size * 0.42;
    final half = size * 0.26;
    final base = tip - direction * head;
    final side = Offset(-direction.dy, direction.dx) * half;

    canvas
      ..drawLine(
        tail,
        base,
        Paint()
          ..color = color
          ..strokeWidth = size * 0.16
          ..strokeCap = StrokeCap.round,
      )
      ..drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(base.dx + side.dx, base.dy + side.dy)
          ..lineTo(base.dx - side.dx, base.dy - side.dy)
          ..close(),
        Paint()..color = color,
      );
  }

  @override
  bool shouldRepaint(_StrokeOrderPainter old) =>
      old.order != order ||
      old.progress != progress ||
      old.colorOf(0) != colorOf(0) ||
      old.showNumbers != showNumbers ||
      old.surface != surface;
}
