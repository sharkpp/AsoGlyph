import 'dart:math' as math;

import '../font/geometry.dart';

/// Ramer–Douglas–Peucker による折れ線の間引き。
///
/// マーチングスクエアの出力はセル 1 個ごとに点が立つため、そのまま曲線に当てると
/// 階段状のノイズを拾う。曲線を当てる前にここで落とす。
List<Pt> simplifyPolyline(List<Pt> points, double tolerance) {
  if (points.length <= 2) return points;

  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  _rdp(points, 0, points.length - 1, tolerance, keep);

  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

void _rdp(List<Pt> points, int first, int last, double tolerance, List<bool> keep) {
  if (last <= first + 1) return;

  var worst = -1.0;
  var worstIndex = first;
  for (var i = first + 1; i < last; i++) {
    final d = distanceToSegment(points[i], points[first], points[last]);
    if (d > worst) {
      worst = d;
      worstIndex = i;
    }
  }

  if (worst <= tolerance) return;
  keep[worstIndex] = true;
  _rdp(points, first, worstIndex, tolerance, keep);
  _rdp(points, worstIndex, last, tolerance, keep);
}

/// 閉じた多角形の間引き。
///
/// RDP は両端を固定するため、閉曲線にそのまま適用すると始点の取り方で結果が変わる。
/// 最初の点から最も遠い点を second anchor に選び、2 本の開いた折れ線として扱う。
List<Pt> simplifyClosed(List<Pt> polygon, double tolerance) {
  if (polygon.length <= 3) return polygon;

  var farthest = 0;
  var farthestDistance = -1.0;
  for (var i = 1; i < polygon.length; i++) {
    final d = (polygon[i] - polygon[0]).length;
    if (d > farthestDistance) {
      farthestDistance = d;
      farthest = i;
    }
  }

  final first = simplifyPolyline(polygon.sublist(0, farthest + 1), tolerance);
  final second = simplifyPolyline(
    [...polygon.sublist(farthest), polygon[0]],
    tolerance,
  );
  // 継ぎ目の点が重複するため、後半の先頭と末尾を落とす。
  return [...first, ...second.sublist(1, second.length - 1)];
}

/// 折れ線を角で分割する。
///
/// 3 次ベジェの当てはめは接線の連続を仮定するため、運筆の折り返しや線の端の
/// 角をまたいで当てると精度が出ない。先に切っておく。
///
/// 戻り値の各区間は、末尾の点が次の区間の先頭と一致する形で輪を一周する。
/// 閉曲線に角が無い場合は、始点を末尾にも足した 1 区間を返す。
List<List<Pt>> splitAtCorners(
  List<Pt> polygon, {
  required bool closed,
  double angleThreshold = math.pi / 3,
}) {
  if (polygon.length < 3) return [polygon];

  final corners = <int>[];
  final start = closed ? 0 : 1;
  final end = closed ? polygon.length : polygon.length - 1;
  for (var i = start; i < end; i++) {
    final prev = polygon[(i - 1 + polygon.length) % polygon.length];
    final current = polygon[i];
    final nextPoint = polygon[(i + 1) % polygon.length];
    if (_turnAngle(prev, current, nextPoint) > angleThreshold) corners.add(i);
  }

  if (closed) {
    // 角が無い滑らかな輪。始点へ戻る 1 本の開いた折れ線として扱う。
    if (corners.isEmpty) {
      return [
        [...polygon, polygon.first],
      ];
    }
    final segments = <List<Pt>>[];
    for (var i = 0; i < corners.length; i++) {
      final from = corners[i];
      final to = corners[(i + 1) % corners.length];
      final piece = <Pt>[];
      var index = from;
      do {
        piece.add(polygon[index]);
        index = (index + 1) % polygon.length;
      } while (index != to);
      piece.add(polygon[to]);
      if (piece.length >= 2) segments.add(piece);
    }
    return segments;
  }

  if (corners.isEmpty) return [polygon];
  final segments = <List<Pt>>[];
  var from = 0;
  for (final corner in corners) {
    segments.add(polygon.sublist(from, corner + 1));
    from = corner;
  }
  segments.add(polygon.sublist(from));
  return segments;
}

/// 3 点のなす進行方向の変化量（0 が直進、pi が折り返し）。
double _turnAngle(Pt prev, Pt current, Pt next) {
  final a = current - prev;
  final b = next - current;
  final lengthA = a.length;
  final lengthB = b.length;
  if (lengthA == 0 || lengthB == 0) return 0;
  final cos = ((a.x * b.x + a.y * b.y) / (lengthA * lengthB)).clamp(-1.0, 1.0);
  return math.acos(cos);
}

double distanceToSegment(Pt p, Pt a, Pt b) {
  final ab = b - a;
  final lengthSquared = ab.x * ab.x + ab.y * ab.y;
  if (lengthSquared == 0) return (p - a).length;
  final ap = p - a;
  final t = ((ap.x * ab.x + ap.y * ab.y) / lengthSquared).clamp(0.0, 1.0);
  return (p - (a + ab * t)).length;
}
