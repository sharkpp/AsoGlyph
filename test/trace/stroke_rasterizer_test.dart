import 'dart:io';
import 'dart:math' as math;

import 'package:asoglyph/font/font_builder.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/trace/contour_tracer.dart';
import 'package:asoglyph/trace/marching_squares.dart';
import 'package:asoglyph/trace/stroke_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 形状のテストでは速度による線幅の補正を切り、ラスタ化と輪郭追跡だけを見る。
  const style = StrokeStyle(baseWidth: 56, speedRange: 0);
  const tracer = ContourTracer();

  /// (200,500) から (800,500) への横棒。筆圧なし・等速。
  Stroke horizontalBar() => Stroke([
    for (var i = 0; i <= 30; i++)
      InkPoint(x: 200 + i * 20, y: 500, t: i * 16),
  ]);

  test('1 本の線は角の丸い帯になる', () async {
    final alpha = await rasterizeStrokes(
      strokes: [horizontalBar()],
      imageSize: 512,
      style: style,
    );
    final contours = tracer.trace(alpha: alpha, imageSize: 512);

    expect(contours.length, 1);

    // 長さ 600、幅 56 の帯に、半径 28 の半円が両端に付いた形。
    const expected = 600 * 56 + math.pi * 28 * 28;
    final area = _contourArea(contours.first).abs();
    expect(
      (area - expected).abs() / expected,
      lessThan(0.03),
      reason: '面積 $area 期待 $expected',
    );

    // Bounds.ofContours は制御点の凸包なので実際の輪郭より外に出る。
    // 端の位置を見たいので、曲線を折ってから測る。
    final bounds = _flatBounds(contours.first);
    expect(bounds.xMin, closeTo(200 - 28, 6));
    expect(bounds.xMax, closeTo(800 + 28, 6));
    expect(bounds.yMin, closeTo(500 - 28, 6));
    expect(bounds.yMax, closeTo(500 + 28, 6));
  });

  test('交差する 2 画は 1 本の輪郭にまとまる', () async {
    // ブーリアン演算を持たなくても、描画に任せれば重なりが解決される。
    final vertical = Stroke([
      for (var i = 0; i <= 30; i++)
        InkPoint(x: 500, y: 200 + i * 20, t: i * 16),
    ]);
    final alpha = await rasterizeStrokes(
      strokes: [horizontalBar(), vertical],
      imageSize: 512,
      style: style,
    );
    final contours = tracer.trace(alpha: alpha, imageSize: 512);

    expect(contours.length, 1, reason: '十字は穴のない 1 本の輪郭になる');
    expect(_contourArea(contours.first), lessThan(0), reason: '外周は時計回り');
  });

  test('輪を描くと外周と穴の 2 本になる', () async {
    final loop = Stroke([
      for (var i = 0; i <= 72; i++)
        InkPoint(
          x: 500 + 250 * math.cos(i / 72 * 2 * math.pi),
          y: 500 + 250 * math.sin(i / 72 * 2 * math.pi),
          t: i * 16,
        ),
    ]);
    final alpha = await rasterizeStrokes(
      strokes: [loop],
      imageSize: 512,
      style: style,
    );
    final contours = tracer.trace(alpha: alpha, imageSize: 512);

    expect(contours.length, 2);
    final areas = [for (final c in contours) _contourArea(c)];
    expect(areas.where((a) => a < 0).length, 1, reason: '外周が 1 本');
    expect(areas.where((a) => a > 0).length, 1, reason: '穴が 1 本');
  });

  test('L1 の縦断: 書いた線からフォントが出る', () async {
    // 書く → ラスタ化 → 輪郭追跡 → グリフ → TTF/OTF。
    final alpha = await rasterizeStrokes(
      strokes: [horizontalBar()],
      imageSize: 1024,
      style: style,
    );
    final contours = tracer.trace(alpha: alpha, imageSize: 1024);

    final glyph = Glyph(
      codePoint: 0x3042,
      contours: contours,
      advanceWidth: 1000,
    );
    final meta = FontMetadata(familyName: 'AsoGlyph Handwriting');

    final dir = Directory('build/font_samples');
    await dir.create(recursive: true);
    for (final format in FontFormat.values) {
      final bytes = buildFont(meta: meta, glyphs: [glyph], format: format);
      expect(bytes.length, greaterThan(500));
      await File('${dir.path}/handwriting.${format.name}').writeAsBytes(bytes);
    }
  });
}

double _contourArea(Contour contour) => signedArea(_flatten(contour)) / 2;

Bounds _flatBounds(Contour contour) {
  final points = _flatten(contour);
  return Bounds(
    points.map((p) => p.x).reduce(math.min),
    points.map((p) => p.y).reduce(math.min),
    points.map((p) => p.x).reduce(math.max),
    points.map((p) => p.y).reduce(math.max),
  );
}

/// 曲線を細かく折って点列にする。
List<Pt> _flatten(Contour contour) {
  final points = <Pt>[contour.start];
  var from = contour.start;
  for (final seg in contour.segs) {
    switch (seg) {
      case LineSeg(:final to):
        points.add(to);
      case CubicSeg(:final c1, :final c2, :final to):
        for (var i = 1; i <= 32; i++) {
          points.add(_cubicAt(from, c1, c2, to, i / 32));
        }
    }
    from = seg.to;
  }
  return points;
}

Pt _cubicAt(Pt p0, Pt p1, Pt p2, Pt p3, double t) {
  final u = 1 - t;
  return p0 * (u * u * u) +
      p1 * (3 * u * u * t) +
      p2 * (3 * u * t * t) +
      p3 * (t * t * t);
}
