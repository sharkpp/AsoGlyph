import 'dart:typed_data';

/// sfnt はすべてビッグエンディアン。書き込み後の差し替えのため索引アクセスを許す。
class ByteWriter {
  final List<int> _bytes = [];

  int get length => _bytes.length;

  void uint8(int v) => _bytes.add(v & 0xff);

  void uint16(int v) {
    _bytes.add((v >> 8) & 0xff);
    _bytes.add(v & 0xff);
  }

  void int16(int v) => uint16(v < 0 ? v + 0x10000 : v);

  void uint32(int v) {
    _bytes.add((v >> 24) & 0xff);
    _bytes.add((v >> 16) & 0xff);
    _bytes.add((v >> 8) & 0xff);
    _bytes.add(v & 0xff);
  }

  void int32(int v) => uint32(v < 0 ? v + 0x100000000 : v);

  void int64(int v) {
    uint32((v >> 32) & 0xffffffff);
    uint32(v & 0xffffffff);
  }

  /// 16.16 固定小数点。
  void fixed(double v) => int32((v * 65536).round());

  /// 4 文字のテーブルタグ。
  void tag(String v) {
    assert(v.length == 4, 'tag must be 4 chars: $v');
    for (var i = 0; i < 4; i++) {
      _bytes.add(v.codeUnitAt(i) & 0xff);
    }
  }

  void ascii(String v) {
    for (final unit in v.codeUnits) {
      _bytes.add(unit & 0xff);
    }
  }

  /// name テーブルの Windows プラットフォーム用。
  void utf16be(String v) {
    for (final unit in v.codeUnits) {
      uint16(unit);
    }
  }

  void bytes(List<int> v) => _bytes.addAll(v);

  /// 4 バイト境界まで 0 で埋める。
  void padTo4() {
    while (_bytes.length % 4 != 0) {
      _bytes.add(0);
    }
  }

  /// 既に書き込んだ位置の uint32 を差し替える。チェックサム確定に使う。
  void patchUint32(int offset, int v) {
    _bytes[offset] = (v >> 24) & 0xff;
    _bytes[offset + 1] = (v >> 16) & 0xff;
    _bytes[offset + 2] = (v >> 8) & 0xff;
    _bytes[offset + 3] = v & 0xff;
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}

/// UTF-16BE で数えたコードユニット数。name テーブルの長さ計算に使う。
int utf16beLength(String v) => v.codeUnits.length * 2;
