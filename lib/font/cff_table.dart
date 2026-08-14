import 'dart:typed_data';

import 'byte_writer.dart';
import 'geometry.dart';
import 'glyph.dart';

/// CFF（Type 2 charstring）テーブル。OTF のアウトラインを担う。
///
/// 内部表現の 3 次ベジェをそのまま rrcurveto で書けるため、TTF と違い
/// 曲線の近似は発生しない。
Uint8List buildCffTable({
  required FontMetadata meta,
  required List<Glyph> glyphs,
  required Bounds bounds,
}) {
  // 標準文字列（SID 0..390）は使わず、必要な文字列をすべて自前で登録する。
  final strings = <String>[];
  int sid(String value) {
    var index = strings.indexOf(value);
    if (index < 0) {
      index = strings.length;
      strings.add(value);
    }
    return 391 + index;
  }

  final versionSid = sid(_ascii(meta.version, '1.000'));
  final fullNameSid = sid(_ascii(meta.fullName, 'AsoGlyph'));
  final familyNameSid = sid(_ascii(meta.familyName, 'AsoGlyph'));
  final weightSid = sid(_ascii(meta.styleName, 'Regular'));
  // charset はグリフ 1 番以降の名前を並べる。0 番は .notdef で固定。
  final glyphSids = [for (final glyph in glyphs.skip(1)) sid(glyph.name)];

  final charset = ByteWriter();
  charset.uint8(0); // format 0
  for (final s in glyphSids) {
    charset.uint16(s);
  }

  final charStrings = _buildIndex([
    for (final glyph in glyphs) _charString(glyph),
  ]);

  final privateDict = ByteWriter();
  _dictInt(privateDict, 0);
  privateDict.uint8(20); // defaultWidthX
  _dictInt(privateDict, 0);
  privateDict.uint8(21); // nominalWidthX
  final private = privateDict.toBytes();

  final nameIndex = _buildIndex([_asciiBytes(meta.postScriptName)]);
  final stringIndex = _buildIndex([for (final s in strings) _asciiBytes(s)]);
  final globalSubrIndex = _buildIndex(const []);

  Uint8List topDict(int charsetOffset, int charStringsOffset, int privateOffset) {
    final w = ByteWriter();
    _dictInt(w, versionSid);
    w.uint8(0); // version
    _dictInt(w, fullNameSid);
    w.uint8(2); // FullName
    _dictInt(w, familyNameSid);
    w.uint8(3); // FamilyName
    _dictInt(w, weightSid);
    w.uint8(4); // Weight
    _dictInt(w, bounds.xMin.floor());
    _dictInt(w, bounds.yMin.floor());
    _dictInt(w, bounds.xMax.ceil());
    _dictInt(w, bounds.yMax.ceil());
    w.uint8(5); // FontBBox
    // オフセットは 5 バイト固定長で書き、確定後に同じ長さで置き換える。
    _dictInt32(w, charsetOffset);
    w.uint8(15); // charset
    _dictInt32(w, charStringsOffset);
    w.uint8(17); // CharStrings
    _dictInt32(w, private.length);
    _dictInt32(w, privateOffset);
    w.uint8(18); // Private
    return w.toBytes();
  }

  const headerSize = 4;
  final topDictIndex = _buildIndex([topDict(0, 0, 0)]);
  final fixedSize = headerSize +
      nameIndex.length +
      topDictIndex.length +
      stringIndex.length +
      globalSubrIndex.length;

  final charsetOffset = fixedSize;
  final charStringsOffset = charsetOffset + charset.length;
  final privateOffset = charStringsOffset + charStrings.length;

  final resolved = _buildIndex([
    topDict(charsetOffset, charStringsOffset, privateOffset),
  ]);
  assert(
    resolved.length == topDictIndex.length,
    'Top DICT の長さはオフセット確定の前後で変わってはならない',
  );

  final w = ByteWriter();
  w.uint8(1); // major
  w.uint8(0); // minor
  w.uint8(headerSize);
  w.uint8(4); // offSize
  w.bytes(nameIndex);
  w.bytes(resolved);
  w.bytes(stringIndex);
  w.bytes(globalSubrIndex);
  w.bytes(charset.toBytes());
  w.bytes(charStrings);
  w.bytes(private);
  return w.toBytes();
}

/// Type 2 charstring を組み立てる。
///
/// 座標は丸めた絶対位置から差分を取る。丸めてから引くことで誤差が蓄積しない。
Uint8List _charString(Glyph glyph) {
  final w = ByteWriter();
  var widthWritten = false;
  var x = 0;
  var y = 0;

  for (final contour in glyph.contours) {
    if (contour.isEmpty) continue;

    final startX = contour.start.x.round();
    final startY = contour.start.y.round();
    if (!widthWritten) {
      // 最初のスタック解放演算子の直前に幅を 1 つ余分に積む規約。
      // nominalWidthX = 0 のため、そのまま advanceWidth を書く。
      _csInt(w, glyph.advanceWidth);
      widthWritten = true;
    }
    _csInt(w, startX - x);
    _csInt(w, startY - y);
    w.uint8(21); // rmoveto
    x = startX;
    y = startY;

    for (final (_, seg) in contour.walk()) {
      switch (seg) {
        case LineSeg(:final to):
          final tx = to.x.round();
          final ty = to.y.round();
          _csInt(w, tx - x);
          _csInt(w, ty - y);
          w.uint8(5); // rlineto
          x = tx;
          y = ty;
        case CubicSeg(:final c1, :final c2, :final to):
          final c1x = c1.x.round();
          final c1y = c1.y.round();
          final c2x = c2.x.round();
          final c2y = c2.y.round();
          final tx = to.x.round();
          final ty = to.y.round();
          _csInt(w, c1x - x);
          _csInt(w, c1y - y);
          _csInt(w, c2x - c1x);
          _csInt(w, c2y - c1y);
          _csInt(w, tx - c2x);
          _csInt(w, ty - c2y);
          w.uint8(8); // rrcurveto
          x = tx;
          y = ty;
      }
    }
  }

  if (!widthWritten) {
    _csInt(w, glyph.advanceWidth);
  }
  w.uint8(14); // endchar
  return w.toBytes();
}

/// Type 2 charstring の整数符号化。
void _csInt(ByteWriter w, int v) {
  if (v >= -107 && v <= 107) {
    w.uint8(v + 139);
  } else if (v >= 108 && v <= 1131) {
    final t = v - 108;
    w.uint8((t >> 8) + 247);
    w.uint8(t & 0xff);
  } else if (v >= -1131 && v <= -108) {
    final t = -v - 108;
    w.uint8((t >> 8) + 251);
    w.uint8(t & 0xff);
  } else {
    w.uint8(28);
    w.int16(v);
  }
}

/// DICT の整数符号化。charstring とは規則が異なる。
void _dictInt(ByteWriter w, int v) {
  if (v >= -107 && v <= 107) {
    w.uint8(v + 139);
  } else if (v >= 108 && v <= 1131) {
    final t = v - 108;
    w.uint8((t >> 8) + 247);
    w.uint8(t & 0xff);
  } else if (v >= -1131 && v <= -108) {
    final t = -v - 108;
    w.uint8((t >> 8) + 251);
    w.uint8(t & 0xff);
  } else if (v >= -32768 && v <= 32767) {
    w.uint8(28);
    w.int16(v);
  } else {
    w.uint8(29);
    w.int32(v);
  }
}

/// 常に 5 バイトで書く整数。前方参照のオフセットに使う。
void _dictInt32(ByteWriter w, int v) {
  w.uint8(29);
  w.int32(v);
}

/// CFF の INDEX 構造。
Uint8List _buildIndex(List<List<int>> items) {
  final w = ByteWriter();
  w.uint16(items.length);
  if (items.isEmpty) return w.toBytes();

  var dataLength = 0;
  for (final item in items) {
    dataLength += item.length;
  }
  final offSize = dataLength + 1 <= 0xff
      ? 1
      : dataLength + 1 <= 0xffff
      ? 2
      : dataLength + 1 <= 0xffffff
      ? 3
      : 4;
  w.uint8(offSize);

  void writeOffset(int value) {
    for (var i = offSize - 1; i >= 0; i--) {
      w.uint8((value >> (i * 8)) & 0xff);
    }
  }

  var offset = 1; // INDEX のオフセットは 1 起点
  writeOffset(offset);
  for (final item in items) {
    offset += item.length;
    writeOffset(offset);
  }
  for (final item in items) {
    w.bytes(item);
  }
  return w.toBytes();
}

/// CFF の文字列は ASCII を前提とする。子供の名前など非 ASCII は name テーブルが持つ。
String _ascii(String value, String fallback) {
  final buffer = StringBuffer();
  for (final unit in value.codeUnits) {
    if (unit >= 0x20 && unit <= 0x7e) buffer.writeCharCode(unit);
  }
  final result = buffer.toString().trim();
  return result.isEmpty ? fallback : result;
}

List<int> _asciiBytes(String value) => value.codeUnits;
