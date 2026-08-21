import 'dart:typed_data';

import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/user.dart';
import 'package:asoglyph/export/backup.dart';
import 'package:asoglyph/model/word.dart';
import 'package:asoglyph/store/word_attempt_store.dart';
import 'package:asoglyph/word/word_book_export.dart';
import 'package:asoglyph/store/bundled_assets.dart';
import 'package:asoglyph/store/word_book_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

Sample _written(String char) => Sample.now(
  char: char,
  mode: PracticeMode.copy,
  strokes: [
    Stroke(const [
      InkPoint(x: 300, y: 500, t: 0),
      InkPoint(x: 700, y: 500, t: 20),
    ]),
  ],
);

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

    test('作った人と概要は、開き直しても残る', () async {
      final db = await openMemoryDatabase();
      final books = await openMemoryWordBooks(db);
      final book = await books.add(
        const WordBook(
          id: '',
          name: 'うちのことば',
          words: [Word(text: 'ぱぱ', reading: 'ぱぱ')],
          author: 'おかあさん',
          description: '3 歳の下の子向け',
        ),
      );

      await books.save(book.withCredits(author: 'おとうさん'));
      final reopened = await openMemoryWordBooks(db);
      final saved = reopened[book.id]!;

      expect(saved.author, 'おとうさん');
      // 片方だけ書き替えたのではなく、書かなかったほうは消える。
      expect(saved.description, isNull);
    });

    test('内蔵の辞書は、資産に書いた作った人と概要を持つ', () async {
      final books = await openMemoryWordBooks();
      final book = books.all.firstWhere(
        (entry) => entry.name == 'ひらがなのことば',
      );

      expect(book.author, isNotEmpty);
      expect(book.description, isNotEmpty);
    });

    test('コピーは作った人と概要を持っていく', () async {
      final books = await openMemoryWordBooks();
      final book = books.all.firstWhere((entry) => entry.author != null);

      final copy = await books.copy(book, name: 'うちのひらがな');

      // 語はその人が選んだもの。コピーを作っただけで出どころは消えない。
      expect(copy.author, book.author);
      expect(copy.description, book.description);
    });

    test('並びは入れた順のまま。開き直しても変わらない', () async {
      final db = await openMemoryDatabase();
      final books = await openMemoryWordBooks(db);
      // 内蔵の辞書は起動時にまとめて入る。同じミリ秒に何冊も入るので、
      // 時刻だけでは並びが決まらない（UUID v7 も同じミリ秒の中では乱数）。
      final order = [for (final book in books.all) book.name];
      expect(order, hasLength(greaterThan(1)));

      for (var i = 0; i < 3; i++) {
        await books.add(
          WordBook(
            id: '',
            name: 'あとから $i',
            words: const [Word(text: 'ねこ', reading: 'ねこ')],
          ),
        );
      }
      final expected = [...order, 'あとから 0', 'あとから 1', 'あとから 2'];
      expect([for (final book in books.all) book.name], expected);

      final reopened = await openMemoryWordBooks(db);
      expect([for (final book in reopened.all) book.name], expected);
    });

    test('辞書を直したら、開き直したときに入れ替わる', () async {
      final db = await openMemoryDatabase();
      final assets = FakeBundledAssets({
        'assets/words/a.yaml': 'name: どうぶつ\n'
            'words:\n  - {text: ねこ, reading: ねこ}\n',
        'assets/words/b.yaml': 'name: たべもの\n'
            'words:\n  - {text: ぱん, reading: ぱん}\n',
      });
      final books = await WordBookStore.open(db, assets: assets);
      final before = books.all.first;
      expect(before.words.single.text, 'ねこ');

      // 辞書を直した。
      assets.files['assets/words/a.yaml'] =
          'name: どうぶつ\n'
          'words:\n  - {text: ねこ, reading: ねこ}\n'
          '  - {text: いぬ, reading: いぬ}\n';

      final reopened = await WordBookStore.open(db, assets: assets);
      final after = reopened.all.first;

      expect(after.words.map((word) => word.text), ['ねこ', 'いぬ']);
      // 誰にどれを出すかは id で覚えている。id が変わると割り振りが外れる。
      expect(after.id, before.id);
      expect(
        [for (final book in reopened.all) book.name],
        ['どうぶつ', 'たべもの'],
        reason: '並びも変わらない',
      );
    });

    test('辞書を直しても、内蔵のままでいる', () async {
      final db = await openMemoryDatabase();
      final assets = FakeBundledAssets({
        'assets/words/a.yaml': 'name: どうぶつ\n'
            'words:\n  - {text: ねこ, reading: ねこ}\n',
      });
      final books = await WordBookStore.open(db, assets: assets);
      final before = books.all.single;

      // 辞書を直した。
      assets.files['assets/words/a.yaml'] =
          'name: どうぶつ\n'
          'words:\n  - {text: ねこ, reading: ねこ}\n'
          '  - {text: いぬ, reading: いぬ}\n';
      await WordBookStore.open(db, assets: assets);

      // 入れ替えたぶんが内蔵でなくなると、次に開いたときに「割り振りの無い
      // 内蔵」と「同じ中身の自分の単語帳」の 2 冊になる。開くたびに増える。
      final reopened = await WordBookStore.open(db, assets: assets);

      expect(reopened.all.length, 1);
      expect(reopened.all.single.isBundled, isTrue);
      expect(reopened.all.single.id, before.id);
    });

    test('変えていない辞書は、開き直しても入れ直さない', () async {
      final db = await openMemoryDatabase();
      final bundle = await encodeWordBookBundle(
        const WordBook(
          id: 'b',
          name: 'どうぶつ',
          words: [Word(text: 'ねこ', reading: 'ねこ', image: 'cat.png')],
        ),
        (id) async => Uint8List.fromList([1, 2, 3]),
      );
      final assets = FakeBundledAssets({'assets/words/a.asodict': bundle});

      final first = await WordBookStore.open(db, assets: assets);
      final image = first.all.single.words.single.image;

      final second = await WordBookStore.open(db, assets: assets);

      // 開くたびに絵を入れ直すと、同じ絵が端末の中で増え続ける。
      expect(second.all.single.words.single.image, image);
      expect(await second.readImage(image!), [1, 2, 3]);
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

    test('控えから戻しても、内蔵の辞書は増えない', () async {
      // 端末ごとに（iPad では Safari とホーム画面のアプリでも、SPEC 10.1）
      // 置き場が別なので、内蔵の辞書は同じ資産でも別の id を持っている。
      // 控えは id ごと持ってくるため、素朴に重ねると 1 資産に 2 冊できる。
      final source = await openMemorySession();
      final target = await openMemorySession();
      final assets = [for (final book in source.books.all) book.source];

      await target.restoreFrom(await exportBackup(source.db));

      expect(
        [for (final book in target.books.all) book.source],
        assets,
        reason: '資産 1 つに対して辞書は 1 冊（SPEC 7.4.3）',
      );

      // 開き直しても増えない。
      final reopened = await openMemorySession(target.db);
      expect([for (final book in reopened.books.all) book.source], assets);
    });

    test('寄せるときは、割り振られている側を残す', () async {
      final source = await openMemorySession();
      final target = await openMemorySession();

      // 控えの側では、内蔵の辞書を 1 冊だけ使うようにしてある。
      final only = source.books.all.first;
      await source.users.save(source.current.copyWith(wordBooks: {only.id}));

      await target.restoreFrom(await exportBackup(source.db));

      // 割り振りは id で覚えている（SPEC 7.4.3）。残す側を間違えると、
      // 戻したのに単語帳が 1 冊も出ない人ができる。
      expect(target.current.wordBooks, {only.id});
      expect(target.books[only.id], isNotNull);
      expect(
        target.books.all.where((book) => target.current.uses(book.id)),
        hasLength(1),
      );
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
      expect(AppBundledAssets.isDebugAsset('assets/words/_ためし.yaml'), isTrue);
      expect(
        AppBundledAssets.isDebugAsset('assets/words/hiragana.yaml'),
        isFalse,
      );
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

    test('語ごとにまとめて、新しい順に並べる', () async {
      final store = await WordAttemptStore.open(
        await openMemoryDatabase(),
        userId: 'test-user',
      );
      await store.finish(word: 'ねこ', sampleIds: ['a']);
      await store.finish(word: 'いぬ', sampleIds: ['b']);
      await store.finish(word: 'ねこ', sampleIds: ['c']);

      final history = store.byWord;
      expect(history.map((entry) => entry.word), ['ねこ', 'いぬ']);
      expect(history.first.count, 2);
      expect(history.first.lastAt, store.all.last.finishedAt);
    });

    test('語ごとに記録を消せる。書いた字は消えない', () async {
      final session = await openMemorySession();
      await session.samples.add(_written('ね'));
      await session.attempts.finish(word: 'ねこ', sampleIds: ['a']);
      await session.attempts.finish(word: 'いぬ', sampleIds: ['b']);

      await session.attempts.removeWord('ねこ');

      // 消えるのは「書けた」という印だけ（SPEC 4.1 / 4.2）。
      expect(session.attempts.countOf('ねこ'), 0);
      expect(session.attempts.countOf('いぬ'), 1);
      expect(session.samples.collectedChars(includeTraced: false), {'ね'});
    });

    test('ぜんぶ消しても、ほかの人の記録は残る', () async {
      final session = await openMemorySession();
      await session.attempts.finish(word: 'ねこ', sampleIds: ['a']);
      await session.addUser(name: 'いもうと', avatar: Avatar.rabbit);
      await session.attempts.finish(word: 'いぬ', sampleIds: ['b']);

      await session.attempts.clear();
      expect(session.attempts.all, isEmpty);

      await session.switchTo(session.users.all.first.id);
      expect(session.attempts.countOf('ねこ'), 1);
    });

    test('消したことは開き直しても残る', () async {
      final db = await openMemoryDatabase();
      final store = await WordAttemptStore.open(db, userId: 'test-user');
      await store.finish(word: 'ねこ', sampleIds: ['a']);
      await store.clear();

      final reopened = await WordAttemptStore.open(db, userId: 'test-user');
      expect(reopened.all, isEmpty);
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
