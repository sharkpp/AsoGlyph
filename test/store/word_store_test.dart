import 'dart:typed_data';

import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/user.dart';
import 'package:asoglyph/model/word.dart';
import 'package:asoglyph/store/word_attempt_store.dart';
import 'package:asoglyph/store/word_book_store.dart';
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
      // 内蔵の単語帳がその条件で丸ごと消えては意味がない。
      //
      // 動作確認用の辞書（`_` で始まる資産）は見ない。手元に置いたものが
      // 何であれ、配るものの保証は変わらない。
      for (final book in books.all.where((book) => !book.isDebugBook)) {
        expect(
          book.words.where((word) => !word.isWritable(all)),
          isEmpty,
          reason: '${book.name} に、まだ集められない字の語がある',
        );
      }
    });

    test('おまかせで全部の字に行き着ける', () async {
      final books = await openMemoryWordBooks();
      final covered = {
        for (final book in books.all)
          if (!book.isDebugBook) ...book.chars,
      };

      // おまかせは語で出す（SPEC 7.3）。語に出てこない字は、その導線では
      // 永久に出てこない。はじめの単語帳だけでフォントが埋まるようにしておく。
      //
      // ヲヂヅゥ は今の日本語の語に出てこない。管理画面の「ことばに
      // 出てこない字」に挙がるので、親が語を足すか一覧から選ばせる。
      const unused = {'ヲ', 'ヂ', 'ヅ', 'ゥ'};
      for (final set in CharSet.values) {
        expect(
          set.chars.where((char) => !covered.contains(char)),
          unused.where(set.chars.contains),
          reason: '${set.label} に、語から行き着けない字がある',
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

    test('足した単語帳は残り、消せる', () async {
      final db = await openMemoryDatabase();
      final books = await openMemoryWordBooks(db);
      final bundled = books.all.length;

      await books.add(
        const WordBook(
          id: 'ignored',
          name: 'うちのことば',
          words: [Word(text: 'ぱぱ', reading: 'ぱぱ')],
        ),
      );
      expect(books.all, hasLength(bundled + 1));

      // 開き直しても残る。
      final reopened = await openMemoryWordBooks(db);
      expect(reopened.all.last.name, 'うちのことば');
      expect(reopened.all.last.words.single.text, 'ぱぱ');

      await reopened.remove(reopened.all.last.id);
      expect(reopened.all, hasLength(bundled));
    });

    test('内蔵の単語帳は直せない・消せない', () async {
      final db = await openMemoryDatabase();
      final books = await openMemoryWordBooks(db);
      final book = books.all.first;
      final before = books.all.length;
      expect(book.isBundled, isTrue);

      // 直せると「元に戻す」道が要る。消せても開き直すと戻ってくるので、
      // 消せたように見えて戻る、といういちばん分かりにくい振る舞いになる。
      await books.save(book.copyWith(name: 'うちのひらがな'));
      await books.remove(book.id);

      final reopened = await openMemoryWordBooks(db);
      expect(reopened.all.first.name, book.name);
      expect(reopened.all, hasLength(before));
    });

    test('内蔵をもとに、直せるコピーを作れる', () async {
      final books = await openMemoryWordBooks();
      final book = books.all.first;

      final copy = await books.copy(book, name: 'うちのひらがな');
      await books.save(
        copy.copyWith(words: [...copy.words, const Word(text: 'ぱぱ', reading: 'ぱぱ')]),
      );

      // 語を 1 つ足したいだけの親が、まるごと作り直すことにならないように。
      expect(copy.isBundled, isFalse);
      expect(books.all.last.words.last.text, 'ぱぱ');
      expect(books.all.first.words, book.words, reason: 'もとは変わらない');
    });

    test('開き直しても内蔵はそろっている', () async {
      final db = await openMemoryDatabase();
      final first = await openMemoryWordBooks(db);
      final assets = [for (final book in first.all) book.source];

      // 空のときだけ入れる作りにすると、あとからアプリに足した辞書が
      // すでに使っている端末に出てこない。
      final reopened = await openMemoryWordBooks(db);
      expect([for (final book in reopened.all) book.source], assets);
      expect(reopened.all.every((book) => book.isBundled), isTrue);
    });

    test('自分の単語帳は、内蔵を合わせるときに消えない', () async {
      final db = await openMemoryDatabase();
      final books = await openMemoryWordBooks(db);
      await books.add(
        const WordBook(
          id: '',
          name: 'うちのことば',
          words: [Word(text: 'ぱぱ', reading: 'ぱぱ')],
        ),
      );

      // 「アプリから外した辞書を片づける」が、自分のぶんまで巻き込まない。
      final reopened = await openMemoryWordBooks(db);
      expect(
        reopened.all.where((book) => !book.isBundled).single.name,
        'うちのことば',
      );
    });

    test('動作確認用の辞書は、名前の先頭で見分ける', () {
      // リリースには存在しない（.gitignore）。手元では内蔵と同じ場所に
      // 並ぶので、見分けが付くようにする。
      expect(WordBookStore.isDebugAsset('assets/words/_ためし.yaml'), isTrue);
      expect(WordBookStore.isDebugAsset('assets/words/hiragana.yaml'), isFalse);
    });
  });

  group('語の絵', () {
    test('入れて読み戻せる。id は拡張子を残す', () async {
      final db = await openMemoryDatabase();
      final books = await openMemoryWordBooks(db);

      final id = await books.addImage(
        Uint8List.fromList([1, 2, 3]),
        fileName: 'ねこの絵.PNG',
      );

      // 拡張子がそのまま形式になる。SVG だけ描き方が違う。
      expect(id, endsWith('.png'));
      expect(await books.readImage(id), [1, 2, 3]);

      // 語から指していれば、開き直しても残る（指されない絵は片づく）。
      await books.add(
        WordBook(
          id: '',
          name: 'え',
          words: [Word(text: 'ねこ', reading: 'ねこ', image: id)],
        ),
      );
      final reopened = await openMemoryWordBooks(db);
      expect(await reopened.readImage(id), [1, 2, 3]);
    });

    test('一度読んだ絵は持っておく', () async {
      final books = await openMemoryWordBooks();
      final id = await books.addImage(
        Uint8List.fromList([1]),
        fileName: 'a.png',
      );

      // 一覧では同じ絵が何度も並ぶ。毎回読み直さない。
      expect(books.cachedImage(id), isNotNull);
    });

    test('どの語からも指されていない絵は片づける', () async {
      final books = await openMemoryWordBooks();
      final kept = await books.addImage(
        Uint8List.fromList([1]),
        fileName: 'a.png',
      );
      final orphan = await books.addImage(
        Uint8List.fromList([2]),
        fileName: 'b.png',
      );

      final book = await books.add(
        WordBook(
          id: '',
          name: 'え',
          words: [Word(text: 'ねこ', reading: 'ねこ', image: kept)],
        ),
      );
      await books.save(book);

      // 絵は記録ではなく持ち物。放っておくと端末の中に溜まる。
      expect(await books.readImage(kept), isNotNull);
      expect(await books.readImage(orphan), isNull);
    });

    test('絵を外すと、その絵も片づく', () async {
      final books = await openMemoryWordBooks();
      final id = await books.addImage(
        Uint8List.fromList([1]),
        fileName: 'a.png',
      );
      final book = await books.add(
        WordBook(
          id: '',
          name: 'え',
          words: [Word(text: 'ねこ', reading: 'ねこ', image: id)],
        ),
      );

      await books.save(
        book.copyWith(words: [book.words.single.withoutImage()]),
      );

      expect(await books.readImage(id), isNull);
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

