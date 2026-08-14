import 'dart:typed_data';

import '../font/geometry.dart';

/// アルファ値の場から等値線を追跡して、閉じた多角形を取り出す。
///
/// 二値化せずアンチエイリアスされたアルファをそのまま使い、セル辺上を線形補間して
/// 交点を求める。Skia が描いた濃淡がサブピクセルの境界位置を持っているため、
/// 二値化するより滑らかな輪郭が得られる。
///
/// 戻り値の座標は画像空間（左上原点・y は下向き）のまま。em 空間への変換は
/// 呼び出し側が行う。
List<List<Pt>> traceContours({
  required Uint8List alpha,
  required int width,
  required int height,
  int threshold = 128,
}) {
  int sample(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    return alpha[y * width + x];
  }

  // 画像の縁で輪郭が閉じるよう、外側に 1 セル分の余白があるものとして走査する。
  final stride = width + 3;
  int edgeKey(int x, int y, bool horizontal) =>
      (((y + 1) * stride + (x + 1)) * 2) + (horizontal ? 0 : 1);

  final positions = <int, Pt>{};
  final next = <int, int>{};

  Pt horizontalCrossing(int x, int y) {
    final v0 = sample(x, y);
    final v1 = sample(x + 1, y);
    return Pt(x + (threshold - v0) / (v1 - v0), y.toDouble());
  }

  Pt verticalCrossing(int x, int y) {
    final v0 = sample(x, y);
    final v1 = sample(x, y + 1);
    return Pt(x.toDouble(), y + (threshold - v0) / (v1 - v0));
  }

  void connect(int fromKey, Pt fromPt, int toKey, Pt toPt) {
    positions[fromKey] = fromPt;
    positions[toKey] = toPt;
    next[fromKey] = toKey;
  }

  for (var y = -1; y < height; y++) {
    for (var x = -1; x < width; x++) {
      final a = sample(x, y);
      final b = sample(x + 1, y);
      final c = sample(x + 1, y + 1);
      final d = sample(x, y + 1);

      final index = (a >= threshold ? 1 : 0) |
          (b >= threshold ? 2 : 0) |
          (c >= threshold ? 4 : 0) |
          (d >= threshold ? 8 : 0);
      if (index == 0 || index == 15) continue;

      // 4 辺の交点。A=(x,y) B=(x+1,y) C=(x+1,y+1) D=(x,y+1) の順に囲む。
      final abKey = edgeKey(x, y, true);
      final bcKey = edgeKey(x + 1, y, false);
      final cdKey = edgeKey(x, y + 1, true);
      final daKey = edgeKey(x, y, false);

      Pt ab() => horizontalCrossing(x, y);
      Pt bc() => verticalCrossing(x + 1, y);
      Pt cd() => horizontalCrossing(x, y + 1);
      Pt da() => verticalCrossing(x, y);

      // 進行方向の左側が内側になるよう向きを決めてある。
      switch (index) {
        case 1:
          connect(abKey, ab(), daKey, da());
        case 2:
          connect(bcKey, bc(), abKey, ab());
        case 3:
          connect(bcKey, bc(), daKey, da());
        case 4:
          connect(cdKey, cd(), bcKey, bc());
        case 5:
          // 対角の曖昧なケース。中心の値で内側の連結を決める（漸近的決定法）。
          if ((a + b + c + d) / 4 >= threshold) {
            connect(abKey, ab(), bcKey, bc());
            connect(cdKey, cd(), daKey, da());
          } else {
            connect(abKey, ab(), daKey, da());
            connect(cdKey, cd(), bcKey, bc());
          }
        case 6:
          connect(cdKey, cd(), abKey, ab());
        case 7:
          connect(cdKey, cd(), daKey, da());
        case 8:
          connect(daKey, da(), cdKey, cd());
        case 9:
          connect(abKey, ab(), cdKey, cd());
        case 10:
          if ((a + b + c + d) / 4 >= threshold) {
            connect(daKey, da(), abKey, ab());
            connect(bcKey, bc(), cdKey, cd());
          } else {
            connect(bcKey, bc(), abKey, ab());
            connect(daKey, da(), cdKey, cd());
          }
        case 11:
          connect(bcKey, bc(), cdKey, cd());
        case 12:
          connect(daKey, da(), bcKey, bc());
        case 13:
          connect(abKey, ab(), bcKey, bc());
        case 14:
          connect(daKey, da(), abKey, ab());
      }
    }
  }

  // 各交点は入次数・出次数がともに 1 なので、辿るだけで閉ループになる。
  final contours = <List<Pt>>[];
  final visited = <int>{};
  for (final startKey in next.keys) {
    if (!visited.add(startKey)) continue;

    final loop = <Pt>[positions[startKey]!];
    var key = next[startKey]!;
    while (key != startKey) {
      if (!visited.add(key)) break; // 破綻した経路は捨てる
      loop.add(positions[key]!);
      final following = next[key];
      if (following == null) break;
      key = following;
    }
    if (loop.length >= 3) contours.add(loop);
  }

  return contours;
}

/// 多角形の符号付き面積の 2 倍。
double signedArea(List<Pt> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum;
}

/// 点が多角形の内部にあるか（交差数判定）。
bool containsPoint(List<Pt> polygon, Pt point) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.y > point.y) != (b.y > point.y) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// 入れ子の深さを数え、外周と穴の巻き方向を規約どおりに揃える。
///
/// 深さが偶数なら外周、奇数なら穴。内部表現の規約は TrueType 準拠で
/// 外周が時計回り（em 空間での符号付き面積が負）。
List<List<Pt>> normalizeWinding(List<List<Pt>> contours) {
  final result = <List<Pt>>[];
  for (var i = 0; i < contours.length; i++) {
    var depth = 0;
    for (var j = 0; j < contours.length; j++) {
      if (i == j) continue;
      if (containsPoint(contours[j], contours[i].first)) depth++;
    }
    final wantClockwise = depth.isEven;
    final isClockwise = signedArea(contours[i]) < 0;
    result.add(
      isClockwise == wantClockwise ? contours[i] : contours[i].reversed.toList(),
    );
  }
  return result;
}
