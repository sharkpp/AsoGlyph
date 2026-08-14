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
  final charSet = charSetOf(char);
  if (charSet == null) {
    throw ArgumentError.value(char, 'char', '収集対象の文字ではない');
  }

  final alpha = await rasterizeStrokes(
    strokes: strokes,
    imageSize: rasterSize,
    style: style,
  );

  return Glyph(
    codePoint: char.runes.first,
    contours: _tracer.trace(alpha: alpha, imageSize: rasterSize),
    advanceWidth: charSet.advanceWidth,
  );
}
