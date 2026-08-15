import 'dart:typed_data';

import '../font/glyph.dart';
import '../ink/stroke.dart';
import '../model/char_set.dart';
import 'contour_tracer.dart';
import 'stroke_rasterizer.dart';

/// ラスタトレースの解像度。em 1000 に対して 1 単位あたり約 1 ピクセル。
const rasterSize = 1024;

const _tracer = ContourTracer();

/// 運筆 1 字ぶんをフォントのグリフにする（SPEC 8）。
///
/// 練習画面の表示と同じ `paintStrokes` を通してラスタ化するため、
/// 子供が見た線とフォントの字形が一致する。
Future<Glyph> buildGlyph({
  required String char,
  required List<Stroke> strokes,
  StrokeStyle style = const StrokeStyle(),
}) async {
  return _glyphOf(
    char,
    await rasterizeStrokes(
      strokes: strokes,
      imageSize: rasterSize,
      style: style,
    ),
  );
}

/// 清音の上に濁点を重ねて 1 つのグリフにする（SPEC 5.1）。
///
/// 2 つを別々に描いてから重ねるのは、線の太さを分けたいため。濁点は小さく
/// 置くので、清音と同じ太さで描くと塗り潰れてしまう。
Future<Glyph> buildComposedGlyph({
  required String char,
  required List<Stroke> base,
  required List<Stroke> mark,
  required double markScale,
  StrokeStyle style = const StrokeStyle(),
}) async {
  final alpha = await rasterizeStrokes(
    strokes: base,
    imageSize: rasterSize,
    style: style,
  );
  final markAlpha = await rasterizeStrokes(
    strokes: mark,
    imageSize: rasterSize,
    style: style.scaleWidth(markScale),
  );

  for (var i = 0; i < alpha.length; i++) {
    if (markAlpha[i] > alpha[i]) alpha[i] = markAlpha[i];
  }

  return _glyphOf(char, alpha);
}

Glyph _glyphOf(String char, Uint8List alpha) {
  final charSet = charSetOf(char);
  if (charSet == null) {
    throw ArgumentError.value(char, 'char', '文字種に属していない');
  }

  return Glyph(
    codePoint: char.runes.first,
    contours: _tracer.trace(alpha: alpha, imageSize: rasterSize),
    advanceWidth: charSet.advanceWidth,
  );
}
