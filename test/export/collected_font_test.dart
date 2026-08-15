import 'dart:typed_data';

import 'package:asoglyph/export/collected_font.dart';
import 'package:asoglyph/font/font_builder.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/kanjivg/dakuten_placement.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

/// 面積のある字を書いた記録。輪郭が起こせる程度の長さを持たせる。
Sample _written(String char, {PracticeMode mode = PracticeMode.copy}) {
  return Sample.now(
    char: char,
    mode: mode,
    strokes: [
      Stroke([
        for (var i = 0; i <= 10; i++)
          InkPoint(x: 200 + i * 60.0, y: 500, t: i * 16, pressure: 0),
      ]),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SampleStore store;
  late DakutenPlacements placements;

  setUpAll(() async => placements = await DakutenPlacements.load());
  setUp(() async => store = await openMemoryStore());

  group('収集済みフォント', () {
    test('集めた字だけがグリフになる', () async {
      await store.add(_written('あ'));
      await store.add(_written('5'));
      // なぞり書きだけの字は素材にしない（SPEC 7.1）。
      await store.add(_written('い', mode: PracticeMode.trace));

      final glyphs = await collectGlyphs(store, placements: placements);

      expect(
        glyphs.map((g) => String.fromCharCode(g.codePoint)),
        ['5', 'あ'],
        reason: 'コードポイント昇順。未収集の字は載らない',
      );
      expect(glyphs.every((g) => g.contours.isNotEmpty), isTrue);
    });

    test('字幅は文字種で決まる', () async {
      await store.add(_written('あ'));
      await store.add(_written('5'));

      final glyphs = await collectGlyphs(store, placements: placements);
      final widths = {
        for (final glyph in glyphs)
          String.fromCharCode(glyph.codePoint): glyph.advanceWidth,
      };

      // 和文は全角 1000、数字は半角 500（SPEC 5.2）。
      expect(widths, {'あ': 1000, '5': 500});
    });

    test('進み具合を字数ぶん知らせる', () async {
      for (final char in ['あ', 'い', 'う']) {
        await store.add(_written(char));
      }

      final reported = <(int, int)>[];
      await collectGlyphs(
        store,
        placements: placements,
        onProgress: (done, total) => reported.add((done, total)),
      );

      expect(reported, [(1, 3), (2, 3), (3, 3)]);
    });

    test('清音と濁点がそろうと濁音が合成される', () async {
      await store.add(_written('か'));
      await store.add(_written('゛'));

      final glyphs = await collectGlyphs(store, placements: placements);
      final chars = glyphs.map((g) => String.fromCharCode(g.codePoint));

      expect(chars, contains('が'), reason: 'か ＋ ゛ から作る');
      expect(chars, isNot(contains('ぱ')), reason: '半濁点はまだ無い');
      expect(chars, isNot(contains('ざ')), reason: 'さ を集めていない');
      expect(
        glyphs.firstWhere((g) => g.codePoint == 'が'.runes.first).contours,
        isNotEmpty,
      );
    });

    test('濁点だけでは何も作れない', () async {
      await store.add(_written('゛'));

      final glyphs = await collectGlyphs(store, placements: placements);

      expect(
        glyphs.map((g) => String.fromCharCode(g.codePoint)),
        ['゛'],
        reason: '濁点そのものは字として載る',
      );
    });

    test('濁音は清音より画が増える', () async {
      await store.add(_written('か'));
      await store.add(_written('゛'));

      final glyphs = await collectGlyphs(store, placements: placements);
      final ka = glyphs.firstWhere((g) => g.codePoint == 'か'.runes.first);
      final ga = glyphs.firstWhere((g) => g.codePoint == 'が'.runes.first);

      expect(
        ga.contours.length,
        greaterThan(ka.contours.length),
        reason: '濁点のぶん輪郭が増える',
      );
      expect(ga.advanceWidth, ka.advanceWidth, reason: '濁音も全角');
    });

    test('.notdef とスペースを足したフォントが出る', () async {
      await store.add(_written('あ'));
      await store.add(_written('5'));

      for (final format in FontFormat.values) {
        final font = await buildCollectedFont(
          store: store,
          placements: placements,
          meta: FontMetadata(familyName: 'AsoGlyph'),
          format: format,
        );

        // .notdef / space / 5 / あ
        expect(_numGlyphs(font), 4, reason: format.name);
      }
    });
  });
}

/// maxp から収録グリフ数を読む。
int _numGlyphs(Uint8List font) {
  final data = ByteData.sublistView(font);
  final tableCount = data.getUint16(4);

  for (var i = 0; i < tableCount; i++) {
    final entry = 12 + i * 16;
    final tag = String.fromCharCodes(font.sublist(entry, entry + 4));
    if (tag == 'maxp') return data.getUint16(data.getUint32(entry + 8) + 4);
  }
  throw StateError('maxp が無い');
}
