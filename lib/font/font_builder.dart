import 'dart:typed_data';

import 'cff_table.dart';
import 'common_tables.dart';
import 'geometry.dart';
import 'glyf_table.dart';
import 'glyph.dart';
import 'sfnt.dart';

export 'geometry.dart';
export 'glyph.dart';

/// フォントの出力形式。
enum FontFormat { ttf, otf }

/// グリフ集合からフォントのバイト列を作る。
///
/// この関数は純粋である。同じ引数からは常に同じバイト列が出る。
/// FontRecipe から再現可能なフォントを作るという仕様は、この性質に依存する。
Uint8List buildFont({
  required FontMetadata meta,
  required List<Glyph> glyphs,
  required FontFormat format,
}) {
  final ordered = _orderGlyphs(glyphs, meta);
  final bounds = _fontBounds(ordered);

  return switch (format) {
    FontFormat.ttf => _buildTrueType(meta, ordered, bounds),
    FontFormat.otf => _buildOpenType(meta, ordered, bounds),
  };
}

Uint8List _buildTrueType(
  FontMetadata meta,
  List<Glyph> glyphs,
  Bounds bounds,
) {
  final outlines = buildGlyfTables(glyphs);
  return assembleSfnt(
    isCff: false,
    tables: [
      SfntTable('OS/2', buildOs2(meta: meta, glyphs: glyphs)),
      SfntTable('cmap', buildCmap(glyphs)),
      SfntTable('glyf', outlines.glyf),
      SfntTable('head', buildHead(meta: meta, bounds: bounds, longLoca: true)),
      SfntTable('hhea', buildHhea(meta: meta, glyphs: glyphs)),
      SfntTable('hmtx', buildHmtx(glyphs)),
      SfntTable('loca', outlines.loca),
      SfntTable(
        'maxp',
        buildMaxpTrueType(
          numGlyphs: glyphs.length,
          maxPoints: outlines.maxPoints,
          maxContours: outlines.maxContours,
        ),
      ),
      SfntTable('name', buildName(meta)),
      SfntTable('post', buildPost(meta)),
    ],
  );
}

Uint8List _buildOpenType(
  FontMetadata meta,
  List<Glyph> inputGlyphs,
  Bounds bounds,
) {
  // 内部表現は TrueType の巻き方向（外周が時計回り）。CFF は逆を慣習とするため反転する。
  final glyphs = [
    for (final glyph in inputGlyphs)
      Glyph(
        codePoint: glyph.codePoint,
        advanceWidth: glyph.advanceWidth,
        contours: [for (final contour in glyph.contours) contour.reversed()],
      ),
  ];

  return assembleSfnt(
    isCff: true,
    tables: [
      SfntTable('CFF ', buildCffTable(meta: meta, glyphs: glyphs, bounds: bounds)),
      SfntTable('OS/2', buildOs2(meta: meta, glyphs: glyphs)),
      SfntTable('cmap', buildCmap(glyphs)),
      SfntTable('head', buildHead(meta: meta, bounds: bounds, longLoca: false)),
      SfntTable('hhea', buildHhea(meta: meta, glyphs: glyphs)),
      SfntTable('hmtx', buildHmtx(glyphs)),
      SfntTable('maxp', buildMaxpCff(glyphs.length)),
      SfntTable('name', buildName(meta)),
      SfntTable('post', buildPost(meta)),
    ],
  );
}

/// グリフ 0 を .notdef に固定し、以降をコードポイント昇順に並べる。
///
/// スペースは常に含める。未収集の文字を補うことはしない（SPEC 6.3）。
List<Glyph> _orderGlyphs(List<Glyph> glyphs, FontMetadata meta) {
  final halfWidth = meta.unitsPerEm ~/ 2;
  final byCodePoint = <int, Glyph>{};
  for (final glyph in glyphs) {
    if (glyph.codePoint < 0) continue;
    byCodePoint[glyph.codePoint] = glyph;
  }
  byCodePoint.putIfAbsent(
    0x20,
    () => Glyph.blank(codePoint: 0x20, advanceWidth: halfWidth),
  );

  final codePoints = byCodePoint.keys.toList()..sort();
  return [
    Glyph.blank(codePoint: -1, advanceWidth: halfWidth),
    for (final cp in codePoints) byCodePoint[cp]!,
  ];
}

Bounds _fontBounds(List<Glyph> glyphs) {
  var bounds = Bounds.empty;
  for (final glyph in glyphs) {
    if (glyph.isBlank) continue;
    bounds = bounds.union(glyph.bounds);
  }
  return bounds;
}
