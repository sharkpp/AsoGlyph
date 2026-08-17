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
    for (final charSet in CharSet.values) {
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
    for (final charSet in CharSet.values) {
      for (final char in charSet.chars) {
        for (final stroke in library[char]!.strokes) {
          final bounds = stroke.getBounds();
          expect(bounds.left, greaterThanOrEqualTo(0), reason: char);
          expect(bounds.top, greaterThanOrEqualTo(0), reason: char);
          expect(
            bounds.right,
            lessThanOrEqualTo(StrokeOrder.viewBox),
            reason: char,
          );
          expect(
            bounds.bottom,
            lessThanOrEqualTo(StrokeOrder.viewBox),
            reason: char,
          );
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

  test('番号は画の書き始めに、枠の中へ置く', () {
    final order = library['あ']!;

    for (var i = 0; i < order.strokeCount; i++) {
      final anchor = order.numberAnchor(i);
      expect(anchor.dx, inInclusiveRange(0, StrokeOrder.viewBox));
      expect(anchor.dy, inInclusiveRange(0, StrokeOrder.viewBox));

      // 書き始めのそば。別の画の番号と取り違える距離ではない。
      final start = order.strokes[i]
          .computeMetrics()
          .single
          .getTangentForOffset(0)!
          .position;
      expect((anchor - start).distance, lessThan(14));
    }
  });

  test('番号は字の外側へ逃げる', () {
    // 手前に逃がすだけだと別の画に乗る。中心から遠ざける向きにも動かす。
    const center = Offset(StrokeOrder.viewBox / 2, StrokeOrder.viewBox / 2);
    for (final char in ['あ', 'ぬ', 'ほ', 'ま']) {
      final order = library[char]!;
      for (var i = 0; i < order.strokeCount; i++) {
        final start = order.strokes[i]
            .computeMetrics()
            .single
            .getTangentForOffset(0)!
            .position;
        // 枠へ寄せる clamp が効く画もあるので、遠ざかることだけを見る。
        expect(
          (order.numberAnchor(i) - center).distance,
          greaterThan((start - center).distance - 8),
          reason: '$char の $i 画目',
        );
      }
    }
  });

  test('矢印は書き始めの少し先に立つ', () {
    // 0 は始点と終点がほぼ重なる。終わりに矢印を立てても向きが決まらない。
    final order = library['0']!;
    final metric = order.strokes[0].computeMetrics().single;
    final start = metric.getTangentForOffset(0)!.position;
    final end = metric.getTangentForOffset(metric.length)!.position;
    expect((end - start).distance, lessThan(15), reason: '始点と終点が近い');

    final mark = order.directionMark(0);
    final distance = (mark.at - start).distance;
    expect(distance, greaterThan(5), reason: '書き始めから離れている');
    expect(distance, lessThan(25), reason: 'それでも書き始めのそば');
  });

  test('矢印は線の外に出す', () {
    // 線の上に描くと字形の一部に見え、なぞる子がその形ごと書いてしまう。
    for (final char in ['0', 'あ', 'し', 'ぽ']) {
      final order = library[char]!;
      for (var i = 0; i < order.strokeCount; i++) {
        final at = order.directionMark(i).at;
        final onLine = order.strokes[i]
            .computeMetrics()
            .single
            .getTangentForOffset(0)!
            .position;
        expect(at, isNot(onLine), reason: char);
      }
    }
  });

  test('画ごとに別の場所へ置く', () {
    final order = library['あ']!;
    final anchors = [
      for (var i = 0; i < order.strokeCount; i++) order.numberAnchor(i),
    ];

    for (var i = 0; i < anchors.length; i++) {
      for (var j = i + 1; j < anchors.length; j++) {
        expect((anchors[i] - anchors[j]).distance, greaterThan(5));
      }
    }
  });

  test('持っていない字は null を返す', () {
    // 「」？ は KanjiVG に無い（SPEC 6.1）。字形で埋めず、無いと答える。
    expect(library['「'], isNull);
  });

  test('濁音も書かせるので運筆を持つ', () {
    for (final char in CharSet.hiraganaVoiced.chars) {
      expect(library[char], isNotNull, reason: char);
    }
    expect(library['が']!.strokeCount, 5, reason: 'か 3 画 ＋ 濁点 2 画');
    expect(library['ぱ']!.strokeCount, 4, reason: 'は 3 画 ＋ 半濁点 1 画');
  });
}
