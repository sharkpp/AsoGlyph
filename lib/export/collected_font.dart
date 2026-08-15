import 'dart:typed_data';

import '../compose/dakuten.dart';
import '../font/font_builder.dart';
import '../kanjivg/dakuten_placement.dart';
import '../model/char_set.dart';
import '../store/sample_store.dart';
import '../trace/glyph_builder.dart';

/// 収集済みの文字を、それぞれの最新の筆跡からグリフに起こす。
///
/// 濁音・半濁音は書かせず、清音に濁点を重ねて作る（SPEC 5.1）。
///
/// 未収集の文字はここに現れない。KanjiVG の字形で埋めるとフォントが
/// 二次的著作物になり、CC BY-SA での配布義務が生じるため（SPEC 6.3）。
Future<List<Glyph>> collectGlyphs(
  SampleStore store, {
  required DakutenPlacements placements,
  void Function(int done, int total)? onProgress,
}) async {
  final written = store.collectedChars.toList()..sort();
  final composed = composableChars(store, placements);
  final total = written.length + composed.length;
  final glyphs = <Glyph>[];

  for (final char in written) {
    final sample = await store.read(store.latestMaterialId(char)!);
    glyphs.add(await buildGlyph(char: char, strokes: sample.strokes));
    onProgress?.call(glyphs.length, total);
  }

  for (final char in composed) {
    final parts = decomposeDakuten(char)!;
    final base = await store.read(store.latestMaterialId(parts.base)!);
    final mark = await store.read(store.latestMaterialId(parts.mark)!);
    final placed = placeMark(mark.strokes, placements[char]!);
    glyphs.add(
      await buildComposedGlyph(
        char: char,
        base: base.strokes,
        mark: placed.strokes,
        markScale: placed.scale,
      ),
    );
    onProgress?.call(glyphs.length, total);
  }

  return glyphs;
}

/// 手元の字から合成できる濁音・半濁音。
///
/// 清音と濁点の両方が集まっていて、置き場所も分かっている字だけを作る。
List<String> composableChars(
  SampleStore store,
  DakutenPlacements placements,
) {
  return [
    for (final char in CharSet.hiraganaVoiced.chars)
      if (placements[char] != null)
        if (_hasAll(store, decomposeDakuten(char)!)) char,
  ];
}

bool _hasAll(SampleStore store, ({String base, String mark}) parts) =>
    store.latestMaterialId(parts.base) != null &&
    store.latestMaterialId(parts.mark) != null;

/// 収集済みの文字だけを載せたフォントを作る。
Future<Uint8List> buildCollectedFont({
  required SampleStore store,
  required DakutenPlacements placements,
  required FontMetadata meta,
  required FontFormat format,
  void Function(int done, int total)? onProgress,
}) async {
  return buildFont(
    meta: meta,
    glyphs: await collectGlyphs(
      store,
      placements: placements,
      onProgress: onProgress,
    ),
    format: format,
  );
}
