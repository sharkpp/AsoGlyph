import 'dart:math' as math;

import 'geometry.dart';

/// 2 次ベジェ 1 本。始点は直前の点から引き継ぐ。
class Quad {
  const Quad(this.control, this.to);

  final Pt control;
  final Pt to;
}

/// 3 次ベジェを 2 次ベジェ列へ近似する。
///
/// TrueType の glyf は 2 次ベジェしか持てないため、TTF 出力時のみ通す。
/// 内部表現を 3 次で統一し、ここでだけ落とすことで OTF 側は無損失に保つ。
///
/// 単一の 2 次で近似したときの最大偏差は sqrt(3)/18 * |-p0 + 3p1 - 3p2 + p3| で
/// 抑えられる。許容誤差を超える場合は t=0.5 で分割して再帰する。分割ごとに
/// 偏差は 1/8 になるため、再帰は浅くて済む。
List<Quad> cubicToQuadratics(
  Pt p0,
  Pt p1,
  Pt p2,
  Pt p3, {
  double tolerance = 0.5,
  int maxDepth = 8,
}) {
  final out = <Quad>[];
  _convert(p0, p1, p2, p3, tolerance, maxDepth, out);
  return out;
}

const double _errorFactor = 0.09622504486493763; // sqrt(3) / 18

void _convert(
  Pt p0,
  Pt p1,
  Pt p2,
  Pt p3,
  double tolerance,
  int depth,
  List<Quad> out,
) {
  final d = Pt(
    -p0.x + 3 * p1.x - 3 * p2.x + p3.x,
    -p0.y + 3 * p1.y - 3 * p2.y + p3.y,
  );
  if (depth == 0 || _errorFactor * d.length <= tolerance) {
    // 端点を保ったまま制御点を 1 点に落とす。
    final control = Pt(
      (3 * p1.x - p0.x + 3 * p2.x - p3.x) / 4,
      (3 * p1.y - p0.y + 3 * p2.y - p3.y) / 4,
    );
    out.add(Quad(control, p3));
    return;
  }

  final p01 = _mid(p0, p1);
  final p12 = _mid(p1, p2);
  final p23 = _mid(p2, p3);
  final p012 = _mid(p01, p12);
  final p123 = _mid(p12, p23);
  final p0123 = _mid(p012, p123);

  _convert(p0, p01, p012, p0123, tolerance, depth - 1, out);
  _convert(p0123, p123, p23, p3, tolerance, depth - 1, out);
}

Pt _mid(Pt a, Pt b) => Pt((a.x + b.x) / 2, (a.y + b.y) / 2);

/// 近似誤差の上界。テストと診断で使う。
double quadraticApproximationError(Pt p0, Pt p1, Pt p2, Pt p3) {
  final dx = -p0.x + 3 * p1.x - 3 * p2.x + p3.x;
  final dy = -p0.y + 3 * p1.y - 3 * p2.y + p3.y;
  return _errorFactor * math.sqrt(dx * dx + dy * dy);
}
