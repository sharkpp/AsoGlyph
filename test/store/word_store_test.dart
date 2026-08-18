import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/user.dart';
import 'package:asoglyph/model/word.dart';
import 'package:asoglyph/store/word_attempt_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('WordBookStore', () {
    test('同梱の単語帳を読む', () async {
      final books = await openMemoryWordBooks();

      expect(books.all.map((book) => book.name), contains('ひらがなのことば'));
      // 読みは全部の語に付いている（SPEC 7.4）。
      expect(
        books.all.every(
          (book) => book.words.every((word) => word.reading.isNotEmpty),
        ),
        isTrue,
      );
    });

    test('同梱の語は、集められる字だけで書ける', () async {
      final books = await openMemoryWordBooks();
      final all = {for (final set in CharSet.values) ...set.chars};

      // 集める文字種に無い字が混じった語は出題候補から外れる（SPEC 7.4）。
      // 同梱の単語帳がその条件で丸ごと消えては意味がない。
      for (final book in books.all) {
        expect(
          book.words.where((word) => !word.isWritable(all)),
          isEmpty,
          reason: '${book.name} に、まだ集められない字の語がある',
        );
      }
    });

    test('ひらがなの単語帳は、ひらがなだけで書ける', () async {
      final books = await openMemoryWordBooks();
      final book = books.all.firstWhere((book) => book.name == 'ひらがなのことば');
      final hiragana = CharSet.hiragana.chars.toSet();

      // カタカナを集めていない 4 歳でも、この単語帳は丸ごと使える。
      expect(book.words.where((word) => !word.isWritable(hiragana)), isEmpty);
    });

    test('取り込んだ単語帳は残り、消せる', () async {
      final db = await openMemoryDatabase();
      final books = await openMemoryWordBooks(db);
      final bundled = books.all.length;

      final added = await books.add(
        const WordBook(
          id: 'ignored',
          name: 'うちのことば',
          words: [Word(text: 'ぱぱ', reading: 'ぱぱ')],
        ),
      );
      expect(books.all, hasLength(bundled + 1));
      expect(books.isImported(added.id), isTrue);

      // 開き直しても残る。
      final reopened = await openMemoryWordBooks(db);
      expect(reopened.all.last.name, 'うちのことば');
      expect(reopened.all.last.words.single.text, 'ぱぱ');

      await reopened.remove(reopened.all.last.id);
      expect(reopened.all, hasLength(bundled));
    });

    test('同梱の単語帳は消させない', () async {
      final books = await openMemoryWordBooks();
      final bundled = books.all.first;

      expect(books.isImported(bundled.id), isFalse);
      await books.remove(bundled.id);
      expect(books.all, contains(bundled));
    });
  });

  group('WordAttemptStore', () {
    test('書き終えた語を数える', () async {
      final store = await WordAttemptStore.open(
        await openMemoryDatabase(),
        userId: 'test-user',
      );

      expect(store.countOf('ねこ'), 0);
      await store.finish(word: 'ねこ', sampleIds: ['a', 'b']);
      expect(store.countOf('ねこ'), 1);
      expect(store.all.single.sampleIds, ['a', 'b']);

      await store.finish(word: 'ねこ', sampleIds: ['c', 'd']);
      expect(store.countOf('ねこ'), 2, reason: '書くたびに増える');
    });

    test('人ごとに分かれる', () async {
      final session = await openMemorySession();
      await session.attempts.finish(word: 'ねこ', sampleIds: ['a']);

      final sister = await session.addUser(
        name: 'いもうと',
        avatar: Avatar.rabbit,
      );
      expect(session.attempts.countOf('ねこ'), 0, reason: 'よその履歴は見えない');

      await session.attempts.finish(word: 'いぬ', sampleIds: ['b']);
      expect(session.attempts.all, hasLength(1));

      await session.switchTo(session.users.all.first.id);
      expect(session.attempts.countOf('ねこ'), 1, reason: '戻せば自分の履歴が見える');
      expect(session.attempts.countOf('いぬ'), 0);
      expect(sister.id, isNot(session.current.id));
    });
  });
}

