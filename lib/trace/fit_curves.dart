import '../font/geometry.dart';
import 'simplify.dart';

/// 折れ線に 3 次ベジェを当てはめる。
///
/// Philip J. Schneider "An Algorithm for Automatically Fitting Digitized Curves"
/// (Graphics Gems, 1990) の手法。最小二乗で 1 本当てはめ、誤差が許容値を超えたら
/// 誤差最大の点で分割して再帰する。分割前に Newton-Raphson でパラメータを
/// 再割り当てすることで、分割数を抑える。
///
/// 内部表現を 3 次に統一しているため、ここでの出力がそのまま CFF に載る。
List<Seg> fitCubics(List<Pt> points, double error) {
  final unique = _dedupe(points);
  if (unique.length < 2) return const [];
  if (unique.length == 2) return [LineSeg(unique[1])];

  final leftTangent = _normalize(unique[1] - unique[0]);
  final rightTangent = _normalize(
    unique[unique.length - 2] - unique[unique.length - 1],
  );
  return _fit(unique, leftTangent, rightTangent, error);
}

List<Seg> _fit(List<Pt> points, Pt leftTangent, Pt rightTangent, double error) {
  if (points.length == 2) {
    return [LineSeg(points[1])];
  }

  var parameters = _chordLengthParameterize(points);
  var curve = _generateBezier(points, parameters, leftTangent, rightTangent);
  var (maxError, splitPoint) = _computeMaxError(points, curve, parameters);

  if (maxError < error) return [_toSeg(curve)];

  // 誤差がまだ小さいうちはパラメータの再割り当てで収束させる。
  if (maxError < error * error) {
    for (var i = 0; i < 20; i++) {
      parameters = _reparameterize(points, parameters, curve);
      curve = _generateBezier(points, parameters, leftTangent, rightTangent);
      (maxError, splitPoint) = _computeMaxError(points, curve, parameters);
      if (maxError < error) return [_toSeg(curve)];
    }
  }

  final centerTangent = _normalize(points[splitPoint - 1] - points[splitPoint + 1]);
  return [
    ..._fit(points.sublist(0, splitPoint + 1), leftTangent, centerTangent, error),
    ..._fit(
      points.sublist(splitPoint),
      Pt(-centerTangent.x, -centerTangent.y),
      rightTangent,
      error,
    ),
  ];
}

/// 制御点が端点を結ぶ直線に十分近ければ直線として出す。
/// 運筆の直線部分でグリフの点数を無駄に増やさないため。
Seg _toSeg(List<Pt> curve) {
  const flatness = 0.05;
  final chord = (curve[3] - curve[0]).length;
  if (chord > 0) {
    final d1 = distanceToSegment(curve[1], curve[0], curve[3]);
    final d2 = distanceToSegment(curve[2], curve[0], curve[3]);
    if (d1 < chord * flatness && d2 < chord * flatness) return LineSeg(curve[3]);
  }
  return CubicSeg(curve[1], curve[2], curve[3]);
}

/// 端点と両端の接線方向を固定したうえで、制御点までの距離を最小二乗で解く。
List<Pt> _generateBezier(
  List<Pt> points,
  List<double> parameters,
  Pt leftTangent,
  Pt rightTangent,
) {
  final first = points.first;
  final last = points.last;

  var c00 = 0.0;
  var c01 = 0.0;
  var c11 = 0.0;
  var x0 = 0.0;
  var x1 = 0.0;

  for (var i = 0; i < points.length; i++) {
    final u = parameters[i];
    final a0 = leftTangent * _b1(u);
    final a1 = rightTangent * _b2(u);

    c00 += _dot(a0, a0);
    c01 += _dot(a0, a1);
    c11 += _dot(a1, a1);

    final onLine = first * (_b0(u) + _b1(u)) + last * (_b2(u) + _b3(u));
    final residual = points[i] - onLine;
    x0 += _dot(a0, residual);
    x1 += _dot(a1, residual);
  }

  final detC = c00 * c11 - c01 * c01;
  final detX0 = x0 * c11 - c01 * x1;
  final detX1 = c00 * x1 - x0 * c01;

  var alphaLeft = detC.abs() < 1e-12 ? 0.0 : detX0 / detC;
  var alphaRight = detC.abs() < 1e-12 ? 0.0 : detX1 / detC;

  // 解が退化した場合は弦長の 1/3 という定石に落とす。
  final chord = (last - first).length;
  final epsilon = 1e-6 * chord;
  if (alphaLeft < epsilon || alphaRight < epsilon) {
    alphaLeft = chord / 3;
    alphaRight = chord / 3;
  }

  return [
    first,
    first + leftTangent * alphaLeft,
    last + rightTangent * alphaRight,
    last,
  ];
}

/// 弦長比によるパラメータの初期割り当て。
List<double> _chordLengthParameterize(List<Pt> points) {
  final parameters = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    parameters[i] = parameters[i - 1] + (points[i] - points[i - 1]).length;
  }
  final total = parameters.last;
  if (total == 0) {
    for (var i = 0; i < points.length; i++) {
      parameters[i] = i / (points.length - 1);
    }
    return parameters;
  }
  for (var i = 1; i < points.length; i++) {
    parameters[i] /= total;
  }
  return parameters;
}

List<double> _reparameterize(
  List<Pt> points,
  List<double> parameters,
  List<Pt> curve,
) {
  return [
    for (var i = 0; i < points.length; i++)
      _newtonRaphson(curve, points[i], parameters[i]),
  ];
}

/// 曲線上で与えた点に最も近いパラメータを 1 段だけ改善する。
double _newtonRaphson(List<Pt> curve, Pt point, double u) {
  final onCurve = _bezierAt(curve, u);
  final d = onCurve - point;

  // 1 階微分（2 次ベジェ）と 2 階微分（1 次ベジェ）。
  final q1 = [
    (curve[1] - curve[0]) * 3,
    (curve[2] - curve[1]) * 3,
    (curve[3] - curve[2]) * 3,
  ];
  final q2 = [(q1[1] - q1[0]) * 2, (q1[2] - q1[1]) * 2];

  final v = 1 - u;
  final d1 = q1[0] * (v * v) + q1[1] * (2 * v * u) + q1[2] * (u * u);
  final d2 = q2[0] * v + q2[1] * u;

  final numerator = _dot(d, d1);
  final denominator = _dot(d1, d1) + _dot(d, d2);
  if (denominator.abs() < 1e-12) return u;
  return (u - numerator / denominator).clamp(0.0, 1.0);
}

(double, int) _computeMaxError(
  List<Pt> points,
  List<Pt> curve,
  List<double> parameters,
) {
  var maxDistance = 0.0;
  var splitPoint = points.length ~/ 2;
  for (var i = 1; i < points.length - 1; i++) {
    final distance = (_bezierAt(curve, parameters[i]) - points[i]).length;
    if (distance > maxDistance) {
      maxDistance = distance;
      splitPoint = i;
    }
  }
  return (maxDistance, splitPoint);
}

Pt _bezierAt(List<Pt> curve, double u) =>
    curve[0] * _b0(u) + curve[1] * _b1(u) + curve[2] * _b2(u) + curve[3] * _b3(u);

double _b0(double u) => (1 - u) * (1 - u) * (1 - u);
double _b1(double u) => 3 * u * (1 - u) * (1 - u);
double _b2(double u) => 3 * u * u * (1 - u);
double _b3(double u) => u * u * u;

double _dot(Pt a, Pt b) => a.x * b.x + a.y * b.y;

Pt _normalize(Pt v) {
  final length = v.length;
  if (length == 0) return const Pt(0, 0);
  return Pt(v.x / length, v.y / length);
}

/// 同一点が連続するとパラメータ化が破綻するため落とす。
List<Pt> _dedupe(List<Pt> points) {
  final result = <Pt>[];
  for (final point in points) {
    if (result.isEmpty || (point - result.last).length > 1e-9) result.add(point);
  }
  return result;
}
