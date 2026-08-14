import 'dart:math' as math;

/// フォントの em 空間上の点。
class Pt {
  const Pt(this.x, this.y);

  final double x;
  final double y;

  Pt operator +(Pt other) => Pt(x + other.x, y + other.y);
  Pt operator -(Pt other) => Pt(x - other.x, y - other.y);
  Pt operator *(double scale) => Pt(x * scale, y * scale);

  double get length => math.sqrt(x * x + y * y);

  @override
  String toString() => 'Pt($x, $y)';

  @override
  bool operator ==(Object other) => other is Pt && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// 輪郭を構成する 1 セグメント。
///
/// 内部表現は 3 次ベジェで統一する。TTF 出力時のみ 2 次へ近似する。
sealed class Seg {
  const Seg();

  /// セグメントの終点。
  Pt get to;
}

class LineSeg extends Seg {
  const LineSeg(this.to);

  @override
  final Pt to;
}

class CubicSeg extends Seg {
  const CubicSeg(this.c1, this.c2, this.to);

  final Pt c1;
  final Pt c2;

  @override
  final Pt to;
}

/// 閉じた輪郭。最後のセグメントの終点から [start] へ暗黙に閉じる。
///
/// 巻き方向は TrueType の慣習（外周が時計回り）に従う。
class Contour {
  const Contour(this.start, this.segs);

  final Pt start;
  final List<Seg> segs;

  bool get isEmpty => segs.isEmpty;

  /// 各セグメントを (始点, セグメント) の組で辿る。
  Iterable<(Pt, Seg)> walk() sync* {
    var from = start;
    for (final seg in segs) {
      yield (from, seg);
      from = seg.to;
    }
  }

  /// 符号付き面積の 2 倍。正なら反時計回り。
  double get signedArea {
    var sum = 0.0;
    var from = start;
    for (final seg in segs) {
      sum += from.x * seg.to.y - seg.to.x * from.y;
      from = seg.to;
    }
    return sum;
  }

  bool get isClockwise => signedArea < 0;

  /// 巻き方向を反転した輪郭を返す。
  ///
  /// 内部表現は TrueType の慣習（外周が時計回り）で統一し、CFF 出力時に反転する。
  Contour reversed() {
    if (segs.isEmpty) return this;

    final newStart = segs.last.to;
    final newSegs = <Seg>[];
    for (var i = segs.length - 1; i >= 0; i--) {
      final seg = segs[i];
      final target = i == 0 ? start : segs[i - 1].to;
      newSegs.add(switch (seg) {
        LineSeg() => LineSeg(target),
        CubicSeg(:final c1, :final c2) => CubicSeg(c2, c1, target),
      });
    }
    return Contour(newStart, newSegs);
  }
}

/// 軸平行な境界矩形。
class Bounds {
  const Bounds(this.xMin, this.yMin, this.xMax, this.yMax);

  static const empty = Bounds(0, 0, 0, 0);

  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;

  /// 制御点の凸包から境界を求める。実際の曲線の範囲を必ず包含する。
  static Bounds ofContours(List<Contour> contours) {
    var xMin = double.infinity;
    var yMin = double.infinity;
    var xMax = double.negativeInfinity;
    var yMax = double.negativeInfinity;

    void add(Pt p) {
      if (p.x < xMin) xMin = p.x;
      if (p.y < yMin) yMin = p.y;
      if (p.x > xMax) xMax = p.x;
      if (p.y > yMax) yMax = p.y;
    }

    for (final contour in contours) {
      if (contour.isEmpty) continue;
      add(contour.start);
      for (final seg in contour.segs) {
        switch (seg) {
          case LineSeg():
            add(seg.to);
          case CubicSeg(:final c1, :final c2, :final to):
            add(c1);
            add(c2);
            add(to);
        }
      }
    }

    if (xMin == double.infinity) return empty;
    return Bounds(xMin, yMin, xMax, yMax);
  }

  Bounds union(Bounds other) {
    if (this == empty) return other;
    if (other == empty) return this;
    return Bounds(
      math.min(xMin, other.xMin),
      math.min(yMin, other.yMin),
      math.max(xMax, other.xMax),
      math.max(yMax, other.yMax),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Bounds &&
      other.xMin == xMin &&
      other.yMin == yMin &&
      other.xMax == xMax &&
      other.yMax == yMax;

  @override
  int get hashCode => Object.hash(xMin, yMin, xMax, yMax);

  @override
  String toString() => 'Bounds($xMin, $yMin, $xMax, $yMax)';
}
