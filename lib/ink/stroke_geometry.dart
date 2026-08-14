import 'dart:math' as math;

import 'stroke.dart';

/// 線幅の決め方と平滑化の設定。
class StrokeStyle {
  const StrokeStyle({
    this.baseWidth = 56,
    this.pressureRange = 0.5,
    this.speedRange = 0.4,
    this.referenceSpeed = 2.0,
    this.resampleSpacing = 5,
    this.smoothingWindow = 5,
  });

  /// em 単位の基準線幅。
  final double baseWidth;

  /// 筆圧で変化させる幅の割合。
  final double pressureRange;

  /// 速度で変化させる幅の割合。筆圧が取れない入力で使う。
  final double speedRange;

  /// この速度（em/ミリ秒）で線幅が下限になる。
  final double referenceSpeed;

  /// 再サンプルの間隔（em 単位）。
  ///
  /// マウス入力は 1 フレームあたりの移動量が大きく、入力点をそのまま結ぶと
  /// 折れ線の角と、区間ごとの線幅の段差が見えてしまう。
  final double resampleSpacing;

  /// 線幅を均す移動平均の窓幅（入力点の個数）。
  final int smoothingWindow;
}

/// 描画に使う 1 点。位置と、その点での線幅を持つ。
class RenderPoint {
  const RenderPoint(this.x, this.y, this.width);

  final double x;
  final double y;
  final double width;
}

/// 運筆を、等間隔で線幅の連続した点列へ整える。
///
/// 練習画面の表示もフォント生成のラスタ化も、必ずここを通す。
List<RenderPoint> renderPoints(Stroke stroke, StrokeStyle style) {
  final points = stroke.points;
  if (points.isEmpty) return const [];

  final widths = _smooth(strokeWidths(stroke, style), style.smoothingWindow);
  if (points.length == 1) {
    return [RenderPoint(points.first.x, points.first.y, widths.first)];
  }

  return _resample(points, widths, style.resampleSpacing);
}

/// 各入力点での線幅を em 単位で求める。
///
/// 筆圧が取れる入力（スタイラス）では筆圧を、取れない入力（指・マウス）では
/// 速度を使う。速いほど細くするのは、運筆の勢いを字形に残すため。
List<double> strokeWidths(Stroke stroke, StrokeStyle style) {
  final points = stroke.points;
  if (points.isEmpty) return const [];

  if (stroke.hasPressure) {
    return [
      for (final point in points)
        style.baseWidth *
            (1 - style.pressureRange + style.pressureRange * 2 * point.pressure)
                .clamp(1 - style.pressureRange, 1 + style.pressureRange),
    ];
  }

  // 速度は前後の区間から求める。端の点で片側しか無い場合はある側だけを使う。
  // 自分自身との差分（速度 0）で代用すると、書き始めが必ず最大幅になってしまう。
  final speeds = <double>[];
  for (var i = 0; i < points.length; i++) {
    final before = i > 0 ? _speedBetween(points[i - 1], points[i]) : null;
    final after = i < points.length - 1
        ? _speedBetween(points[i], points[i + 1])
        : null;
    speeds.add(
      switch ((before, after)) {
        (final a?, final b?) => (a + b) / 2,
        (final a?, null) => a,
        (null, final b?) => b,
        _ => 0.0,
      },
    );
  }

  return [
    for (final speed in speeds)
      style.baseWidth *
          (1 - style.speedRange * (speed / style.referenceSpeed).clamp(0.0, 1.0)),
  ];
}

double _speedBetween(InkPoint a, InkPoint b) {
  final dt = (b.t - a.t).abs();
  if (dt == 0) return 0;
  final distance = math.sqrt(
    math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2),
  );
  return distance / dt;
}

/// 移動平均。窓が入力点数を超える場合は全体の平均になる。
List<double> _smooth(List<double> values, int window) {
  if (values.length < 3 || window < 2) return values;
  final half = window ~/ 2;

  return [
    for (var i = 0; i < values.length; i++)
      () {
        final from = math.max(0, i - half);
        final to = math.min(values.length - 1, i + half);
        var sum = 0.0;
        for (var j = from; j <= to; j++) {
          sum += values[j];
        }
        return sum / (to - from + 1);
      }(),
  ];
}

/// Catmull-Rom で補間しながら細かく打ち直す。
///
/// 入力点を必ず通る補間なので、書いた形が動かない。
///
/// パラメータ化は重心（centripetal, alpha = 0.5）を使う。一様パラメータ化は
/// 点の間隔が不揃いだと大きくはみ出す性質があり、1 フレームあたりの移動量が
/// ばらつくマウス入力ではまさにその条件に当たる。重心パラメータ化なら
/// 尖点も自己交差も生じない。
List<RenderPoint> _resample(
  List<InkPoint> points,
  List<double> widths,
  double spacing,
) {
  final result = <RenderPoint>[
    RenderPoint(points.first.x, points.first.y, widths.first),
  ];

  for (var i = 0; i < points.length - 1; i++) {
    final p1 = (points[i].x, points[i].y);
    final p2 = (points[i + 1].x, points[i + 1].y);
    // 端では隣の点を反転させた仮想点を置く。同じ点を重ねるとノットが潰れる。
    final p0 = i > 0
        ? (points[i - 1].x, points[i - 1].y)
        : (2 * p1.$1 - p2.$1, 2 * p1.$2 - p2.$2);
    final p3 = i + 2 < points.length
        ? (points[i + 2].x, points[i + 2].y)
        : (2 * p2.$1 - p1.$1, 2 * p2.$2 - p1.$2);

    const t0 = 0.0;
    final t1 = t0 + _knotSpan(p0, p1);
    final t2 = t1 + _knotSpan(p1, p2);
    final t3 = t2 + _knotSpan(p2, p3);

    final distance = _distance(p1, p2);
    final steps = math.max(1, (distance / spacing).ceil());

    for (var step = 1; step <= steps; step++) {
      final s = step / steps;
      final t = t1 + (t2 - t1) * s;
      result.add(
        RenderPoint(
          _centripetal(p0.$1, p1.$1, p2.$1, p3.$1, t0, t1, t2, t3, t),
          _centripetal(p0.$2, p1.$2, p2.$2, p3.$2, t0, t1, t2, t3, t),
          widths[i] + (widths[i + 1] - widths[i]) * s,
        ),
      );
    }
  }

  return result;
}

double _distance((double, double) a, (double, double) b) =>
    math.sqrt(math.pow(b.$1 - a.$1, 2) + math.pow(b.$2 - a.$2, 2));

/// alpha = 0.5 のノット間隔。距離 0 でも 0 除算にならないよう下限を置く。
double _knotSpan((double, double) a, (double, double) b) =>
    math.max(math.sqrt(_distance(a, b)), 1e-4);

double _centripetal(
  double p0,
  double p1,
  double p2,
  double p3,
  double t0,
  double t1,
  double t2,
  double t3,
  double t,
) {
  final a1 = _lerpKnot(p0, p1, t0, t1, t);
  final a2 = _lerpKnot(p1, p2, t1, t2, t);
  final a3 = _lerpKnot(p2, p3, t2, t3, t);
  final b1 = _lerpKnot(a1, a2, t0, t2, t);
  final b2 = _lerpKnot(a2, a3, t1, t3, t);
  return _lerpKnot(b1, b2, t1, t2, t);
}

double _lerpKnot(double a, double b, double ta, double tb, double t) =>
    ((tb - t) * a + (t - ta) * b) / (tb - ta);
