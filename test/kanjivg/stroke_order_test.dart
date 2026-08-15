import 'package:asoglyph/kanjivg/stroke_order.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StrokeOrderLibrary library;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    library = await StrokeOrderLibrary.load();
  });

  test('収集対象の字は全部そろっている', () {
    for (final charSet in CharSet.values.where((s) => s.collect)) {
      for (final char in charSet.chars) {
        expect(library[char], isNotNull, reason: '$char の書き順が無い');
      }
    }
  });

  test('画数が KanjiVG のとおりになる', () {
    expect(library['あ']!.strokeCount, 3);
    expect(library['い']!.strokeCount, 2);
    expect(library['ん']!.strokeCount, 1);
    expect(library['0']!.strokeCount, 1);
  });

  test('字は KanjiVG の座標系に収まる', () {
    for (final charSet in CharSet.values.where((s) => s.collect)) {
      for (final char in charSet.chars) {
        for (final stroke in library[char]!.strokes) {
          final bounds = stroke.getBounds();
          expect(bounds.left, greaterThanOrEqualTo(0), reason: char);
          expect(bounds.top, greaterThanOrEqualTo(0), reason: char);
          expect(bounds.right, lessThanOrEqualTo(StrokeOrder.viewBox), reason: char);
          expect(bounds.bottom, lessThanOrEqualTo(StrokeOrder.viewBox), reason: char);
        }
      }
    }
  });

  test('書き順の途中を取り出せる', () {
    final order = library['あ']!;

    expect(
      order.partial(0, 0).getBounds().isEmpty,
      isTrue,
      reason: '書き始める前は 1 画目の起点だけ',
    );
    expect(
      order.partial(0, 1).getBounds(),
      order.strokes.first.getBounds(),
      reason: '書き終わりは 1 画まるごと',
    );

    final half = order.partial(0, 0.5).getBounds();
    final whole = order.strokes.first.getBounds();
    expect(half.width, lessThan(whole.width), reason: '途中はまだ短い');
  });

  test('持っていない字は null を返す', () {
    // 「」？ は KanjiVG に無い（SPEC 6.1）。字形で埋めず、無いと答える。
    expect(library['「'], isNull);
  });

  test('書かせない字は同梱しない', () {
    // 濁音は清音＋濁点で合成する。KanjiVG の が を持ち歩く理由がない（SPEC 5.1）。
    for (final char in CharSet.hiraganaVoiced.chars) {
      expect(library[char], isNull, reason: char);
    }
  });
}
