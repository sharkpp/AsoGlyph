// KanjiVG から、このアプリが必要とするものだけを抜き出す。
//
//   dart run tool/extract_kanjivg.dart <kanjivg-YYYYMMDD.xml>
//
// 出すもの:
//   assets/kanjivg/strokes.json … 収集対象の字の運筆（お手本と なぞり書きに使う）
//   assets/kanjivg/dakuten.json … 濁点・半濁点の置き場所（SPEC 5.1）
//
// 元データは KanjiVG（CC BY-SA 3.0 / Ulrich Apel, https://kanjivg.tagaini.net/）。
// 出力もライセンス継承のため CC BY-SA 3.0 とし、このスクリプトごとリポジトリで
// 公開する（SPEC 6.3）。
//
// 全 6,702 字を同梱すると 6.4 MB になる。収集対象は多くても 1,200 字ほどで、
// 使わない字を抱える理由がないため、CharSet に載っている字だけを抜く。
// CharSet が増えたら、このスクリプトを流し直せば出力も追随する。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:asoglyph/compose/dakuten.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:path_parsing/path_parsing.dart';
import 'package:xml/xml.dart';

/// KanjiVG の名前空間。`kvg:element` に対象文字が入っている。
const _kvg = 'http://kanjivg.tagaini.net';

/// KanjiVG の viewBox は 0 0 109 109。em 1000 への倍率（SPEC 6.2）。
const _toEm = 1000 / 109;

const _strokesOutput = 'assets/kanjivg/strokes.json';
const _dakutenOutput = 'assets/kanjivg/dakuten.json';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('使い方: dart run tool/extract_kanjivg.dart <kanjivg.xml>');
    exit(64);
  }

  final kanjivg = _read(args.single);
  _writeStrokes(kanjivg);
  _writeDakutenPlacements(kanjivg);
}

/// 文字 → 画順に並んだ SVG パス。
Map<String, List<String>> _read(String path) {
  final document = XmlDocument.parse(File(path).readAsStringSync());
  final strokes = <String, List<String>>{};
  for (final kanji in document.rootElement.childElements) {
    final group = kanji.childElements.first;
    final char = group.getAttribute('element', namespaceUri: _kvg);
    if (char == null) continue;
    // 同じ字が複数の異体字として載ることがある。最初のものを正とする。
    strokes.putIfAbsent(
      char,
      () => kanji
          .findAllElements('path')
          .map((path) => path.getAttribute('d')!)
          .toList(),
    );
  }
  return strokes;
}

/// 書かせて集める字の運筆を出す。
void _writeStrokes(Map<String, List<String>> kanjivg) {
  final wanted = [
    for (final set in CharSet.values)
      if (set.collect) ...set.chars,
  ];
  final extracted = {
    for (final char in wanted)
      if (kanjivg.containsKey(char)) char: kanjivg[char]!,
  };

  final missing = wanted.where((char) => !kanjivg.containsKey(char));
  if (missing.isNotEmpty) {
    // 「」？ は KanjiVG に無い（SPEC 6.1）。自作するまでは書き順を出せない。
    stderr.writeln('KanjiVG に無い字: ${missing.join()}');
  }

  _write(_strokesOutput, extracted);
  stdout.writeln('運筆 ${extracted.length} / ${wanted.length} 字');
}

/// 濁点・半濁点をどこへ置くかを出す。
///
/// KanjiVG は濁音字を「清音の画 ＋ 濁点の画」として持っている（が = か 3 画 ＋ 2 画）。
/// 清音の画数から先が濁点なので、その範囲を囲む矩形を置き場所とする。
///
/// 出すのは矩形だけで、KanjiVG の濁点そのものは同梱しない。フォントに載るのは
/// 子供が書いた濁点でなければならない（SPEC 6.3）。
void _writeDakutenPlacements(Map<String, List<String>> kanjivg) {
  final placements = <String, List<double>>{};

  for (final char in CharSet.hiraganaVoiced.chars) {
    final parts = decomposeDakuten(char);
    if (parts == null) throw StateError('$char を分解できない');

    final voiced = kanjivg[char];
    final base = kanjivg[parts.base];
    if (voiced == null || base == null) {
      stderr.writeln('KanjiVG に無いため $char の置き場所を出せない');
      continue;
    }
    if (voiced.length <= base.length) {
      throw StateError('$char の画数が ${parts.base} を超えていない');
    }

    final box = _boundsOf(voiced.sublist(base.length));
    placements[char] = [box.left, box.bottom, box.right, box.top];
  }

  _write(_dakutenOutput, placements);
  stdout.writeln('濁点の置き場所 ${placements.length} 字');
}

/// SVG パス列を囲む矩形を em 空間（y 上向き）で返す。
EmBox _boundsOf(List<String> paths) {
  final bounds = _Bounds();
  for (final d in paths) {
    writeSvgPathDataToPath(d, bounds);
  }
  // KanjiVG は y 下向き。em 空間は y 上向きなので上下が入れ替わる。
  return EmBox(
    left: bounds.minX * _toEm,
    bottom: 1000 - bounds.maxY * _toEm,
    right: bounds.maxX * _toEm,
    top: 1000 - bounds.minY * _toEm,
  );
}

/// パスが実際に通る範囲を測る。
///
/// 制御点まで含めた外側の矩形で済ませると、半濁点の丸で横に 36% 広がる。
/// `dart:ui` の使えない素の Dart なので、3 次ベジェの極値は自分で解く。
class _Bounds extends PathProxy {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;

  var _x = 0.0;
  var _y = 0.0;

  void _see(double x, double y) {
    minX = math.min(minX, x);
    minY = math.min(minY, y);
    maxX = math.max(maxX, x);
    maxY = math.max(maxY, y);
  }

  @override
  void moveTo(double x, double y) {
    _see(_x = x, _y = y);
  }

  @override
  void lineTo(double x, double y) {
    _see(_x = x, _y = y);
  }

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    for (final t in _extrema(_x, x1, x2, x3)) {
      _see(_at(t, _x, x1, x2, x3), _at(t, _y, y1, y2, y3));
    }
    for (final t in _extrema(_y, y1, y2, y3)) {
      _see(_at(t, _x, x1, x2, x3), _at(t, _y, y1, y2, y3));
    }
    _see(_x = x3, _y = y3);
  }

  @override
  void close() {}
}

/// 3 次ベジェの [t] における値。
double _at(double t, double p0, double p1, double p2, double p3) {
  final u = 1 - t;
  return u * u * u * p0 +
      3 * u * u * t * p1 +
      3 * u * t * t * p2 +
      t * t * t * p3;
}

/// 3 次ベジェが折り返す t（0 < t < 1）。微分＝0 の解。
List<double> _extrema(double p0, double p1, double p2, double p3) {
  final a = -p0 + 3 * p1 - 3 * p2 + p3;
  final b = 2 * (p0 - 2 * p1 + p2);
  final c = -p0 + p1;

  if (a.abs() < 1e-9) {
    if (b.abs() < 1e-9) return const [];
    return [-c / b].where(_inside).toList();
  }

  final discriminant = b * b - 4 * a * c;
  if (discriminant < 0) return const [];
  final root = math.sqrt(discriminant);
  return [
    (-b + root) / (2 * a),
    (-b - root) / (2 * a),
  ].where(_inside).toList();
}

bool _inside(double t) => t > 0 && t < 1;

void _write(String path, Object data) {
  File(path).writeAsStringSync('${jsonEncode(data)}\n');
}
