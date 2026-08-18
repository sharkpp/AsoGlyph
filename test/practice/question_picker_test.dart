import 'dart:math';

import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/score.dart';
import 'package:asoglyph/model/user.dart';
import 'package:asoglyph/practice/question_picker.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

final _user = User(
  id: 'test-user',
  displayName: 'じぶん',
  avatar: Avatar.cat,
  createdAt: DateTime(2026, 4, 1),
  collecting: const {CharSet.hiragana},
);

Sample _written(
  String char, {
  double overall = 1,
  bool rejected = false,
  int retries = 0,
  int durationMs = 1000,
  PracticeMode mode = PracticeMode.copy,
}) => Sample.now(
  char: char,
  mode: mode,
  strokes: [
    Stroke(const [
      InkPoint(x: 300, y: 500, t: 0),
      InkPoint(x: 700, y: 500, t: 20),
    ]),
  ],
  score: Score(
    shape: overall,
    strokes: overall,
    fit: overall,
    durationMs: durationMs,
    retries: retries,
  ),
  rejected: rejected,
);

void main() {
  late SampleStore store;

  setUp(() async {
    store = await openMemoryStore();
  });

  Question questionFor(String char) =>
      questionsFor(_user, store).firstWhere((q) => q.char == char);

  group('苦手さ', () {
    test('書いたことのない字は真ん中', () {
      // 分からないものを「得意」とも「苦手」とも決めない。
      expect(difficultyOf('あ', store), 0.5);
    });

    test('よく書けた字は下がり、書けなかった字は上がる', () async {
      await store.add(_written('あ', overall: 1));
      await store.add(_written('い', overall: 0));

      expect(difficultyOf('あ', store), lessThan(0.3));
      expect(difficultyOf('い', store), greaterThan(0.6));
    });

    test('はねた字はいちばん苦手なものとして数える', () async {
      // 書けなかったという事実そのものが、その字が苦手だという証拠になる。
      await store.add(_written('あ', overall: 1, rejected: true));

      expect(difficultyOf('あ', store), 1);
    });

    test('書き直しとかかった時間も苦手さのうち', () async {
      await store.add(_written('あ', overall: 0.8));
      await store.add(_written('い', overall: 0.8, retries: 4,
          durationMs: 30000));

      expect(difficultyOf('い', store), greaterThan(difficultyOf('あ', store)));
    });

    test('直近の試行だけを見る', () async {
      // 昔うまく書けなかったことを、いつまでも引きずらせない。
      await store.add(_written('あ', overall: 0));
      for (var i = 0; i < 5; i++) {
        await store.add(_written('あ', overall: 1));
      }

      expect(difficultyOf('あ', store), lessThan(0.3));
    });
  });

  group('出題の重み', () {
    test('集めていない字が、集めた字より出やすい', () async {
      await store.add(_written('あ', overall: 1));

      expect(questionFor('い').weight, greaterThan(questionFor('あ').weight));
      expect(questionFor('あ').collected, isTrue);
    });

    test('集まってくると、苦手な字の反復へ移る', () async {
      // 未収集がまだ多いうちは、苦手さより「まだ書いていない」が効く。
      await store.add(_written('あ', overall: 0));
      final early = questionsFor(_user, store);
      final earlyGap =
          early.firstWhere((q) => q.char == 'い').weight -
          early.firstWhere((q) => q.char == 'あ').weight;

      // 全部集まったあとは、苦手な字のほうが出やすくなる。
      for (final char in CharSet.hiragana.chars) {
        if (char != 'あ') await store.add(_written(char, overall: 1));
      }
      final late_ = questionsFor(_user, store);
      final lateGap =
          late_.firstWhere((q) => q.char == 'い').weight -
          late_.firstWhere((q) => q.char == 'あ').weight;

      expect(earlyGap, greaterThan(0), reason: '集めていない い が出やすい');
      expect(lateGap, lessThan(0), reason: '苦手な あ が出やすい');
    });

    test('なぞっただけの字は、まだ集めていない扱い', () async {
      await store.add(_written('あ', mode: PracticeMode.trace));

      // なぞった字はその子の字とは言いにくい（SPEC 7.1）。
      expect(questionFor('あ').collected, isFalse);
    });

    test('集めない文字種は出さない', () {
      final chars = questionsFor(_user, store).map((q) => q.char).toSet();

      expect(chars, contains('あ'));
      expect(chars, isNot(contains('ア')));
      expect(chars, isNot(contains('0')));
    });

    test('どの字にも出る目はある', () async {
      for (final char in CharSet.hiragana.chars) {
        await store.add(_written(char, overall: 1));
      }

      // 重みが 0 になると、その字は二度と出なくなる。
      expect(questionsFor(_user, store).every((q) => q.weight > 0), isTrue);
    });
  });

  group('抽選', () {
    test('求めた字数を、重複なく選ぶ', () {
      final picked = pickQuestions(_user, store, count: 5, random: Random(1));

      expect(picked, hasLength(5));
      expect(picked.toSet(), hasLength(5), reason: '同じ字を 2 度出さない');
    });

    test('文字種の字数より多くは選べない', () {
      final user = _user.copyWith(collecting: {CharSet.digits});
      final picked = pickQuestions(user, store, count: 99, random: Random(1));

      expect(picked, hasLength(CharSet.digits.chars.length));
    });

    test('苦手な字ほど多く出る', () async {
      final user = _user.copyWith(collecting: {CharSet.digits});
      for (final char in CharSet.digits.chars) {
        await store.add(_written(char, overall: char == '7' ? 0 : 1));
      }

      var seven = 0;
      final random = Random(7);
      for (var i = 0; i < 200; i++) {
        if (pickQuestions(user, store, count: 1, random: random).first == '7') {
          seven++;
        }
      }

      // 10 字から等確率で選べば 20 回。苦手な字はそれより多く出る。
      expect(seven, greaterThan(30));
    });
  });
}
