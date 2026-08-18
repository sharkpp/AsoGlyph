import 'package:asoglyph/export/resolve_recipe.dart';
import 'package:asoglyph/font/glyph.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/font_recipe.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/score.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

Sample _written(
  String char, {
  PracticeMode mode = PracticeMode.copy,
  required DateTime at,
  double? overall,
  bool rejected = false,
}) => Sample(
  id: '$char-${at.toIso8601String()}-${mode.name}',
  char: char,
  mode: mode,
  writtenAt: at,
  rejected: rejected,
  score: overall == null
      ? null
      : Score(
          shape: overall,
          strokes: overall,
          fit: overall,
          durationMs: 1000,
          retries: 0,
        ),
  strokes: [
    Stroke(const [
      InkPoint(x: 300, y: 500, t: 0, pressure: 0),
      InkPoint(x: 700, y: 500, t: 20, pressure: 0),
    ]),
  ],
);

FontRecipe _recipe({
  Set<CharSet>? charSets,
  Policy base = const LatestPolicy(),
  Map<CharSet, Policy> groupRules = const {},
  Map<String, String> charRules = const {},
}) => FontRecipe(
  id: 'r',
  name: 'テスト',
  createdAt: DateTime.utc(2026),
  fontMeta: FontMetadata(familyName: 'Test'),
  charSets: charSets ?? CharSet.values.toSet(),
  base: base,
  groupRules: groupRules,
  charRules: charRules,
);

void main() {
  final spring = DateTime.utc(2026, 4, 1);
  final summer = DateTime.utc(2026, 7, 1);
  final autumn = DateTime.utc(2026, 10, 1);

  late SampleStore store;
  setUp(() async => store = await openMemoryStore());

  Map<String, String> resolve(FontRecipe recipe, {bool includeTraced = false}) =>
      resolveRecipe(recipe, store, includeTraced: includeTraced);

  group('base = latest', () {
    test('その字の最新を採る', () async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('あ', at: autumn));

      expect(resolve(_recipe())['あ'], 'あ-2026-10-01T00:00:00.000Z-copy');
    });

    test('書いていない字は載らない', () async {
      await store.add(_written('あ', at: spring));

      final resolved = resolve(_recipe());
      expect(resolved.keys, ['あ']);
      // 未収集の字を KanjiVG の字形で埋めない（SPEC 6.3）。
      expect(resolved.containsKey('い'), isFalse);
    });

    test('なぞった字を混ぜるかを選べる', () async {
      await store.add(_written('い', mode: PracticeMode.trace, at: spring));

      expect(resolve(_recipe()), isEmpty);
      expect(resolve(_recipe(), includeTraced: true).keys, ['い']);
    });
  });

  group('base = at', () {
    test('その時点以前で最新を採る', () async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('あ', at: autumn));

      // 夏の時点では、春に書いた字がいちばん新しい。
      expect(
        resolve(_recipe(base: AtPolicy(summer)))['あ'],
        'あ-2026-04-01T00:00:00.000Z-copy',
      );
    });

    test('その時点より後にしか書いていない字は載らない', () async {
      await store.add(_written('あ', at: autumn));

      expect(resolve(_recipe(base: AtPolicy(summer))), isEmpty);
    });

    test('ちょうどその時刻に書いた字は入る', () async {
      await store.add(_written('あ', at: summer));

      expect(resolve(_recipe(base: AtPolicy(summer))).keys, ['あ']);
    });
  });

  group('解決順', () {
    test('groupRules は base より強い', () async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('あ', at: autumn));
      await store.add(_written('ア', at: spring));
      await store.add(_written('ア', at: autumn));

      // ひらがなは春の字、カタカナは今の字。
      final resolved = resolve(
        _recipe(groupRules: {CharSet.hiragana: AtPolicy(summer)}),
      );
      expect(resolved['あ'], 'あ-2026-04-01T00:00:00.000Z-copy');
      expect(resolved['ア'], 'ア-2026-10-01T00:00:00.000Z-copy');
    });

    test('charRules はいちばん強い', () async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('あ', at: autumn));

      const first = 'あ-2026-04-01T00:00:00.000Z-copy';
      final resolved = resolve(
        _recipe(base: const LatestPolicy(), charRules: {'あ': first}),
      );
      expect(resolved['あ'], first, reason: '最新ではなく名指しの版');
    });

    test('charRules はなぞりの扱いにも左右されない', () async {
      final traced = _written('い', mode: PracticeMode.trace, at: spring);
      await store.add(traced);

      // 親がその字を名指しで選んでいる。混ぜない設定でも採る。
      expect(resolve(_recipe(charRules: {'い': traced.id}))['い'], traced.id);
    });

    test('指す先が消えた charRules は規則へ落ちる', () async {
      await store.add(_written('あ', at: autumn));

      final resolved = resolve(_recipe(charRules: {'あ': 'もう無い id'}));
      expect(resolved['あ'], 'あ-2026-10-01T00:00:00.000Z-copy');
    });
  });

  group('charSets', () {
    test('出力対象の文字種だけが載る', () async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('ア', at: spring));
      await store.add(_written('5', at: spring));

      final resolved = resolve(_recipe(charSets: {CharSet.hiragana}));
      expect(resolved.keys, ['あ']);
    });

    test('分母は出力対象の字数', () {
      expect(
        totalChars(_recipe(charSets: {CharSet.hiragana})),
        CharSet.hiragana.chars.length,
      );
      expect(
        totalChars(_recipe(charSets: {CharSet.hiragana, CharSet.digits})),
        CharSet.hiragana.chars.length + CharSet.digits.chars.length,
      );
    });
  });

  test('「2026年春の、ひらがなだけのフォント」が作れる', () async {
    await store.add(_written('あ', at: spring));
    await store.add(_written('あ', at: autumn));
    await store.add(_written('い', at: autumn));
    await store.add(_written('ア', at: spring));

    // SPEC 4.3 の例。春までに書けていた ひらがな だけが入る。
    final resolved = resolve(
      _recipe(charSets: {CharSet.hiragana}, base: AtPolicy(spring)),
    );

    expect(resolved.keys, ['あ']);
    expect(resolved['あ'], 'あ-2026-04-01T00:00:00.000Z-copy');
  });
  group('いちばん よく書けた字', () {
    test('同じ字のうち、測りのいちばん良いものを採る', () async {
      final store = await openMemoryStore();
      final best = _written('あ', at: DateTime(2026, 4, 1), overall: 0.9);
      await store.add(best);
      await store.add(_written('あ', at: DateTime(2026, 5, 1), overall: 0.2));

      final resolved = resolveRecipe(
        _recipe(base: const BestPolicy()),
        store,
        includeTraced: false,
      );

      // 点で採否を決めるのではなく、同じ字のうちどれを採るかを選ぶだけ。
      expect(resolved['あ'], best.id);
    });

    test('測りが無い字は、いちばん新しいものを採る', () async {
      final store = await openMemoryStore();
      await store.add(_written('あ', at: DateTime(2026, 4, 1)));
      final newest = _written('あ', at: DateTime(2026, 5, 1));
      await store.add(newest);

      final resolved = resolveRecipe(
        _recipe(base: const BestPolicy()),
        store,
        includeTraced: false,
      );

      // 0 点として扱うと、採点できない字だけ最初に書いた字が残り続ける。
      expect(resolved['あ'], newest.id);
    });

    test('はねた字は、点が良くても採らない', () async {
      final store = await openMemoryStore();
      await store.add(
        _written('あ', at: DateTime(2026, 4, 1), overall: 1, rejected: true),
      );
      final kept = _written('あ', at: DateTime(2026, 5, 1), overall: 0.3);
      await store.add(kept);

      final resolved = resolveRecipe(
        _recipe(base: const BestPolicy()),
        store,
        includeTraced: false,
      );

      expect(resolved['あ'], kept.id);
    });
  });

}
