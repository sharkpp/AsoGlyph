import 'dart:math' as math;

import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/ink/stroke_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = StrokeStyle(baseWidth: 56);

  group('線幅', () {
    test('筆圧が強いほど太い', () {
      Stroke withPressure(double pressure) => Stroke([
        InkPoint(x: 0, y: 0, t: 0, pressure: pressure),
        InkPoint(x: 100, y: 0, t: 16, pressure: pressure),
      ]);

      expect(
        strokeWidths(withPressure(0.1), style).first,
        lessThan(strokeWidths(withPressure(0.9), style).first),
      );
    });

    test('筆圧が無い入力では速いほど細い', () {
      final slow = Stroke([
        const InkPoint(x: 0, y: 0, t: 0),
        const InkPoint(x: 10, y: 0, t: 100),
      ]);
      final fast = Stroke([
        const InkPoint(x: 0, y: 0, t: 0),
        const InkPoint(x: 400, y: 0, t: 16),
      ]);
      expect(
        strokeWidths(fast, style).last,
        lessThan(strokeWidths(slow, style).last),
      );
    });

    test('書き始めが最大幅にならない', () {
      // 自分自身との差分を速度 0 とみなすと、速く書き始めても先頭だけ太くなり、
      // 書き出しに丸が 1 個できる。前後の区間から速度を求めることで防ぐ。
      final fast = Stroke([
        for (var i = 0; i <= 10; i++) InkPoint(x: i * 60.0, y: 0, t: i * 16),
      ]);
      final widths = strokeWidths(fast, style);

      expect(widths.first, lessThan(style.baseWidth * 0.95));
      expect(
        (widths.first - widths[1]).abs(),
        lessThan(style.baseWidth * 0.05),
        reason: '先頭だけ突出してはならない',
      );
    });
  });

  group('整形', () {
    /// マウス操作を模した、間隔が空いて速度もばらつく運筆。
    Stroke jerkyStroke() => Stroke([
      const InkPoint(x: 100, y: 500, t: 0),
      const InkPoint(x: 180, y: 505, t: 16),
      const InkPoint(x: 400, y: 510, t: 32),
      const InkPoint(x: 450, y: 505, t: 48),
      const InkPoint(x: 700, y: 495, t: 64),
      const InkPoint(x: 760, y: 490, t: 80),
      const InkPoint(x: 900, y: 500, t: 96),
    ]);

    test('隣り合う点の線幅が急に変わらない', () {
      final points = renderPoints(jerkyStroke(), style);

      var worst = 0.0;
      for (var i = 1; i < points.length; i++) {
        final change =
            (points[i].width - points[i - 1].width).abs() / points[i - 1].width;
        if (change > worst) worst = change;
      }
      expect(
        worst,
        lessThan(0.02),
        reason: '幅の段差が残ると、太い区間の丸いキャップがはみ出して数珠状に見える',
      );
    });

    test('点が等間隔に打ち直される', () {
      final points = renderPoints(jerkyStroke(), style);
      expect(points.length, greaterThan(100), reason: '入力 7 点から十分に細かくなる');

      // 刻み数は弦長から決めるが、曲線は弦より長いぶん間隔が広がる。
      // 一様パラメータ化では 1.57 倍まで開いていた。重心パラメータ化に
      // することでオーバーシュートが減り、1.2 倍に収まる。
      for (var i = 1; i < points.length; i++) {
        final gap = math.sqrt(
          math.pow(points[i].x - points[i - 1].x, 2) +
              math.pow(points[i].y - points[i - 1].y, 2),
        );
        expect(gap, lessThanOrEqualTo(style.resampleSpacing * 1.2));
      }
    });

    test('入力した点を必ず通る', () {
      // 平滑化で字が動いてしまっては、書いたとおりの字にならない。
      final stroke = jerkyStroke();
      final points = renderPoints(stroke, style);

      for (final input in stroke.points) {
        final nearest = points
            .map((p) => math.sqrt(math.pow(p.x - input.x, 2) + math.pow(p.y - input.y, 2)))
            .reduce(math.min);
        expect(nearest, lessThan(0.001), reason: '入力点 (${input.x}, ${input.y})');
      }
    });

    test('1 点だけの運筆は点として残る', () {
      final dot = Stroke([const InkPoint(x: 500, y: 500, t: 0)]);
      final points = renderPoints(dot, style);
      expect(points, hasLength(1));
      expect(points.first.width, greaterThan(0));
    });
  });
}
