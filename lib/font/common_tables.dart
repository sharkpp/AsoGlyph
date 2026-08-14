import 'dart:typed_data';

import 'byte_writer.dart';
import 'geometry.dart';
import 'glyph.dart';

/// TTF と OTF で共通のテーブル群。
///
/// グリフ列は先頭が .notdef、以降はコードポイント昇順であることを前提とする。

/// 1904-01-01 00:00:00 UTC からの経過秒。head の longDateTime。
int _longDateTime(DateTime at) =>
    at.toUtc().difference(DateTime.utc(1904)).inSeconds;

Uint8List buildHead({
  required FontMetadata meta,
  required Bounds bounds,
  required bool longLoca,
}) {
  final w = ByteWriter();
  w.uint32(0x00010000); // version
  w.fixed(double.tryParse(meta.version) ?? 1.0); // fontRevision
  w.uint32(0); // checkSumAdjustment（sfnt 組み立て時に埋める）
  w.uint32(0x5f0f3cf5); // magicNumber
  w.uint16(0x0003); // flags: baseline at y=0, lsb at x=0
  w.uint16(meta.unitsPerEm);
  w.int64(_longDateTime(meta.created));
  w.int64(_longDateTime(meta.created));
  w.int16(bounds.xMin.floor());
  w.int16(bounds.yMin.floor());
  w.int16(bounds.xMax.ceil());
  w.int16(bounds.yMax.ceil());
  w.uint16(0); // macStyle
  w.uint16(8); // lowestRecPPEM
  w.int16(2); // fontDirectionHint
  w.int16(longLoca ? 1 : 0); // indexToLocFormat
  w.int16(0); // glyphDataFormat
  return w.toBytes();
}

Uint8List buildHhea({
  required FontMetadata meta,
  required List<Glyph> glyphs,
}) {
  var advanceWidthMax = 0;
  var minLsb = 32767;
  var minRsb = 32767;
  var xMaxExtent = -32768;

  for (final glyph in glyphs) {
    if (glyph.advanceWidth > advanceWidthMax) advanceWidthMax = glyph.advanceWidth;
    if (glyph.isBlank) continue;
    final b = glyph.bounds;
    final lsb = b.xMin.floor();
    final xMax = b.xMax.ceil();
    if (lsb < minLsb) minLsb = lsb;
    if (glyph.advanceWidth - xMax < minRsb) minRsb = glyph.advanceWidth - xMax;
    if (xMax > xMaxExtent) xMaxExtent = xMax;
  }
  if (xMaxExtent == -32768) {
    minLsb = 0;
    minRsb = 0;
    xMaxExtent = 0;
  }

  final w = ByteWriter();
  w.uint32(0x00010000); // version
  w.int16(meta.ascender);
  w.int16(meta.descender);
  w.int16(meta.lineGap);
  w.uint16(advanceWidthMax);
  w.int16(minLsb);
  w.int16(minRsb);
  w.int16(xMaxExtent);
  w.int16(1); // caretSlopeRise
  w.int16(0); // caretSlopeRun
  w.int16(0); // caretOffset
  for (var i = 0; i < 4; i++) {
    w.int16(0); // reserved
  }
  w.int16(0); // metricDataFormat
  w.uint16(glyphs.length); // numberOfHMetrics
  return w.toBytes();
}

/// TrueType アウトライン用の maxp（version 1.0）。
Uint8List buildMaxpTrueType({
  required int numGlyphs,
  required int maxPoints,
  required int maxContours,
}) {
  final w = ByteWriter();
  w.uint32(0x00010000);
  w.uint16(numGlyphs);
  w.uint16(maxPoints);
  w.uint16(maxContours);
  w.uint16(0); // maxCompositePoints
  w.uint16(0); // maxCompositeContours
  w.uint16(2); // maxZones
  w.uint16(0); // maxTwilightPoints
  w.uint16(0); // maxStorage
  w.uint16(0); // maxFunctionDefs
  w.uint16(0); // maxInstructionDefs
  w.uint16(0); // maxStackElements
  w.uint16(0); // maxSizeOfInstructions
  w.uint16(0); // maxComponentElements
  w.uint16(0); // maxComponentDepth
  return w.toBytes();
}

/// CFF アウトライン用の maxp（version 0.5）。
Uint8List buildMaxpCff(int numGlyphs) {
  final w = ByteWriter();
  w.uint32(0x00005000);
  w.uint16(numGlyphs);
  return w.toBytes();
}

Uint8List buildHmtx(List<Glyph> glyphs) {
  final w = ByteWriter();
  for (final glyph in glyphs) {
    w.uint16(glyph.advanceWidth);
    w.int16(glyph.isBlank ? 0 : glyph.bounds.xMin.floor());
  }
  return w.toBytes();
}

/// cmap format 4。対象文字は全て BMP に収まるため format 12 は用いない。
Uint8List buildCmap(List<Glyph> glyphs) {
  // (コードポイント, グリフ ID) を昇順で集める。
  final entries = <(int, int)>[];
  for (var id = 0; id < glyphs.length; id++) {
    final cp = glyphs[id].codePoint;
    if (cp >= 0 && cp <= 0xffff) entries.add((cp, id));
  }
  entries.sort((a, b) => a.$1.compareTo(b.$1));

  // コードポイントとグリフ ID がともに連続する範囲を 1 セグメントにまとめる。
  final starts = <int>[];
  final ends = <int>[];
  final deltas = <int>[];
  for (final (cp, id) in entries) {
    if (starts.isNotEmpty &&
        ends.last + 1 == cp &&
        (ends.last + deltas.last) & 0xffff == id - 1) {
      ends[ends.length - 1] = cp;
      continue;
    }
    starts.add(cp);
    ends.add(cp);
    deltas.add((id - cp) & 0xffff);
  }
  // 必須の終端セグメント。
  starts.add(0xffff);
  ends.add(0xffff);
  deltas.add(1);

  final segCount = starts.length;
  var entrySelector = 0;
  while ((1 << (entrySelector + 1)) <= segCount) {
    entrySelector++;
  }
  final searchRange = 2 * (1 << entrySelector);

  final sub = ByteWriter();
  sub.uint16(4); // format
  sub.uint16(16 + 8 * segCount); // length
  sub.uint16(0); // language
  sub.uint16(segCount * 2);
  sub.uint16(searchRange);
  sub.uint16(entrySelector);
  sub.uint16(segCount * 2 - searchRange);
  for (final end in ends) {
    sub.uint16(end);
  }
  sub.uint16(0); // reservedPad
  for (final start in starts) {
    sub.uint16(start);
  }
  for (final delta in deltas) {
    sub.uint16(delta);
  }
  for (var i = 0; i < segCount; i++) {
    sub.uint16(0); // idRangeOffset: idDelta のみで解決する
  }
  final subtable = sub.toBytes();

  // Unicode BMP を 2 つのプラットフォームから同じ subtable へ向ける。
  const encodings = [(0, 3), (3, 1)];
  final subtableOffset = 4 + encodings.length * 8;

  final w = ByteWriter();
  w.uint16(0); // version
  w.uint16(encodings.length);
  for (final (platform, encoding) in encodings) {
    w.uint16(platform);
    w.uint16(encoding);
    w.uint32(subtableOffset);
  }
  w.bytes(subtable);
  return w.toBytes();
}

/// name テーブル（format 0）。
///
/// Windows プラットフォーム（3,1,0x409）のみを出力する。家族名に子供の名前など
/// 非 ASCII が入りうるため、Mac Roman のレコードは持たない。
Uint8List buildName(FontMetadata meta) {
  final records = <(int, String)>[
    (0, 'Copyright (c) ${meta.manufacturer}'),
    (1, meta.familyName),
    (2, meta.styleName),
    (3, meta.uniqueId),
    (4, meta.fullName),
    (5, 'Version ${meta.version}'),
    (6, meta.postScriptName),
    (8, meta.manufacturer),
    (11, meta.vendorUrl),
  ];

  final storage = ByteWriter();
  final offsets = <int>[];
  final lengths = <int>[];
  for (final (_, value) in records) {
    offsets.add(storage.length);
    lengths.add(utf16beLength(value));
    storage.utf16be(value);
  }

  final w = ByteWriter();
  w.uint16(0); // format
  w.uint16(records.length);
  w.uint16(6 + records.length * 12); // stringOffset
  for (var i = 0; i < records.length; i++) {
    w.uint16(3); // platformID: Windows
    w.uint16(1); // encodingID: Unicode BMP
    w.uint16(0x409); // languageID: en-US
    w.uint16(records[i].$1);
    w.uint16(lengths[i]);
    w.uint16(offsets[i]);
  }
  w.bytes(storage.toBytes());
  return w.toBytes();
}

Uint8List buildOs2({
  required FontMetadata meta,
  required List<Glyph> glyphs,
}) {
  final codePoints = [
    for (final glyph in glyphs)
      if (glyph.codePoint >= 0) glyph.codePoint,
  ];
  final firstChar = codePoints.isEmpty
      ? 0xffff
      : codePoints.reduce((a, b) => a < b ? a : b);
  final lastChar = codePoints.isEmpty
      ? 0xffff
      : codePoints.reduce((a, b) => a > b ? a : b);

  var totalWidth = 0;
  for (final glyph in glyphs) {
    totalWidth += glyph.advanceWidth;
  }
  final avgWidth = glyphs.isEmpty ? 0 : (totalWidth / glyphs.length).round();

  final (range1, range2, range3, range4) = _unicodeRanges(codePoints);
  final em = meta.unitsPerEm;

  final w = ByteWriter();
  w.uint16(4); // version
  w.int16(avgWidth);
  w.uint16(400); // usWeightClass: Regular
  w.uint16(5); // usWidthClass: Medium
  w.uint16(0); // fsType: 埋め込み制限なし
  w.int16((em * 0.65).round()); // ySubscriptXSize
  w.int16((em * 0.60).round()); // ySubscriptYSize
  w.int16(0); // ySubscriptXOffset
  w.int16((em * 0.075).round()); // ySubscriptYOffset
  w.int16((em * 0.65).round()); // ySuperscriptXSize
  w.int16((em * 0.60).round()); // ySuperscriptYSize
  w.int16(0); // ySuperscriptXOffset
  w.int16((em * 0.35).round()); // ySuperscriptYOffset
  w.int16((em * 0.05).round()); // yStrikeoutSize
  w.int16((em * 0.26).round()); // yStrikeoutPosition
  w.int16(0); // sFamilyClass
  for (var i = 0; i < 10; i++) {
    w.uint8(0); // panose: 未分類
  }
  w.uint32(range1);
  w.uint32(range2);
  w.uint32(range3);
  w.uint32(range4);
  w.tag(meta.vendorId.padRight(4).substring(0, 4));
  w.uint16(meta.styleName == 'Regular' ? 0x0040 : 0x0000); // fsSelection
  w.uint16(firstChar);
  w.uint16(lastChar);
  w.int16(meta.ascender); // sTypoAscender
  w.int16(meta.descender); // sTypoDescender
  w.int16(meta.lineGap); // sTypoLineGap
  w.uint16(meta.ascender); // usWinAscent
  w.uint16(-meta.descender); // usWinDescent
  w.uint32(_codePageRanges(codePoints));
  w.uint32(0); // ulCodePageRange2
  w.int16(0); // sxHeight: 手書きのため定義しない
  w.int16(0); // sCapHeight: 同上
  w.uint16(0); // usDefaultChar
  w.uint16(0x20); // usBreakChar
  w.uint16(1); // usMaxContext: GSUB/GPOS を持たない
  return w.toBytes();
}

/// OS/2 の ulUnicodeRange。本アプリが扱う範囲のみを判定する。
(int, int, int, int) _unicodeRanges(List<int> codePoints) {
  var bits = 0;
  var ranges = [0, 0, 0, 0];

  void setBit(int bit) {
    ranges[bit ~/ 32] |= 1 << (bit % 32);
    bits++;
  }

  var hasLatin = false;
  var hasPunctuation = false;
  var hasHiragana = false;
  var hasKatakana = false;
  var hasKanji = false;
  for (final cp in codePoints) {
    if (cp <= 0x7f) hasLatin = true;
    if (cp >= 0x3000 && cp <= 0x303f) hasPunctuation = true;
    if (cp >= 0x3040 && cp <= 0x309f) hasHiragana = true;
    if (cp >= 0x30a0 && cp <= 0x30ff) hasKatakana = true;
    if (cp >= 0x4e00 && cp <= 0x9fff) hasKanji = true;
  }
  if (hasLatin) setBit(0); // Basic Latin
  if (hasPunctuation) setBit(48); // CJK Symbols and Punctuation
  if (hasHiragana) setBit(49); // Hiragana
  if (hasKatakana) setBit(50); // Katakana
  if (hasKanji) setBit(59); // CJK Unified Ideographs
  if (bits == 0) ranges[0] = 1;

  return (ranges[0], ranges[1], ranges[2], ranges[3]);
}

/// OS/2 の ulCodePageRange1。
int _codePageRanges(List<int> codePoints) {
  var value = 1 << 0; // Latin 1 (1252)
  for (final cp in codePoints) {
    if (cp >= 0x3000 && cp <= 0x9fff) {
      value |= 1 << 17; // JIS/Japan (932)
      break;
    }
  }
  return value;
}

/// post テーブル（version 3.0）。グリフ名は持たない。
Uint8List buildPost(FontMetadata meta) {
  final w = ByteWriter();
  w.uint32(0x00030000); // version
  w.fixed(0); // italicAngle
  w.int16(-(meta.unitsPerEm * 0.075).round()); // underlinePosition
  w.int16((meta.unitsPerEm * 0.05).round()); // underlineThickness
  w.uint32(0); // isFixedPitch
  w.uint32(0); // minMemType42
  w.uint32(0); // maxMemType42
  w.uint32(0); // minMemType1
  w.uint32(0); // maxMemType1
  return w.toBytes();
}
