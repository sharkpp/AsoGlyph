import 'dart:math' as math;

import '../ink/stroke.dart';

/// em 空間（0..1000、左下原点・y 上向き）の矩形。
///
/// `dart:ui` の Rect は y 下向きを前提に top < bottom を要求するため使わない。
class EmBox {
  const EmBox({
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
  });

  final double left;
  final double bottom;
  final double right;
  final double top;

  double get width => right - left;
  double get height => top - bottom;
  double get centerX => (left + right) / 2;
  double get centerY => (bottom + top) / 2;

  @override
  String toString() => 'EmBox($left, $bottom, $right, $top)';
}

/// 濁音・半濁音を、清音と濁点の組に分解する（SPEC 5.1）。
///
/// 合成できない字（清音そのもの、カタカナなど）には null を返す。
({String base, String mark})? decomposeDakuten(String char) {
  if (char.runes.length != 1) return null;
  final code = char.runes.first;

  // ひらがなの濁音は、清音の 1 つ次のコードポイントに並んでいる。
  // 半濁音は 2 つ次。は行だけが半濁音を持つ。
  for (final (offset, mark) in [(1, '゛'), (2, '゜')]) {
    final base = String.fromCharCode(code - offset);
    if (_voicedBases[mark]!.contains(base)) {
      return (base: base, mark: mark);
    }
  }
  return null;
}

const _voicedBases = {
  '゛': 'かきくけこさしすせそたちつてとはひふへほ',
  '゜': 'はひふへほ',
};

/// 子供が書いた濁点を、置き場所 [placement] に収まるよう移す。
///
/// 縦横おなじ倍率で入れて中央に置く。引き伸ばすと、その子の濁点の形が壊れる。
/// 返す [scale] は線幅を細める倍率にも使う。小さく置いた濁点を元の太さで
/// 描くと潰れてしまう。
({List<Stroke> strokes, double scale}) placeMark(
  List<Stroke> mark,
  EmBox placement,
) {
  final source = boundsOf(mark);
  if (source == null) return (strokes: mark, scale: 1);

  final scale = math.min(
    source.width > 0 ? placement.width / source.width : double.infinity,
    source.height > 0 ? placement.height / source.height : double.infinity,
  );
  // 点だけの濁点は伸縮しようがない。位置だけ合わせる。
  final factor = scale.isFinite ? scale : 1.0;

  return (
    strokes: [
      for (final stroke in mark)
        Stroke([
          for (final point in stroke.points)
            InkPoint(
              x: placement.centerX + (point.x - source.centerX) * factor,
              y: placement.centerY + (point.y - source.centerY) * factor,
              t: point.t,
              pressure: point.pressure,
            ),
        ]),
    ],
    scale: factor,
  );
}

/// 運筆全体を囲む矩形。点が 1 つも無ければ null。
EmBox? boundsOf(List<Stroke> strokes) {
  var left = double.infinity;
  var bottom = double.infinity;
  var right = double.negativeInfinity;
  var top = double.negativeInfinity;

  for (final stroke in strokes) {
    for (final point in stroke.points) {
      left = math.min(left, point.x);
      right = math.max(right, point.x);
      bottom = math.min(bottom, point.y);
      top = math.max(top, point.y);
    }
  }

  if (left > right) return null;
  return EmBox(left: left, bottom: bottom, right: right, top: top);
}
