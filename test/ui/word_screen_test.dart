import 'dart:convert';

import 'package:asoglyph/kanjivg/stroke_order.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/word.dart';
import 'package:asoglyph/store/session.dart';
import 'package:asoglyph/ui/word_image_view.dart';
import 'package:asoglyph/ui/word_screen.dart';
import 'package:asoglyph/ui/writing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';
import '../support/recording_speaker.dart';
import '../support/writing_actions.dart';

void main() {
  late Session session;
  late RecordingSpeaker speaker;
  late StrokeOrderLibrary strokeOrders;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    strokeOrders = await StrokeOrderLibrary.load();
  });

  setUp(() async {
    session = await openMemorySession();
    speaker = RecordingSpeaker();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    PracticeMode mode = PracticeMode.copy,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: WordScreen(
          session: session,
          speaker: speaker,
          strokeOrders: strokeOrders,
          mode: mode,
        ),
      ),
    );
  }

  /// 集める文字種を絞る。
  Future<void> collectOnly(WidgetTester tester, Set<CharSet> sets) =>
      tester.runAsync(
        () => session.users.save(session.current.copyWith(collecting: sets)),
      );

  testWidgets('同梱の単語帳が並ぶ', (tester) async {
    await pumpScreen(tester);

    expect(find.text('ひらがなのことば'), findsOneWidget);
    expect(find.text('ねこ'), findsOneWidget);
  });

  testWidgets('集める文字種で書けない語は出さない', (tester) async {
    await collectOnly(tester, {CharSet.hiragana});
    await pumpScreen(tester);

    // 書けない字が 1 つでも混じると、その語は最後まで書けない（SPEC 7.4）。
    expect(find.text('ねこ'), findsOneWidget);
    expect(find.text('カタカナのことば'), findsNothing);
    expect(find.text('バス'), findsNothing);
  });

  testWidgets('書ける語が 1 つも無ければ、そのことを言う', (tester) async {
    // どの単語帳もこの人には割り振られていない状態にする。
    await tester.runAsync(
      () => session.users.save(session.current.copyWith(wordBooks: {'none'})),
    );
    await pumpScreen(tester);

    expect(find.textContaining('書ける語がありません'), findsOneWidget);
  });

  testWidgets('この人に割り振られた単語帳だけを出す', (tester) async {
    final hiragana = session.books.all
        .firstWhere((book) => book.name == 'ひらがなのことば')
        .id;
    await tester.runAsync(
      () => session.users.save(
        session.current.copyWith(wordBooks: {hiragana}),
      ),
    );
    await pumpScreen(tester);

    // 上の子には漢字入りの語、下の子にはひらがなの語、という使い分け（SPEC 7.4）。
    expect(find.text('ひらがなのことば'), findsOneWidget);
    expect(find.text('カタカナのことば'), findsNothing);
  });

  testWidgets('語を書くと、1 字ずつ書かせて履歴に残る', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('ねこ'));
    await tester.pumpAndSettle();

    // いま何字めかが見えている。3 字めまで書いたのに何の語か分からない、
    // という状態を作らない（SPEC 7.4）。
    final first = tester.widget<WritingScreen>(find.byType(WritingScreen));
    expect(first.char, 'ね');
    expect(first.steps!.index, 0);
    expect(first.steps!.isLast, isFalse);
    expect(speaker.spoken.last, contains('ねこ の ね'));

    await drawLine(tester);
    await tester.pump();
    await tapDone(tester);

    // まだ続きがあるので「つぎ」。
    expect(find.widgetWithText(FilledButton, 'つぎ'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'つぎ'));
    await tester.pumpAndSettle();

    final second = tester.widget<WritingScreen>(find.byType(WritingScreen));
    expect(second.char, 'こ');
    expect(second.steps!.isLast, isTrue);

    await drawLine(tester);
    await tester.pump();
    await tapDone(tester);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'おわり'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    // 単語トライアルとして残る（SPEC 4.2）。書いた記録そのものは 1 字ずつ入る。
    expect(session.attempts.countOf('ねこ'), 1);
    expect(session.attempts.all.single.sampleIds, hasLength(2));
    expect(session.samples.collectedChars(includeTraced: false), {'ね', 'こ'});
    expect(find.text('ねこ'), findsOneWidget, reason: '一覧に戻る');
  });

  testWidgets('途中でやめたら、単語トライアルは残らない', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('ねこ'));
    await tester.pumpAndSettle();
    await drawLine(tester);
    await tester.pump();
    await tapDone(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'つぎ'));
    await tester.pumpAndSettle();

    // 2 字めを書かずに閉じる。
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(session.attempts.all, isEmpty);
    // 書いた字は残る。記録は追記のみで消さない（SPEC 4.1）。
    expect(session.samples.collectedChars(includeTraced: false), {'ね'});
  });

  testWidgets('何も見ずに書くモードでは、まだ書いていない字を伏せる', (tester) async {
    await pumpScreen(tester, mode: PracticeMode.free);

    await tester.tap(find.text('ねこ'));
    await tester.pumpAndSettle();

    // 字が出ていると、音を頼りに書くという前提が崩れる（SPEC 7.1）。
    expect(find.text('？'), findsNWidgets(2));
    expect(find.text('ね'), findsNothing);
  });

  testWidgets('書き終えた語には印が付く', (tester) async {
    await tester.runAsync(
      () => session.attempts.finish(word: 'ねこ', sampleIds: ['a', 'b']),
    );
    await pumpScreen(tester);

    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('ねこ'),
          matching: find.byType(InkWell),
        ),
        matching: find.byIcon(Icons.star),
      ),
      findsOneWidget,
    );
  });

  testWidgets('絵のある語は、絵つきで並ぶ', (tester) async {
    await tester.runAsync(() async {
      final image = await session.books.addImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
          'hKmMIQAAAABJRU5ErkJggg==',
        ),
        fileName: 'cat.png',
      );
      final book = await session.books.add(
        WordBook(
          id: '',
          name: 'えのあることば',
          words: [Word(text: 'ねこ', reading: 'ねこ', image: image)],
        ),
      );
      // ほかの単語帳を出さないようにして、この語だけを並べる。
      await session.users.save(
        session.current.copyWith(wordBooks: {book.id}),
      );
    });
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    // 字が読めない子は、絵でしか語を選べない（SPEC 7.4）。
    expect(find.byType(WordImageView), findsOneWidget);
  });

  testWidgets('かっこの中は出しておくだけで、書かせない', (tester) async {
    await tester.runAsync(() async {
      final hero = await session.books.add(
        const WordBook(
          id: '',
          name: 'ヒーロー',
          words: [
            Word(text: '[ウルトラマン]オメガ', reading: 'うるとらまんおめが'),
          ],
        ),
      );
      // ほかの単語帳を出さないようにして、この語だけを並べる。
      await session.users.save(
        session.current.copyWith(wordBooks: {hero.id}),
      );
    });
    await collectOnly(tester, {CharSet.katakana});
    await pumpScreen(tester);

    await tester.tap(find.text('ウルトラマンオメガ'));
    await tester.pumpAndSettle();

    // 長い名前ぜんぶを書かせると 1 セッションで終わらない（SPEC 7.4）。
    final screen = tester.widget<WritingScreen>(find.byType(WritingScreen));
    expect(screen.char, 'オ', reason: 'ウルトラマン は書かせない');
    expect(screen.steps!.chars, hasLength(9), reason: '並びからは外さない');
    expect(screen.steps!.given, {0, 1, 2, 3, 4, 5});
    expect(screen.steps!.index, 6);
    expect(screen.steps!.isLast, isFalse);

    // 出しておく字も画面に出る。何の語を書いているのかが分からなくなる。
    expect(find.text('ウ'), findsOneWidget);
    expect(find.text('マ'), findsOneWidget);
  });

  test('書けない字を含む語は出題候補から外れる', () {
    const word = Word(text: 'ねこ', reading: 'ねこ');

    expect(word.isWritable({'ね', 'こ'}), isTrue);
    expect(word.isWritable({'ね'}), isFalse);
    expect(word.chars, ['ね', 'こ']);
  });
}
