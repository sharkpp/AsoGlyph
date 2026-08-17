import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:path_parsing/path_parsing.dart';

/// KanjiVG 由来の書き順（SPEC 6）。
///
/// お手本の表示にだけ使う。生成するフォントは子供の筆跡だけから作り、
/// 未収集の字をこの字形で埋めることは決してしない（SPEC 6.3）。
class StrokeOrder {
  StrokeOrder(this.strokes)
    // 1 画は 1 本の連続した軌跡。分かれていたら書き順として扱えない。
    : _metrics = [for (final s in strokes) s.computeMetrics().single];

  /// 画順に並んだ 1 画ぶんの軌跡。座標系は KanjiVG のまま [viewBox] 四方。
  final List<Path> strokes;

  final List<PathMetric> _metrics;

  /// KanjiVG の座標系。em 1000 に直すときは 1000/[viewBox] 倍する（SPEC 6.2）。
  static const viewBox = 109.0;

  int get strokeCount => strokes.length;

  /// [index] 画目の、書き始めから [fraction]（0..1）までの部分。
  Path partial(int index, double fraction) {
    final metric = _metrics[index];
    return metric.extractPath(0, metric.length * fraction);
  }

  /// [index] 画目の番号を置く点。座標系は [viewBox] 四方のまま。
  ///
  /// KanjiVG の main.xml は画数ラベルの座標を持たないため自分で決める。
  /// 書き始めのまわりを一周して、**どの画からもいちばん離れた向き**を選ぶ。
  /// 向きを決め打ちすると、別の画の上に乗ってその線を隠してしまう
  /// （あ の 3 画目は、手前へ逃がすと 1 画目の横棒に乗る）。
  Offset numberAnchor(int index) {
    final start = _metrics[index].getTangentForOffset(0)!;
    const center = Offset(viewBox / 2, viewBox / 2);
    final outward = start.position - center;
    final away = outward.distance < 1 ? Offset.zero : outward / outward.distance;

    Offset? best;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < _numberDirections; i++) {
      final angle = 2 * pi * i / _numberDirections;
      final direction = Offset(cos(angle), sin(angle));
      final at = Offset(
        (start.position.dx + direction.dx * _numberRadius)
            .clamp(_margin, viewBox - _margin),
        (start.position.dy + direction.dy * _numberRadius)
            .clamp(_margin, viewBox - _margin),
      );

      // 線から遠いほど良い。同じくらいなら字の外側を選ぶ。
      final score =
          _distanceToInk(at) + (direction.dx * away.dx + direction.dy * away.dy);
      if (score > bestScore) {
        bestScore = score;
        best = at;
      }
    }
    return best!;
  }

  /// [index] 画目の、進む向きを示す矢印を置く場所と向き。
  ///
  /// 位置は書き終わりではなく書き始めの少し先。0 のように始点と終点が
  /// 重なる画は、終わりに矢印を立てても左回りか右回りか決まらない。
  ///
  /// さらに線から横へ逃がす。線の上に描くと字形の一部に見えてしまい、
  /// なぞる子がその形ごと書いてしまう。
  ({Offset at, double angle}) directionMark(int index) {
    final metric = _metrics[index];
    final on = metric.getTangentForOffset(
      min(_markOffset, metric.length * 0.35),
    )!;

    // 進む向きの左右どちらへ逃がすか。他の画から遠いほうを選ぶ。
    final normal = Offset(-on.vector.dy, on.vector.dx);
    var best = on.position;
    var bestScore = double.negativeInfinity;
    for (final side in [1.0, -1.0]) {
      final at = Offset(
        (on.position.dx + normal.dx * side * _markGap)
            .clamp(_margin, viewBox - _margin),
        (on.position.dy + normal.dy * side * _markGap)
            .clamp(_margin, viewBox - _margin),
      );
      final score = _distanceToInk(at);
      if (score > bestScore) {
        bestScore = score;
        best = at;
      }
    }
    return (at: best, angle: on.angle);
  }

  /// 全部の画を粗く点に開いたもの。番号の置き場所を選ぶのに使う。
  late final List<Offset> _ink = [
    for (final metric in _metrics)
      for (var d = 0.0; d <= metric.length; d += _inkSpacing)
        metric.getTangentForOffset(d)!.position,
  ];

  double _distanceToInk(Offset at) {
    var nearest = double.infinity;
    for (final point in _ink) {
      final d = (point - at).distanceSquared;
      if (d < nearest) nearest = d;
    }
    return sqrt(nearest);
  }

  static const _markOffset = 13.0;
  static const _markGap = 9.0;
  static const _numberDirections = 16;
  static const _numberRadius = 12.0;
  static const _inkSpacing = 2.0;
  static const _margin = 7.0;
}

/// 書き順データの置き場。
///
/// 収集対象の全字ぶんでも数十 KB しかないため、まとめて読んで持っておく。
class StrokeOrderLibrary {
  StrokeOrderLibrary._(this._byChar);

  final Map<String, StrokeOrder> _byChar;

  static const _asset = 'assets/kanjivg/strokes.json';

  static Future<StrokeOrderLibrary> load({AssetBundle? bundle}) async {
    final json = await (bundle ?? rootBundle).loadString(_asset);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return StrokeOrderLibrary._({
      for (final entry in decoded.entries)
        entry.key: StrokeOrder([
          for (final d in entry.value as List) _parsePath(d as String),
        ]),
    });
  }

  /// 書き順を持たない字もある（「」？ は KanjiVG に無い）。
  StrokeOrder? operator [](String char) => _byChar[char];
}

Path _parsePath(String d) {
  final proxy = _PathBuilder();
  writeSvgPathDataToPath(d, proxy);
  return proxy.path;
}

/// SVG パスの読み取り結果を [Path] に積む。
class _PathBuilder extends PathProxy {
  final path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}
