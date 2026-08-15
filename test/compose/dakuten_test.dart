import 'package:asoglyph/compose/dakuten.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/kanjivg/dakuten_placement.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:flutter_test/flutter_test.dart';

/// 左下から右上へ伸びる正方形の運筆。
List<Stroke> _square({
  double left = 0,
  double bottom = 0,
  double size = 1000,
}) => [
  Stroke([
    InkPoint(x: left, y: bottom, t: 0),
    InkPoint(x: left + size, y: bottom, t: 10),
    InkPoint(x: left + size, y: bottom + size, t: 20),
  ]),
];

void main() {
  group('分解', () {
    test('濁音は清音と濁点に分かれる', () {
      expect(decomposeDakuten('が'), (base: 'か', mark: '゛'));
      expect(decomposeDakuten('じ'), (base: 'し', mark: '゛'));
      expect(decomposeDakuten('ど'), (base: 'と', mark: '゛'));
      expect(decomposeDakuten('づ'), (base: 'つ', mark: '゛'));
    });

    test('半濁音は半濁点に分かれる', () {
      expect(decomposeDakuten('ぱ'), (base: 'は', mark: '゜'));
      expect(decomposeDakuten('ぽ'), (base: 'ほ', mark: '゜'));
    });

    test('分解できない字には null を返す', () {
      for (final char in ['あ', 'か', 'ア', '3', '゛', 'ゐ']) {
        expect(decomposeDakuten(char), isNull, reason: char);
      }
    });

    test('合成対象の 25 字がすべて分解できる', () {
      for (final char in CharSet.hiraganaVoiced.chars) {
        final parts = decomposeDakuten(char);
        expect(parts, isNotNull, reason: char);
        expect(
          CharSet.hiraganaBasic.chars,
          contains(parts!.base),
          reason: '$char の清音 ${parts.base} を集めていない',
        );
      }
    });
  });

  group('濁点の置きかた', () {
    const placement = EmBox(left: 700, bottom: 700, right: 900, top: 800);

    test('置き場所の中に収める', () {
      final placed = placeMark(_square(), placement);
      final bounds = boundsOf(placed.strokes)!;

      expect(bounds.left, greaterThanOrEqualTo(placement.left));
      expect(bounds.right, lessThanOrEqualTo(placement.right));
      expect(bounds.bottom, greaterThanOrEqualTo(placement.bottom));
      expect(bounds.top, lessThanOrEqualTo(placement.top));
    });

    test('縦横おなじ倍率で入れて中央に置く', () {
      final placed = placeMark(_square(), placement);
      final bounds = boundsOf(placed.strokes)!;

      // 正方形を 200x100 の枠に入れると、狭いほうに合わせて 100 角になる。
      expect(bounds.width, closeTo(100, 0.01));
      expect(bounds.height, closeTo(100, 0.01));
      expect(placed.scale, closeTo(0.1, 0.001));
      expect(bounds.centerX, closeTo(placement.centerX, 0.01));
      expect(bounds.centerY, closeTo(placement.centerY, 0.01));
    });

    test('どこに書いても同じ場所へ移る', () {
      final corner = placeMark(_square(left: 0, bottom: 0, size: 300), placement);
      final middle = placeMark(
        _square(left: 400, bottom: 400, size: 300),
        placement,
      );

      expect(boundsOf(corner.strokes)!.left, closeTo(boundsOf(middle.strokes)!.left, 0.01));
      expect(corner.scale, closeTo(middle.scale, 0.001));
    });

    test('点だけの濁点は位置だけ合わせる', () {
      final dot = [
        const Stroke([InkPoint(x: 100, y: 100, t: 0)]),
      ];
      final placed = placeMark(dot, placement);

      expect(placed.scale, 1, reason: '伸縮しようがない');
      expect(placed.strokes.single.points.single.x, placement.centerX);
      expect(placed.strokes.single.points.single.y, placement.centerY);
    });

    test('時刻と筆圧はそのまま残る', () {
      final mark = [
        const Stroke([
          InkPoint(x: 0, y: 0, t: 0, pressure: 0.3),
          InkPoint(x: 500, y: 500, t: 42, pressure: 0.9),
        ]),
      ];
      final placed = placeMark(mark, placement).strokes.single.points;

      expect(placed.map((p) => p.t), [0, 42]);
      expect(placed.map((p) => p.pressure), [0.3, 0.9]);
    });
  });

  group('置き場所の表', () {
    late DakutenPlacements placements;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      placements = await DakutenPlacements.load();
    });

    test('合成対象の 25 字ぶんある', () {
      for (final char in CharSet.hiraganaVoiced.chars) {
        expect(placements[char], isNotNull, reason: char);
      }
    });

    test('濁点は字の右上に寄る', () {
      final box = placements['が']!;

      expect(box.left, greaterThan(500), reason: '右半分');
      expect(box.bottom, greaterThan(500), reason: '上半分');
      expect(box.right, lessThanOrEqualTo(1000));
      expect(box.top, lessThanOrEqualTo(1000));
    });

    test('半濁点は丸なので正方形になる', () {
      final box = placements['ぱ']!;

      expect(box.width, closeTo(box.height, 1));
    });

    test('置き場所は字ごとに違う', () {
      // じ は し が細いぶん、が より内側に寄る。
      expect(placements['じ']!.left, lessThan(placements['が']!.left));
    });

    test('清音そのものは持たない', () {
      expect(placements['か'], isNull);
    });
  });
}
