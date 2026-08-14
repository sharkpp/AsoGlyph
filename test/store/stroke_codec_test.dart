import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/store/stroke_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('運筆の符号化', () {
    test('往復しても座標・時刻・筆圧が保たれる', () {
      final strokes = [
        Stroke(const [
          InkPoint(x: 0, y: 0, t: 0, pressure: 0),
          InkPoint(x: 500, y: 1000, t: 120, pressure: 1),
        ]),
        Stroke(const [InkPoint(x: 999, y: 1, t: 4000, pressure: 0.5)]),
      ];

      final decoded = decodeStrokes(encodeStrokes(strokes));

      expect(decoded, hasLength(2));
      expect(decoded[0].points.map((p) => p.x), [0, 500]);
      expect(decoded[0].points.map((p) => p.y), [0, 1000]);
      expect(decoded[0].points.map((p) => p.t), [0, 120]);
      expect(decoded[0].points.last.pressure, 1);
      expect(decoded[1].points.single.t, 4000);
      // 筆圧は uint8 に落ちるため 1/255 の丸めが乗る。
      expect(decoded[1].points.single.pressure, closeTo(0.5, 1 / 255));
    });

    test('1 点あたり 7 バイトに収まる', () {
      final stroke = Stroke([
        for (var i = 0; i < 40; i++)
          InkPoint(x: i * 10, y: i * 10, t: i * 16, pressure: 0),
      ]);

      // 画数 2 + 点数 2 + 40 点 × 7
      expect(encodeStrokes([stroke]), hasLength(2 + 2 + 40 * 7));
    });

    test('画が無くても壊れない', () {
      expect(decodeStrokes(encodeStrokes([])), isEmpty);
      expect(decodeStrokes(encodeStrokes([const Stroke([])])), hasLength(1));
    });

    test('uint16 に収まらない経過時間は頭打ちにする', () {
      final strokes = [
        Stroke(const [InkPoint(x: 0, y: 0, t: 100000, pressure: 0)]),
      ];
      expect(decodeStrokes(encodeStrokes(strokes)).single.points.single.t, 65535);
    });
  });
}
