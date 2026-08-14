import 'dart:typed_data';

import 'byte_writer.dart';
import 'cubic_to_quadratic.dart';
import 'geometry.dart';
import 'glyph.dart';

/// glyf に載る 1 点。
class _GlyfPoint {
  const _GlyfPoint(this.x, this.y, this.onCurve);

  final int x;
  final int y;
  final bool onCurve;
}

/// glyf と loca は互いのオフセットで結びつくため、まとめて構築する。
class GlyfTables {
  const GlyfTables({
    required this.glyf,
    required this.loca,
    required this.maxPoints,
    required this.maxContours,
  });

  final Uint8List glyf;
  final Uint8List loca;
  final int maxPoints;
  final int maxContours;
}

// glyf のフラグ。
const int _onCurvePoint = 0x01;
const int _xShortVector = 0x02;
const int _yShortVector = 0x04;
const int _xIsSameOrPositive = 0x10;
const int _yIsSameOrPositive = 0x20;

/// グリフ列から glyf / loca を構築する。loca は常に long 形式を使う。
GlyfTables buildGlyfTables(List<Glyph> glyphs, {double tolerance = 0.5}) {
  final glyf = ByteWriter();
  final offsets = <int>[];
  var maxPoints = 0;
  var maxContours = 0;

  for (final glyph in glyphs) {
    offsets.add(glyf.length);
    if (glyph.isBlank) continue;

    final contours = [
      for (final contour in glyph.contours)
        if (!contour.isEmpty) _flatten(contour, tolerance),
    ]..removeWhere((points) => points.length < 2);
    if (contours.isEmpty) continue;

    final points = [for (final contour in contours) ...contour];
    if (points.length > maxPoints) maxPoints = points.length;
    if (contours.length > maxContours) maxContours = contours.length;

    _writeSimpleGlyph(glyf, contours, points);
    glyf.padTo4();
  }
  offsets.add(glyf.length);

  final loca = ByteWriter();
  for (final offset in offsets) {
    loca.uint32(offset);
  }

  return GlyfTables(
    glyf: glyf.toBytes(),
    loca: loca.toBytes(),
    maxPoints: maxPoints,
    maxContours: maxContours,
  );
}

/// 3 次ベジェの輪郭を、glyf が扱える整数座標の点列へ落とす。
List<_GlyfPoint> _flatten(Contour contour, double tolerance) {
  final points = <_GlyfPoint>[
    _GlyfPoint(contour.start.x.round(), contour.start.y.round(), true),
  ];

  for (final (from, seg) in contour.walk()) {
    switch (seg) {
      case LineSeg(:final to):
        points.add(_GlyfPoint(to.x.round(), to.y.round(), true));
      case CubicSeg(:final c1, :final c2, :final to):
        final quads = cubicToQuadratics(from, c1, c2, to, tolerance: tolerance);
        for (final quad in quads) {
          points.add(
            _GlyfPoint(quad.control.x.round(), quad.control.y.round(), false),
          );
          points.add(_GlyfPoint(quad.to.x.round(), quad.to.y.round(), true));
        }
    }
  }

  // 輪郭は暗黙に閉じるため、始点と重なる終点は落とす。
  final last = points.last;
  final first = points.first;
  if (points.length > 1 &&
      last.onCurve &&
      last.x == first.x &&
      last.y == first.y) {
    points.removeLast();
  }
  return points;
}

void _writeSimpleGlyph(
  ByteWriter w,
  List<List<_GlyfPoint>> contours,
  List<_GlyfPoint> points,
) {
  var xMin = points.first.x;
  var yMin = points.first.y;
  var xMax = xMin;
  var yMax = yMin;
  for (final point in points) {
    if (point.x < xMin) xMin = point.x;
    if (point.y < yMin) yMin = point.y;
    if (point.x > xMax) xMax = point.x;
    if (point.y > yMax) yMax = point.y;
  }

  w.int16(contours.length);
  w.int16(xMin);
  w.int16(yMin);
  w.int16(xMax);
  w.int16(yMax);

  var end = -1;
  for (final contour in contours) {
    end += contour.length;
    w.uint16(end);
  }
  w.uint16(0); // instructionLength

  // フラグと座標は、直前の点からの差分で符号化する。
  final flags = <int>[];
  final xs = ByteWriter();
  final ys = ByteWriter();
  var prevX = 0;
  var prevY = 0;

  for (final point in points) {
    var flag = point.onCurve ? _onCurvePoint : 0;

    final dx = point.x - prevX;
    if (dx == 0) {
      flag |= _xIsSameOrPositive;
    } else if (dx.abs() <= 255) {
      flag |= _xShortVector;
      if (dx > 0) flag |= _xIsSameOrPositive;
      xs.uint8(dx.abs());
    } else {
      xs.int16(dx);
    }

    final dy = point.y - prevY;
    if (dy == 0) {
      flag |= _yIsSameOrPositive;
    } else if (dy.abs() <= 255) {
      flag |= _yShortVector;
      if (dy > 0) flag |= _yIsSameOrPositive;
      ys.uint8(dy.abs());
    } else {
      ys.int16(dy);
    }

    flags.add(flag);
    prevX = point.x;
    prevY = point.y;
  }

  for (final flag in flags) {
    w.uint8(flag);
  }
  w.bytes(xs.toBytes());
  w.bytes(ys.toBytes());
}
