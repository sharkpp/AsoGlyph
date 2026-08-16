import 'dart:convert';
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
  /// KanjiVG の main.xml は画数ラベルの座標を持たないため、書き始めから
  /// 進む向きと逆へ少し逃がした位置を使う。線に重ならず、どの画の番号かも
  /// 取り違えにくい。
  Offset numberAnchor(int index) {
    final start = _metrics[index].getTangentForOffset(0)!;
    final anchor = start.position - start.vector * _numberOffset;
    // 端で書き始める画があるので、枠の外へ出さない。
    return Offset(
      anchor.dx.clamp(_numberMargin, viewBox - _numberMargin),
      anchor.dy.clamp(_numberMargin, viewBox - _numberMargin),
    );
  }

  static const _numberOffset = 7.0;
  static const _numberMargin = 6.0;
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
