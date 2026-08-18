/// 書いた字を測る（SPEC 7.3）。
///
/// 測るのは**出題の重み付けのため**であって、フォントに載せるかを決める
/// ためではない（SPEC 1）。ここが混ざると、整った字だけが残るフォントに
/// なってしまい、この製品の中核が失われる。
///
/// 母集団は本人の履歴のみ。全ユーザー統計は採らない（SPEC 7.3）。
library;

import 'dart:math';
import 'dart:ui';

import '../ink/stroke.dart';
import '../kanjivg/stroke_order.dart';
import '../model/score.dart';

/// 1 画を何点に開いて比べるか。
const _samples = 16;

/// この距離だけずれたら形の近さは 0 になる（em 空間）。
///
/// 250 は em の 1/4。4 歳の字は線 1 本ぶん平気でずれるので、厳しくすると
/// 全部の字が同じ点になり、重み付けに使えなくなる。
const _shapeTolerance = 250.0;

/// 書いた字を測る。書き順データが無い字では、形と画数は測らない。
Score scoreStrokes({
  required List<Stroke> strokes,
  required StrokeOrder? model,
  int retries = 0,
}) {
  final written = _resampleAll(strokes);
  final duration = strokes.fold(0, (sum, stroke) => sum + stroke.duration);

  if (model == null || written.isEmpty) {
    return Score(
      shape: null,
      strokes: null,
      fit: null,
      durationMs: duration,
      retries: retries,
    );
  }

  final reference = modelPoints(model);

  return Score(
    shape: (1 - _meanDistance(written, reference) / _shapeTolerance).clamp(
      0.0,
      1.0,
    ),
    strokes: _strokeCountScore(written.length, reference.length),
    fit: _fitScore(written, reference),
    durationMs: duration,
    retries: retries,
  );
}

/// 鏡文字か、明らかな書き損じか（SPEC 4.1）。
///
/// **ここだけがフォントへの採否に効く。** 判定はきつくしない。取りこぼした
/// 鏡文字が 1 字混じるほうが、その子の字が 1 字 消えるより良い。
bool detectRejected({
  required List<Stroke> strokes,
  required StrokeOrder? model,
}) {
  final written = _resampleAll(strokes);
  if (model == null || written.isEmpty) return false;

  final reference = modelPoints(model);

  // なぐりがき。画がやたら多いか、線の総延長がお手本より桁違いに長い。
  final modelLength = _totalLength(reference);
  if (written.length > reference.length * 2 + 2) return true;
  if (modelLength > 0 && _totalLength(written) > modelLength * 3) return true;

  // 鏡文字。左右を返したほうがはるかによく合うときだけ。
  final upright = _meanDistance(written, reference);
  final mirrored = _meanDistance(written, [
    for (final stroke in reference)
      [for (final point in stroke) Offset(1000 - point.dx, point.dy)],
  ]);
  return upright > _shapeTolerance * 0.6 && mirrored < upright * 0.6;
}

/// お手本を em 空間（0..1000、左下原点・y 上向き）の点列に開く。
///
/// KanjiVG は 109 四方・y 下向き。em 1000 への正規化は 1000/109 倍（SPEC 6.2）。
List<List<Offset>> modelPoints(StrokeOrder model) => [
  for (var i = 0; i < model.strokeCount; i++)
    [
      for (final point in model.samplePoints(i, _samples))
        Offset(
          point.dx * 1000 / StrokeOrder.viewBox,
          1000 - point.dy * 1000 / StrokeOrder.viewBox,
        ),
    ],
];

List<List<Offset>> _resampleAll(List<Stroke> strokes) => [
  for (final stroke in strokes)
    if (stroke.points.isNotEmpty) _resample(stroke, _samples),
];

/// 画を等間隔の [count] 点に開く。点の粗さが違っても比べられるようにする。
List<Offset> _resample(Stroke stroke, int count) {
  final points = [for (final p in stroke.points) Offset(p.x, p.y)];
  if (points.length == 1) return List.filled(count, points.first);

  final lengths = <double>[0];
  for (var i = 1; i < points.length; i++) {
    lengths.add(lengths.last + (points[i] - points[i - 1]).distance);
  }
  final total = lengths.last;
  if (total == 0) return List.filled(count, points.first);

  final out = <Offset>[];
  var index = 1;
  for (var i = 0; i < count; i++) {
    final target = total * i / (count - 1);
    while (index < lengths.length - 1 && lengths[index] < target) {
      index++;
    }
    final span = lengths[index] - lengths[index - 1];
    final t = span == 0 ? 0.0 : (target - lengths[index - 1]) / span;
    out.add(Offset.lerp(points[index - 1], points[index], t)!);
  }
  return out;
}

/// 対応する画どうしの平均距離（em 空間）。
///
/// 画の数が違うときは、揃っているところまでで測る。足りない・多いぶんは
/// 画数のほうで測っているので、二重には引かない。
///
/// 書き出しの向きが逆でも形は同じなので、前からと後ろからの近いほうを採る。
/// 「い」を下から書く子の字を、形が違うことにはしない。
double _meanDistance(List<List<Offset>> written, List<List<Offset>> reference) {
  final pairs = min(written.length, reference.length);
  if (pairs == 0) return double.infinity;

  var total = 0.0;
  for (var i = 0; i < pairs; i++) {
    total += min(
      _strokeDistance(written[i], reference[i]),
      _strokeDistance(written[i].reversed.toList(), reference[i]),
    );
  }
  return total / pairs;
}

double _strokeDistance(List<Offset> a, List<Offset> b) {
  var total = 0.0;
  for (var i = 0; i < a.length; i++) {
    total += (a[i] - b[i]).distance;
  }
  return total / a.length;
}

/// 画数の一致。
double _strokeCountScore(int written, int expected) {
  if (expected == 0) return 1;
  return (1 - (written - expected).abs() / expected).clamp(0.0, 1.0);
}

/// 枠への収まり。お手本と同じ大きさ・位置に書けているか。
double _fitScore(List<List<Offset>> written, List<List<Offset>> reference) {
  final a = _bounds(written);
  final b = _bounds(reference);
  if (a == null || b == null) return 0;

  final offset = (a.center - b.center).distance / 500;
  final size = ((a.width - b.width).abs() + (a.height - b.height).abs()) / 1000;
  return (1 - offset - size).clamp(0.0, 1.0);
}

Rect? _bounds(List<List<Offset>> strokes) {
  double? left, top, right, bottom;
  for (final stroke in strokes) {
    for (final point in stroke) {
      left = left == null ? point.dx : min(left, point.dx);
      right = right == null ? point.dx : max(right, point.dx);
      top = top == null ? point.dy : min(top, point.dy);
      bottom = bottom == null ? point.dy : max(bottom, point.dy);
    }
  }
  if (left == null) return null;
  return Rect.fromLTRB(left, top!, right!, bottom!);
}

double _totalLength(List<List<Offset>> strokes) {
  var total = 0.0;
  for (final stroke in strokes) {
    for (var i = 1; i < stroke.length; i++) {
      total += (stroke[i] - stroke[i - 1]).distance;
    }
  }
  return total;
}
