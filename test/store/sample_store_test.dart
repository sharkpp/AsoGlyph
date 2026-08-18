import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/score.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

Sample _sample(
  String char, {
  PracticeMode mode = PracticeMode.copy,
  double x = 0,
  Score? score,
  bool rejected = false,
}) {
  return Sample.now(
    char: char,
    mode: mode,
    score: score,
    rejected: rejected,
    strokes: [
      Stroke([
        InkPoint(x: x, y: 0, t: 0, pressure: 0),
        InkPoint(x: x + 100, y: 500, t: 20, pressure: 0),
      ]),
    ],
  );
}

void main() {
  group('SampleStore', () {
    test('書いた記録を読み戻せる', () async {
      final store = await openMemoryStore();
      final sample = _sample('あ');
      await store.add(sample);

      final read = await store.read(sample.id);
      expect(read.char, 'あ');
      expect(read.mode, PracticeMode.copy);
      expect(read.strokes.single.points, hasLength(2));
      expect(read.strokes.single.points.last.y, 500);
    });

    test('同じ字を書き足しても上書きしない', () async {
      final store = await openMemoryStore();
      await store.add(_sample('あ'));
      final second = _sample('あ', x: 200);
      await store.add(second);

      expect(store.attemptCount('あ'), 2);
      expect(store.latestId('あ', includeTraced: false), second.id, reason: '最新が素材になる');
      expect((await store.read(second.id)).strokes.single.points.first.x, 200);
    });

    test('なぞり書きは素材にしない', () async {
      final store = await openMemoryStore();
      final copy = _sample('い');
      await store.add(copy);
      await store.add(_sample('い', mode: PracticeMode.trace));

      expect(store.attemptCount('い'), 2, reason: '進捗としては数える');
      expect(store.latestId('い', includeTraced: false), copy.id);
    });

    test('なぞり書きしかない字は集めた字に入らない', () async {
      final store = await openMemoryStore();
      await store.add(_sample('う', mode: PracticeMode.trace));

      expect(store.latestId('う', includeTraced: false), isNull);
      expect(store.collectedChars(includeTraced: false), isEmpty);
    });

    test('開き直しても記録が残る', () async {
      final store = await openMemoryStore();
      await store.add(_sample('か'));
      await store.add(_sample('き'));

      await store.load();
      expect(store.collectedChars(includeTraced: false), unorderedEquals(['か', 'き']));
    });

    test('書くたびに通知する', () async {
      final store = await openMemoryStore();
      var notified = 0;
      store.addListener(() => notified++);

      await store.add(_sample('く'));
      expect(notified, 1);
    });

    test('鏡文字・書き損じは素材にしない', () async {
      final store = await openMemoryStore();
      await store.add(_sample('あ', rejected: true));

      // 素材に採らないのは、なぞりを除けばここだけ（SPEC 1 / 4.1）。
      expect(store.latestId('あ', includeTraced: true), isNull);
      expect(store.collectedChars(includeTraced: true), isEmpty);
      // 記録そのものは残る。書いた事実は消さない（SPEC 4.1）。
      expect(store.attemptCount('あ'), 1);
      expect(store.attempts('あ').single.rejected, isTrue);
    });

    test('測りを読み戻せる', () async {
      final store = await openMemoryStore();
      await store.add(
        _sample(
          'あ',
          score: const Score(
            shape: 0.5,
            strokes: 1,
            fit: 0.25,
            durationMs: 1200,
            retries: 2,
          ),
        ),
      );

      await store.load();
      final score = store.attempts('あ').single.score!;
      expect(score.shape, 0.5);
      expect(score.retries, 2);
      expect(score.durationMs, 1200);
    });

    test('ぜんぶ消すと空になる', () async {
      final store = await openMemoryStore();
      await store.add(_sample('あ'));
      await store.add(_sample('い'));

      await store.clear();

      expect(store.collectedChars(includeTraced: false), isEmpty);
      expect(store.attemptCount('あ'), 0);

      // 読み直しても戻らない。記録そのものが消えている。
      await store.load();
      expect(store.collectedChars(includeTraced: false), isEmpty);
    });
  });
}
