import 'dart:typed_data';

import 'byte_writer.dart';

/// sfnt コンテナに収める 1 テーブル。
class SfntTable {
  const SfntTable(this.tag, this.data);

  final String tag;
  final Uint8List data;
}

const int _sfntVersionTrueType = 0x00010000;
const String _sfntVersionCff = 'OTTO';

/// head テーブル内の checkSumAdjustment の位置。
const int _headCheckSumAdjustmentOffset = 8;

/// テーブル群を sfnt コンテナへ組み立てる。
///
/// TTF と OTF の違いは、先頭のバージョンタグと収めるテーブルだけである。
Uint8List assembleSfnt({
  required bool isCff,
  required List<SfntTable> tables,
}) {
  final sorted = [...tables]..sort((a, b) => a.tag.compareTo(b.tag));
  final numTables = sorted.length;

  var entrySelector = 0;
  while ((1 << (entrySelector + 1)) <= numTables) {
    entrySelector++;
  }
  final searchRange = (1 << entrySelector) * 16;
  final rangeShift = numTables * 16 - searchRange;

  final writer = ByteWriter();
  if (isCff) {
    writer.tag(_sfntVersionCff);
  } else {
    writer.uint32(_sfntVersionTrueType);
  }
  writer.uint16(numTables);
  writer.uint16(searchRange);
  writer.uint16(entrySelector);
  writer.uint16(rangeShift);

  // ディレクトリ本体は後段でオフセットが確定するため、
  // 位置を控えたうえで仮の値を書いておく。
  final entryOffsets = <int>[];
  for (final table in sorted) {
    writer.tag(table.tag);
    entryOffsets.add(writer.length);
    writer.uint32(0); // checksum
    writer.uint32(0); // offset
    writer.uint32(0); // length
  }

  var headTableOffset = -1;
  for (var i = 0; i < sorted.length; i++) {
    writer.padTo4();
    final offset = writer.length;
    if (sorted[i].tag == 'head') headTableOffset = offset;
    writer.bytes(sorted[i].data);

    writer.patchUint32(entryOffsets[i], _checksum(sorted[i].data));
    writer.patchUint32(entryOffsets[i] + 4, offset);
    writer.patchUint32(entryOffsets[i] + 8, sorted[i].data.length);
  }
  writer.padTo4();

  final font = writer.toBytes();

  // checkSumAdjustment はフォント全体のチェックサムから決まるため最後に埋める。
  if (headTableOffset >= 0) {
    final adjustment = (0xb1b0afba - _checksum(font)) & 0xffffffff;
    final at = headTableOffset + _headCheckSumAdjustmentOffset;
    font[at] = (adjustment >> 24) & 0xff;
    font[at + 1] = (adjustment >> 16) & 0xff;
    font[at + 2] = (adjustment >> 8) & 0xff;
    font[at + 3] = adjustment & 0xff;
  }

  return font;
}

/// 4 バイト境界まで 0 で埋めたうえで uint32 として総和を取る。
int _checksum(Uint8List data) {
  var sum = 0;
  for (var i = 0; i < data.length; i += 4) {
    final b0 = data[i];
    final b1 = i + 1 < data.length ? data[i + 1] : 0;
    final b2 = i + 2 < data.length ? data[i + 2] : 0;
    final b3 = i + 3 < data.length ? data[i + 3] : 0;
    sum = (sum + ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)) & 0xffffffff;
  }
  return sum;
}
