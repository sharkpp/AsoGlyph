import 'dart:typed_data';

import '../ink/stroke.dart';

const _bytesPerPoint = 7;
const _endian = Endian.little;

/// 1 画の最大時間。uint16 ミリ秒に収める。
const _maxDuration = 0xffff;

/// 運筆をバイト列に詰める。
///
/// 1 点 7 バイト（x:int16, y:int16, t:uint16, pressure:uint8）で持つ（SPEC 4.1）。
/// ひらがな 1 字 ≒ 3 画 × 40 点 ≒ 0.9 KB。JSON にすると数倍に膨らみ、
/// web の IndexedDB では容量がそのまま効くため、記録は詰めた形にする。
///
/// ```
/// uint16 画数
///   uint16 点数
///     int16 x, int16 y, uint16 t, uint8 pressure   (× 点数)
/// ```
Uint8List encodeStrokes(List<Stroke> strokes) {
  final pointCount = strokes.fold(0, (n, s) => n + s.points.length);
  final bytes = ByteData(2 + strokes.length * 2 + pointCount * _bytesPerPoint);

  var offset = 0;
  bytes.setUint16(offset, strokes.length, _endian);
  offset += 2;

  for (final stroke in strokes) {
    bytes.setUint16(offset, stroke.points.length, _endian);
    offset += 2;

    for (final point in stroke.points) {
      bytes.setInt16(offset, point.x.round(), _endian);
      bytes.setInt16(offset + 2, point.y.round(), _endian);
      bytes.setUint16(offset + 4, point.t.clamp(0, _maxDuration), _endian);
      bytes.setUint8(offset + 6, (point.pressure * 255).round().clamp(0, 255));
      offset += _bytesPerPoint;
    }
  }

  return bytes.buffer.asUint8List();
}

List<Stroke> decodeStrokes(Uint8List data) {
  final bytes = ByteData.sublistView(data);

  var offset = 0;
  final strokeCount = bytes.getUint16(offset, _endian);
  offset += 2;

  final strokes = <Stroke>[];
  for (var s = 0; s < strokeCount; s++) {
    final pointCount = bytes.getUint16(offset, _endian);
    offset += 2;

    final points = <InkPoint>[];
    for (var p = 0; p < pointCount; p++) {
      points.add(
        InkPoint(
          x: bytes.getInt16(offset, _endian).toDouble(),
          y: bytes.getInt16(offset + 2, _endian).toDouble(),
          t: bytes.getUint16(offset + 4, _endian),
          pressure: bytes.getUint8(offset + 6) / 255,
        ),
      );
      offset += _bytesPerPoint;
    }
    strokes.add(Stroke(points));
  }

  return strokes;
}
