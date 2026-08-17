import 'dart:typed_data';

import '../font/font_builder.dart';
import '../model/font_recipe.dart';
import '../store/sample_store.dart';
import '../trace/glyph_builder.dart';
import 'resolve_recipe.dart';

/// レシピが指した試行を、それぞれグリフに起こす。
///
/// [includeTraced] でなぞり書きを混ぜるかを決める。混ぜる場合はモードを
/// 問わず最新の筆跡を使う（SPEC 7.7）。
///
/// 未収集の文字はここに現れない。KanjiVG の字形で埋めるとフォントが
/// 二次的著作物になり、CC BY-SA での配布義務が生じるため（SPEC 6.3）。
Future<List<Glyph>> collectGlyphs(
  FontRecipe recipe,
  SampleStore store, {
  required bool includeTraced,
  void Function(int done, int total)? onProgress,
}) async {
  final resolved = resolveRecipe(recipe, store, includeTraced: includeTraced);
  // 並び順を決めておく。同じレシピからは同じバイト列が出る必要がある。
  final chars = resolved.keys.toList()..sort();
  final glyphs = <Glyph>[];

  for (final char in chars) {
    final sample = await store.read(resolved[char]!);
    glyphs.add(await buildGlyph(char: char, strokes: sample.strokes));
    onProgress?.call(glyphs.length, chars.length);
  }

  return glyphs;
}

/// レシピどおりのフォントを作る。
///
/// `(FontRecipe, Sample集合) -> バイナリ` の純関数（SPEC 4.3）。
/// 同じレシピからは常に同じフォントが出るため、生成物は保存しない。
Future<Uint8List> buildRecipeFont({
  required FontRecipe recipe,
  required SampleStore store,
  required FontFormat format,
  required bool includeTraced,
  void Function(int done, int total)? onProgress,
}) async {
  return buildFont(
    meta: recipe.fontMeta,
    glyphs: await collectGlyphs(
      recipe,
      store,
      includeTraced: includeTraced,
      onProgress: onProgress,
    ),
    format: format,
  );
}
