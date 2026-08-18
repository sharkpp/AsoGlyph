import 'dart:math';

import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/score.dart';
import 'package:asoglyph/model/user.dart';
import 'package:asoglyph/model/word.dart';
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

  group('語の抽選', () {
    final books = [
      const WordBook(
        id: 'b1',
        name: 'テスト',
        words: [
          Word(text: 'ねこ', reading: 'ねこ'),
          Word(text: 'いぬ', reading: 'いぬ'),
          Word(text: 'ありがとう', reading: 'ありがとう'),
        ],
      ),
    ];

    test('字数のぶんだけ語を採る', () {
      final picked = pickWords(_user, store, books, chars: 5, random: Random(1));

      // 語数ではなく字数で区切る。1 セッションの長さを、語の長さに
      // よらず一定に保つため（SPEC 7.1）。
      expect(picked, isNotEmpty);
      expect(
        picked.fold(0, (sum, word) => sum + word.chars.length),
        greaterThanOrEqualTo(5),
      );
    });

    test('同じ語を 2 度出さない', () {
      final picked = pickWords(_user, store, books, chars: 99, random: Random(1));

      expect(picked.map((word) => word.text).toSet(), hasLength(picked.length));
      expect(picked, hasLength(3), reason: '語が尽きたら終わる');
    });

    test('出したい字を多く含む語ほど出やすい', () async {
      for (final char in CharSet.hiragana.chars) {
        await store.add(_written(char, overall: 1));
      }
      // 「ねこ」の字だけ苦手にする。
      await store.add(_written('ね', overall: 0));
      await store.add(_written('こ', overall: 0));

      var neko = 0;
      final random = Random(3);
      for (var i = 0; i < 200; i++) {
        if (pickWords(_user, store, books, chars: 1, random: random).first.text ==
            'ねこ') {
          neko++;
        }
      }

      // 3 語から等確率なら 67 回。
      expect(neko, greaterThan(100));
    });

    test('長い語というだけでは出やすくならない', () {
      // 合計にすると長い語ばかりが出る。「ありがとう」が「そら」より
      // 2.5 倍出やすい、という理由が無い。
      var long = 0;
      final random = Random(5);
      for (var i = 0; i < 200; i++) {
        if (pickWords(_user, store, books, chars: 1, random: random).first.text ==
            'ありがとう') {
          long++;
        }
      }

      expect(long, lessThan(100));
    });

    test('割り振られていない単語帳からは出さない', () {
      final user = _user.copyWith(wordBooks: {'other'});

      expect(pickWords(user, store, books, random: Random(1)), isEmpty);
      expect(writableWords(user, books), isEmpty);
    });

    test('集める文字種で書けない語は出さない', () {
      final user = _user.copyWith(collecting: {CharSet.digits});

      expect(writableWords(user, books), isEmpty);
    });

    test('同じ語が 2 冊にあっても 1 つにまとめる', () {
      final twice = [
        ...books,
        const WordBook(
          id: 'b2',
          name: 'もう 1 冊',
          words: [Word(text: 'ねこ', reading: 'ねこ')],
        ),
      ];

      expect(
        writableWords(_user, twice).where((word) => word.text == 'ねこ'),
        hasLength(1),
      );
    });
  });

  group('語に出てこない字', () {
    test('語に無い字を並べる', () {
      final books = [
        const WordBook(
          id: 'b1',
          name: 'テスト',
          words: [Word(text: 'ねこ', reading: 'ねこ')],
        ),
      ];

      final missing = charsMissingFromWords(_user, books);

      expect(missing, isNot(contains('ね')));
      expect(missing, isNot(contains('こ')));
      expect(missing, contains('あ'));
      expect(missing, hasLength(CharSet.hiragana.chars.length - 2));
    });

    test('集めない文字種の字は数えない', () {
      final books = [
        const WordBook(
          id: 'b1',
          name: 'テスト',
          words: [Word(text: 'ねこ', reading: 'ねこ')],
        ),
      ];

      expect(charsMissingFromWords(_user, books), isNot(contains('ア')));
    });
  });
}
