import 'dart:convert';
import 'dart:typed_data';

import 'package:asoglyph/model/word.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:asoglyph/store/session.dart';
import 'package:asoglyph/store/word_book_store.dart';
import 'package:asoglyph/ui/word_book_editor.dart';
import 'package:asoglyph/ui/word_image_view.dart';
import 'package:asoglyph/word/word_book_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

/// 1 画素の PNG。中身は問わないが、`Image.memory` が読める必要がある。
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM'
  'IQAAAABJRU5ErkJggg==',
);

void main() {
  late Session session;
  late WordBookStore books;

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() async {
    session = await openMemorySession();
    books = session.books;
  });

  Future<WordBook> makeBook({String? image}) => books.add(
    WordBook(
      id: '',
      name: 'どうぶつ',
      words: [Word(text: 'ねこ', reading: 'ねこ', image: image)],
    ),
  );

  Future<void> pumpEditor(WidgetTester tester, WordBook book) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: WordBookEditor(book: book, books: books)),
    );
  }

  testWidgets('ことばを直すと、その場で保存する', (tester) async {
    final book = await tester.runAsync(makeBook) as WordBook;
    await pumpEditor(tester, book);

    // 見出しと読みの両方に「ねこ」が出る。行そのものを押す。
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'ことば'), 'いぬ');
    await tester.runAsync(() async {
      await tester.tap(find.text('決める'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    // 「保存」ボタンは置かない。押し忘れで語が消える導線を作らない。
    expect(books.all.last.words.single.text, 'いぬ');
    expect(books.all.last.words.single.reading, 'ねこ', reason: '読みは残る');
  });

  testWidgets('絵のある語は、絵つきで並ぶ', (tester) async {
    final image = await tester.runAsync(
      () => books.addImage(_png, fileName: 'cat.png'),
    );
    final book = await tester.runAsync(() => makeBook(image: image)) as WordBook;
    await pumpEditor(tester, book);
    await tester.pumpAndSettle();

    expect(find.byType(WordImageView), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('絵を外すと、語から名前が消える', (tester) async {
    final image = await tester.runAsync(
      () => books.addImage(_png, fileName: 'cat.png'),
    );
    final book = await tester.runAsync(() => makeBook(image: image)) as WordBook;
    await pumpEditor(tester, book);

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('絵を外す'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('決める'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(books.all.last.words.single.image, isNull);
    // 指されなくなった絵は片づく。
    expect(await tester.runAsync(() => books.readImage(image!)), isNull);
  });

  testWidgets('書き出す形を選ばせる', (tester) async {
    final book = await tester.runAsync(makeBook) as WordBook;
    await pumpEditor(tester, book);

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    // 使い道で変わる。人に渡すなら絵ごと、自分で直すなら YAML。
    expect(find.text('単語帳ファイル（.asodict）'), findsOneWidget);
    expect(find.text('YAML'), findsOneWidget);
  });

  testWidgets('絵は落として入れることもできる', (tester) async {
    final book = await tester.runAsync(makeBook) as WordBook;
    await pumpEditor(tester, book);

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    // 選ぶ画面を開いて探し直すより、そのまま落とせるほうが早い。
    expect(find.byType(DropTarget), findsOneWidget);
    expect(find.textContaining('ここに絵を落としても入ります'), findsOneWidget);
  });

  testWidgets('かっこの中は薄く出す', (tester) async {
    final book = await tester.runAsync(
      () => books.add(
        const WordBook(
          id: '',
          name: 'ヒーロー',
          words: [Word(text: '[ウルトラマン]オメガ', reading: 'うるとらまんおめが')],
        ),
      ),
    ) as WordBook;
    await pumpEditor(tester, book);

    // どこを書かせるのかが、親にもひと目で分かるようにする。
    // 行の見出しは 1 つめの Text（2 つめは読み）。
    final title = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(ListTile).first,
            matching: find.byType(Text),
          )
          .first,
    );
    final spans = (title.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((span) => span.text), ['ウルトラマン', 'オメガ']);
    expect(spans.first.style!.color, const Color(0xff9c948a));
    expect(spans.last.style!.color, isNull, reason: '書かせるところは地の色');
  });

  testWidgets('ぜんぶ かっこの中の語は決められない', (tester) async {
    final book = await tester.runAsync(makeBook) as WordBook;
    await pumpEditor(tester, book);

    await tester.tap(find.text('ことばを足す'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'ことば'), '[ぜんぶ]');
    await tester.pump();

    expect(find.textContaining('書かせる字がありません'), findsOneWidget);
    await tester.tap(find.text('決める'));
    await tester.pumpAndSettle();

    // 書かせる字が 1 つも無い語は、練習に出しようがない。
    expect(
      find.widgetWithText(AlertDialog, 'ことばを足す'),
      findsOneWidget,
      reason: '閉じない',
    );
    expect(books.all.last.words, hasLength(1));
  });

  test('書き出した単語帳ファイルを、絵ごと戻せる', () async {
    final image = await books.addImage(_png, fileName: 'cat.png');
    final book = await makeBook(image: image);

    final bytes = await encodeWordBookBundle(book, books.readImage);
    final bundle = parseWordBookBundle(
      Uint8List.fromList(bytes),
      name: 'どうぶつ',
    );

    expect(bundle.book.name, 'どうぶつ');
    expect(bundle.images[image], _png, reason: '絵の中身がそのまま入っている');
    expect(bundle.book.words.single.image, image);
  });
}
