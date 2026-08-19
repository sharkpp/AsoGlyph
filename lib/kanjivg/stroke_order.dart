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

  /// [index] 画目の、[fraction]（0..1）から終わりまでの部分。
  ///
  /// なぞる下敷きを、ペン先が通ったところから消していくのに使う（SPEC 7.1）。
  Path rest(int index, double fraction) {
    final metric = _metrics[index];
    return metric.extractPath(metric.length * fraction, metric.length);
  }

  /// [index] 画目の長さ。座標系は [viewBox] 四方のまま。
  ///
  /// 子供の線がその画のどこまで進んだかを、長さの比で見るのに使う。
  double strokeLength(int index) => _metrics[index].length;

  /// [index] 画目を、等間隔の [count] 点に開く。座標系は [viewBox] 四方のまま。
  ///
  /// 書いた字とお手本を同じ形に揃えて比べるために使う（SPEC 7.3）。
  List<Offset> samplePoints(int index, int count) {
    final metric = _metrics[index];
    return [
      for (var i = 0; i < count; i++)
        metric
            .getTangentForOffset(
              metric.length * (count == 1 ? 0 : i / (count - 1)),
            )!
            .position,
    ];
  }

  /// [index] 画目の番号を置く点。座標系は [viewBox] 四方のまま。
  ///
  /// KanjiVG の main.xml は画数ラベルの座標を持たないため自分で決める。
  /// 書き始めのまわりを一周して、**どの画からもいちばん離れた向き**を選ぶ。
  /// 向きを決め打ちすると、別の画の上に乗ってその線を隠してしまう
  /// （あ の 3 画目は、手前へ逃がすと 1 画目の横棒に乗る）。
  Offset numberAnchor(int index) => _anchors[index];

  /// 画順に決めていく。あとの番号は、先に置いた番号からも離れるようにする。
  late final List<Offset> _anchors = () {
    final placed = <Offset>[];
    for (var i = 0; i < strokeCount; i++) {
      placed.add(_chooseAnchor(i, placed));
    }
    return placed;
  }();

  Offset _chooseAnchor(int index, List<Offset> placed) {
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

      // 線から遠いほど良い。同じくらいなら、書き始めの手前で字の外側を選ぶ。
      // 手前に置くと、番号に添えた矢印がそのまま書き始めを指す。
      final back =
          -(direction.dx * start.vector.dx + direction.dy * start.vector.dy);
      final out = direction.dx * away.dx + direction.dy * away.dy;
      var crowd = 0.0;
      for (final other in placed) {
        final gap = (other - at).distance;
        if (gap < _numberRadius) crowd += _numberRadius - gap;
      }
      final score = _distanceToInk(at) + back * 1.5 + out - crowd;
      if (score > bestScore) {
        bestScore = score;
        best = at;
      }
    }
    return best!;
  }

  /// [index] 画目を書き始める向き。長さ 1 のベクトルで返す。
  ///
  /// 接線ではなく、書き出しから少し進んだ点までを結んだ向き。あ の 3 画目は
  /// 出だしだけ下へ向かってから左へ払うので、接線を取ると「下」に見えてしまう。
  /// 人が「どちらへ書くか」と見るのは、この区間の流れのほう。
  ///
  /// [Tangent.angle] は y を反転した角度（`-atan2(dy, dx)`）を返すため使わない。
  /// この座標系は y が下向きで、そのまま描画に渡せるのはベクトルのほう。
  Offset startDirection(int index) {
    final metric = _metrics[index];
    final from = metric.getTangentForOffset(0)!.position;
    final to = metric
        .getTangentForOffset(min(_lookAhead, metric.length * 0.3))!
        .position;

    final along = to - from;
    if (along.distance < 0.01) {
      return metric.getTangentForOffset(0)!.vector;
    }
    return along / along.distance;
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

  static const _lookAhead = 22.0;
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
