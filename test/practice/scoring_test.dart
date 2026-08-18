import 'dart:math';

import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/kanjivg/stroke_order.dart';
import 'package:asoglyph/model/score.dart';
import 'package:asoglyph/practice/scoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// お手本をそのままなぞった運筆。
List<Stroke> traced(
  StrokeOrder model, {
  Offset shift = Offset.zero,
  double scale = 1,
  double noise = 0,
  int? strokes,
  bool mirror = false,
}) {
  final random = Random(42);
  const center = Offset(500, 500);

  return [
    for (final stroke in modelPoints(model).take(strokes ?? 1 << 30))
      Stroke([
        for (final (i, point) in stroke.indexed)
          () {
            var at = center + (point - center) * scale + shift;
            if (mirror) at = Offset(1000 - at.dx, at.dy);
            return InkPoint(
              x: at.dx + (random.nextDouble() - 0.5) * 2 * noise,
              y: at.dy + (random.nextDouble() - 0.5) * 2 * noise,
              t: i * 20,
            );
          }(),
      ]),
  ];
}

void main() {
  late StrokeOrderLibrary library;
  late StrokeOrder a;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    library = await StrokeOrderLibrary.load();
    a = library['あ']!;
  });

  group('採点', () {
    test('お手本のとおりに書けば満点に近い', () {
      final score = scoreStrokes(strokes: traced(a), model: a);

      expect(score.shape, closeTo(1, 0.01));
      expect(score.strokes, 1);
      expect(score.fit, closeTo(1, 0.01));
      expect(score.overall, closeTo(1, 0.01));
    });

    test('少しゆがんでいても点は残る', () {
      // 4 歳の字は線 1 本ぶん平気でずれる。そこで 0 になると重み付けに使えない。
      final score = scoreStrokes(strokes: traced(a, noise: 60), model: a);

      expect(score.shape, greaterThan(0.6));
      expect(score.shape, lessThan(1));
    });

    test('画数が足りないと画数の点が下がる', () {
      final score = scoreStrokes(strokes: traced(a, strokes: 2), model: a);

      expect(a.strokeCount, 3);
      expect(score.strokes, closeTo(2 / 3, 0.01));
      // 書けた画の形は変わらないので、形の点は落とさない。
      expect(score.shape, closeTo(1, 0.01));
    });

    test('小さく書くと収まりの点が下がる', () {
      final score = scoreStrokes(strokes: traced(a, scale: 0.4), model: a);

      expect(score.fit, lessThan(0.7));
    });

    test('端に寄せて書いても収まりの点が下がる', () {
      final score = scoreStrokes(
        strokes: traced(a, shift: const Offset(250, 0)),
        model: a,
      );

      expect(score.fit, lessThan(0.6));
    });

    test('書き順データが無い字では、形と画数を測らない', () {
      final score = scoreStrokes(strokes: traced(a), model: null);

      expect(score.shape, isNull);
      expect(score.strokes, isNull);
      // 測れないものを 0 点にしない。0 点にすると、書き順の無い字ばかりが
      // 苦手な字として出続ける。
      expect(score.overall, 0.5);
    });

    test('かかった時間と書き直しの回数を持つ', () {
      final score = scoreStrokes(strokes: traced(a), model: a, retries: 2);

      expect(score.durationMs, greaterThan(0));
      expect(score.retries, 2);
    });

    test('記録に書き出して読み戻せる', () {
      final score = scoreStrokes(strokes: traced(a), model: a, retries: 1);
      final back = Score.fromRecord(score.toRecord());

      expect(back.shape, score.shape);
      expect(back.retries, 1);
      expect(back.overall, score.overall);
    });
  });

  group('鏡文字・書き損じ', () {
    test('鏡文字を見分ける', () {
      expect(
        detectRejected(strokes: traced(a, mirror: true), model: a),
        isTrue,
      );
    });

    test('ゆがんだだけの字は はねない', () {
      // 取りこぼした鏡文字が 1 字混じるほうが、その子の字が 1 字消えるより良い。
      for (final noise in [40.0, 80.0, 120.0]) {
        expect(
          detectRejected(strokes: traced(a, noise: noise), model: a),
          isFalse,
          reason: 'ゆがみ $noise で はねている',
        );
      }
    });

    test('小さく書いただけの字も はねない', () {
      expect(detectRejected(strokes: traced(a, scale: 0.5), model: a), isFalse);
    });

    test('画をやたら重ねたなぐりがきは はねる', () {
      final scribble = [
        for (var i = 0; i < 12; i++)
          Stroke([
            for (var j = 0; j < 16; j++)
              InkPoint(x: 100.0 + j * 50, y: 200.0 + i * 40, t: j * 5),
          ]),
      ];

      expect(detectRejected(strokes: scribble, model: a), isTrue);
    });

    test('書き順データが無い字は、はねようがない', () {
      expect(detectRejected(strokes: traced(a, mirror: true), model: null),
          isFalse);
    });
  });
}
