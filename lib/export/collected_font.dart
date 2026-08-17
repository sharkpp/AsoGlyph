import 'dart:typed_data';

import '../font/font_builder.dart';
import '../store/sample_store.dart';
import '../trace/glyph_builder.dart';

/// 収集済みの文字を、それぞれの最新の筆跡からグリフに起こす。
///
/// [includeTraced] でなぞり書きを混ぜるかを決める。混ぜる場合はモードを
/// 問わず最新の筆跡を使う。
///
/// 未収集の文字はここに現れない。KanjiVG の字形で埋めるとフォントが
/// 二次的著作物になり、CC BY-SA での配布義務が生じるため（SPEC 6.3）。
Future<List<Glyph>> collectGlyphs(
  SampleStore store, {
  required bool includeTraced,
  void Function(int done, int total)? onProgress,
}) async {
  final chars = store.collectedChars(includeTraced: includeTraced).toList()
    ..sort();
  final glyphs = <Glyph>[];

  for (final char in chars) {
    final sample = await store.read(
      store.latestId(char, includeTraced: includeTraced)!,
    );
    glyphs.add(await buildGlyph(char: char, strokes: sample.strokes));
    onProgress?.call(glyphs.length, chars.length);
  }

  return glyphs;
}

/// 収集済みの文字だけを載せたフォントを作る。
Future<Uint8List> buildCollectedFont({
  required SampleStore store,
  required FontMetadata meta,
  required FontFormat format,
  required bool includeTraced,
  void Function(int done, int total)? onProgress,
}) async {
  return buildFont(
    meta: meta,
    glyphs: await collectGlyphs(
      store,
      includeTraced: includeTraced,
      onProgress: onProgress,
    ),
    format: format,
  );
}
