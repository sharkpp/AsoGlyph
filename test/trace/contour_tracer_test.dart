import 'dart:math' as math;
import 'dart:typed_data';

import 'package:asoglyph/font/geometry.dart';
import 'package:asoglyph/trace/contour_tracer.dart';
import 'package:asoglyph/trace/marching_squares.dart';
import 'package:asoglyph/trace/simplify.dart';
import 'package:flutter_test/flutter_test.dart';

const _imageSize = 512;
const _emSize = 1000.0;
const _scale = _emSize / _imageSize;

void main() {
  const tracer = ContourTracer();

  group('輪郭追跡', () {
    test('円は 1 本の輪郭になり、面積と向きが規約どおり', () {
      const radius = 200.0;
      final contours = tracer.trace(
        alpha: _disk(_imageSize, 256, 256, radius),
        imageSize: _imageSize,
      );

      expect(contours.length, 1);

      final expected = math.pi * math.pow(radius * _scale, 2);
      final area = _contourArea(contours.first);
      expect(
        (area.abs() - expected).abs() / expected,
        lessThan(0.01),
        reason: '面積 ${area.abs()} 期待 $expected',
      );
      expect(area, lessThan(0), reason: '外周は時計回り（em 空間で負）でなければならない');
    });

    test('円は少ないセグメント数で表現される', () {
      final contours = tracer.trace(
        alpha: _disk(_imageSize, 256, 256, 200),
        imageSize: _imageSize,
      );
      // 曲線当てはめが効いていれば、円周 1 本あたり十数本で足りる。
      expect(contours.first.segs.length, lessThan(24));
      expect(contours.first.segs.whereType<CubicSeg>(), isNotEmpty);
    });

    test('穴あきは外周と内周で巻き方向が逆になる', () {
      const outer = 200.0;
      const inner = 100.0;
      final contours = tracer.trace(
        alpha: _ring(_imageSize, 256, 256, outer, inner),
        imageSize: _imageSize,
      );

      expect(contours.length, 2);
      final areas = [for (final c in contours) _contourArea(c)]..sort(
        (a, b) => a.abs().compareTo(b.abs()),
      );
      expect(areas[0], greaterThan(0), reason: '内周は反時計回り');
      expect(areas[1], lessThan(0), reason: '外周は時計回り');

      final net = areas[0] + areas[1];
      final expected = -math.pi *
          (math.pow(outer * _scale, 2) - math.pow(inner * _scale, 2));
      expect(
        (net - expected).abs() / expected.abs(),
        lessThan(0.02),
        reason: '正味の面積 $net 期待 $expected',
      );
    });

    test('離れた 2 つの図形はどちらも外周として扱われる', () {
      final alpha = _disk(_imageSize, 130, 256, 90);
      final second = _disk(_imageSize, 380, 256, 90);
      for (var i = 0; i < alpha.length; i++) {
        if (second[i] > alpha[i]) alpha[i] = second[i];
      }

      final contours = tracer.trace(alpha: alpha, imageSize: _imageSize);
      expect(contours.length, 2);
      for (final contour in contours) {
        expect(_contourArea(contour), lessThan(0), reason: 'どちらも外周');
      }
    });

    test('正方形は 4 つの角で分割され、直線として表現される', () {
      final contours = tracer.trace(
        alpha: _square(_imageSize, 128, 384),
        imageSize: _imageSize,
      );

      expect(contours.length, 1);
      final contour = contours.first;
      expect(contour.segs.length, 4, reason: '4 辺ちょうどに収まるはず');
      expect(contour.segs.whereType<LineSeg>().length, 4, reason: 'すべて直線');

      final expected = math.pow((384 - 128) * _scale, 2).toDouble();
      expect((_contourArea(contour).abs() - expected).abs() / expected,
          lessThan(0.01));
    });

    test('ノイズのような微小な図形は捨てられる', () {
      final contours = tracer.trace(
        alpha: _disk(_imageSize, 256, 256, 1.2),
        imageSize: _imageSize,
      );
      expect(contours, isEmpty);
    });
  });

  group('間引き', () {
    test('直線上の点は落ちる', () {
      final points = [for (var i = 0; i <= 10; i++) Pt(i * 10, 0)];
      expect(simplifyPolyline(points, 0.5), hasLength(2));
    });

    test('許容誤差を超える突起は残る', () {
      final points = [
        const Pt(0, 0),
        const Pt(10, 0),
        const Pt(20, 5),
        const Pt(30, 0),
        const Pt(40, 0),
      ];
      expect(simplifyPolyline(points, 0.5), contains(const Pt(20, 5)));
      expect(simplifyPolyline(points, 10), hasLength(2));
    });

    test('角で分割される', () {
      final square = [
        const Pt(0, 0),
        const Pt(50, 0),
        const Pt(100, 0),
        const Pt(100, 50),
        const Pt(100, 100),
        const Pt(50, 100),
        const Pt(0, 100),
        const Pt(0, 50),
      ];
      final pieces = splitAtCorners(square, closed: true);
      expect(pieces.length, 4);
      for (final piece in pieces) {
        expect(piece.first, isNot(piece.last));
      }
    });
  });
}

/// アンチエイリアスされた円のアルファ場。境界の 1 ピクセルで線形に落とす。
Uint8List _disk(int size, double cx, double cy, double r) {
  final alpha = Uint8List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final d = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
      alpha[y * size + x] = _coverage(r - d);
    }
  }
  return alpha;
}

Uint8List _ring(int size, double cx, double cy, double outer, double inner) {
  final alpha = Uint8List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final d = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
      final coverage = math.min(_coverage(outer - d), _coverage(d - inner));
      alpha[y * size + x] = coverage;
    }
  }
  return alpha;
}

Uint8List _square(int size, double low, double high) {
  final alpha = Uint8List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final inside = math.min(
        math.min(_coverage(x - low), _coverage(high - x)),
        math.min(_coverage(y - low), _coverage(high - y)),
      );
      alpha[y * size + x] = inside;
    }
  }
  return alpha;
}

int _coverage(double signedDistance) =>
    ((signedDistance + 0.5).clamp(0.0, 1.0) * 255).round();

/// 曲線を細かく折り、シューレース公式で符号付き面積を求める。
double _contourArea(Contour contour) {
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
  return signedArea(points) / 2;
}

Pt _cubicAt(Pt p0, Pt p1, Pt p2, Pt p3, double t) {
  final u = 1 - t;
  return p0 * (u * u * u) +
      p1 * (3 * u * u * t) +
      p2 * (3 * u * t * t) +
      p3 * (t * t * t);
}
