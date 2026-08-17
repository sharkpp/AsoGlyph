import 'dart:typed_data';

import '../font/font_builder.dart';
import '../store/sample_store.dart';
import '../trace/glyph_builder.dart';

/// 収集済みの文字を、それぞれの最新の筆跡からグリフに起こす。
///
/// 未収集の文字はここに現れない。KanjiVG の字形で埋めるとフォントが
/// 二次的著作物になり、CC BY-SA での配布義務が生じるため（SPEC 6.3）。
Future<List<Glyph>> collectGlyphs(
  SampleStore store, {
  void Function(int done, int total)? onProgress,
}) async {
  final chars = store.collectedChars.toList()..sort();
  final glyphs = <Glyph>[];

  for (final char in chars) {
    final sample = await store.read(store.latestMaterialId(char)!);
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
  void Function(int done, int total)? onProgress,
}) async {
  return buildFont(
    meta: meta,
    glyphs: await collectGlyphs(store, onProgress: onProgress),
    format: format,
  );
}
