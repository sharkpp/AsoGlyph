import 'package:asoglyph/audio/speaker.dart';
import 'package:asoglyph/font/font_builder.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/kanjivg/stroke_order.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/store/passcode.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/store/session.dart';
import 'package:asoglyph/store/word_book_store.dart';
import 'package:asoglyph/ui/char_set_screen.dart';
import 'package:asoglyph/model/user.dart';
import 'package:asoglyph/ui/collection_screen.dart';
import 'package:asoglyph/ui/user_picker.dart';
import 'package:asoglyph/ui/writing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';
import '../support/recording_speaker.dart';

Sample _written(String char, {PracticeMode mode = PracticeMode.copy}) =>
    Sample.now(
      char: char,
      mode: mode,
      strokes: [
        Stroke(const [
          InkPoint(x: 300, y: 500, t: 0, pressure: 0),
          InkPoint(x: 700, y: 500, t: 20, pressure: 0),
        ]),
      ],
    );

/// 束ごとの字数。小書きを足してひらがなとカタカナで違う（カタカナは「ー」がある）。
final hiragana = CharSet.hiragana.chars.length;
final katakana = CharSet.katakana.chars.length;

void main() {
  late Session session;
  late SampleStore store;
  late Locks locks;
  late WordBookStore books;
  late StrokeOrderLibrary strokeOrders;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    strokeOrders = await StrokeOrderLibrary.load();
  });

  setUp(() async {
    session = await openMemorySession();
    store = session.samples;
    locks = await openMemoryLocks();
    books = await openMemoryWordBooks();
  });

  /// sembast はタイマを使う。テストの疑似非同期環境では完了しないため、
  /// 記録の読み書きは必ず [WidgetTester.runAsync] の中で行う。
  Future<void> collect(WidgetTester tester, String char) =>
      tester.runAsync(() => store.add(_written(char)));

  Future<void> pumpScreen(WidgetTester tester, {Speaker? speaker}) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionScreen(
          session: session,
          locks: locks,
          books: books,
          speaker: speaker ?? RecordingSpeaker(),
          strokeOrders: strokeOrders,
        ),
      ),
    );
  }

  /// 文字種の充足率。同じ字数の文字種があるので、必ず束ごとに読む。
  String countOf(WidgetTester tester, String label) => tester
      .widget<Text>(
        find.descendant(
          of: find.widgetWithText(CharSetRing, label),
          matching: find.textContaining('/'),
        ),
      )
      .data!;

  /// 文字種を開き、字をタップして入った書き取り画面。
  Future<WritingScreen> openWriting(
    WidgetTester tester,
    String label,
    String char,
  ) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CharTile, char));
    await tester.pumpAndSettle();
    return tester.widget<WritingScreen>(find.byType(WritingScreen));
  }

  testWidgets('文字種ごとに充足率を出す', (tester) async {
    await pumpScreen(tester);

    // 束の名前が全部見えていること。一覧はここから枝分かれする。
    for (final charSet in CharSet.values) {
      expect(find.text(charSet.label), findsOneWidget);
      expect(countOf(tester, charSet.label), '0 / ${charSet.chars.length}');
    }
  });

  testWidgets('字を集めると充足率が上がる', (tester) async {
    await collect(tester, 'あ');
    await pumpScreen(tester);

    expect(countOf(tester, 'ひらがな'), '1 / $hiragana');
    expect(countOf(tester, 'カタカナ'), '0 / $katakana', reason: '別の束は動かない');
  });

  testWidgets('なぞっただけでは充足率は動かない', (tester) async {
    await tester.runAsync(
      () => store.add(_written('あ', mode: PracticeMode.trace)),
    );
    await pumpScreen(tester);

    // なぞった字はその子の字とは言いにくい。混ぜるかは出力時に選ぶ（SPEC 7.1）。
    expect(countOf(tester, 'ひらがな'), '0 / $hiragana');
  });

  testWidgets('文字種を開くとその束の字が並ぶ', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('カタカナ'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(CharTile, 'ア'), findsOneWidget);
    expect(find.widgetWithText(CharTile, 'あ'), findsNothing, reason: '別の束は混ざらない');
  });

  testWidgets('字をタップするとその字の書き取りに入る', (tester) async {
    await pumpScreen(tester);

    expect((await openWriting(tester, 'ひらがな', 'か')).char, 'か');
  });

  testWidgets('既定はお手本を見て書く', (tester) async {
    await pumpScreen(tester);

    expect((await openWriting(tester, 'ひらがな', 'か')).mode, PracticeMode.copy);
  });

  testWidgets('じぶんでを選ぶと、その字は何も見ずに書く', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('じぶんで'));
    await tester.pumpAndSettle();

    expect((await openWriting(tester, 'ひらがな', 'か')).mode, PracticeMode.free);
  });

  testWidgets('なぞり書きも選べる', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('なぞる'));
    await tester.pumpAndSettle();

    expect((await openWriting(tester, 'ひらがな', 'か')).mode, PracticeMode.trace);
  });

  testWidgets('モードを選ぶと声でも伝える', (tester) async {
    final speaker = RecordingSpeaker();
    await pumpScreen(tester, speaker: speaker);

    await tester.tap(find.text('じぶんで'));
    await tester.pumpAndSettle();

    expect(speaker.spoken, ['じぶんで かいてみよう']);
  });

  testWidgets('集めない文字種は、子供の画面に出さない', (tester) async {
    await tester.runAsync(
      () => session.users.save(
        session.current.copyWith(collecting: {CharSet.hiragana}),
      ),
    );
    await pumpScreen(tester);

    expect(find.text('ひらがな'), findsOneWidget);
    expect(find.text('カタカナ'), findsNothing);
    expect(find.text('すうじ'), findsNothing);
  });

  testWidgets('1 人しかいないうちは、人の切り替えを出さない', (tester) async {
    await pumpScreen(tester);

    // 使いようのないボタンを子供向け画面に置かない（SPEC 9）。
    expect(find.byType(AvatarMark), findsNothing);
  });

  testWidgets('2 人いれば切り替えられ、字は混ざらない', (tester) async {
    await collect(tester, 'あ');
    await tester.runAsync(
      () => session.addUser(name: 'いもうと', avatar: Avatar.rabbit),
    );
    await pumpScreen(tester);

    // いま書いている人の印が出る。
    expect(find.byType(AvatarMark), findsOneWidget);
    expect(countOf(tester, 'ひらがな'), '0 / $hiragana', reason: 'いもうとの字はまだ無い');

    await tester.tap(find.byType(AvatarMark));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('じぶん'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(countOf(tester, 'ひらがな'), '1 / $hiragana', reason: 'じぶんの字は残っている');
  });

  testWidgets('切り替えにロックが掛かっていれば、選ばせる前に聞く', (tester) async {
    locks = await openMemoryLocks(switching: '1234');
    await tester.runAsync(
      () => session.addUser(name: 'いもうと', avatar: Avatar.rabbit),
    );
    await pumpScreen(tester);

    await tester.tap(find.byType(AvatarMark));
    await tester.pumpAndSettle();

    // 選ばせる前に聞く。選んでから断ると、押した印が使えないものだったのか
    // 間違えたのかが子供に分からない。
    expect(find.text('パスコード'), findsOneWidget);
    expect(find.text('だれが かく？'), findsNothing);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'あける'));
    await tester.pumpAndSettle();

    expect(find.text('だれが かく？'), findsOneWidget);
  });

  testWidgets('切り替えのロックを掛けていなければ、そのまま選べる', (tester) async {
    await tester.runAsync(
      () => session.addUser(name: 'いもうと', avatar: Avatar.rabbit),
    );
    await pumpScreen(tester);

    await tester.tap(find.byType(AvatarMark));
    await tester.pumpAndSettle();

    // 既定は無効（SPEC 7.5）。
    expect(find.text('パスコード'), findsNothing);
    expect(find.text('だれが かく？'), findsOneWidget);
  });

  testWidgets('KanjiVG のクレジットをアプリの中で読める', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    // SPEC 6.3 の要求。KanjiVG・作者・ライセンスの 3 つが要る。
    final notice = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(notice.data, contains('KanjiVG'));
    expect(notice.data, contains('Ulrich Apel'));
    expect(notice.data, contains('creativecommons.org/licenses/by-sa/3.0/'));
  });

  testWidgets('テスト用に集めた字をぜんぶ消せる', (tester) async {
    await collect(tester, 'あ');
    await pumpScreen(tester);
    expect(countOf(tester, 'ひらがな'), '1 / $hiragana');

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('集めた字をぜんぶ消す（テスト用）'));
    await tester.pumpAndSettle();

    // 取り消せないので、必ず一度たしかめる。
    expect(find.text('集めた字をぜんぶ消しますか？'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '消す'));
    });
    await tester.pumpAndSettle();

    expect(store.collectedChars(includeTraced: false), isEmpty);
    expect(countOf(tester, 'ひらがな'), '0 / $hiragana');
  });

  testWidgets('やめるを押したら消さない', (tester) async {
    await collect(tester, 'あ');
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('集めた字をぜんぶ消す（テスト用）'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'やめる'));
    await tester.pumpAndSettle();

    expect(store.collectedChars(includeTraced: false), ['あ']);
  });

  testWidgets('集めた字が無いうちはフォントを作らない', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();

    expect(find.text('まだ字がありません'), findsOneWidget);
    expect(find.text('TTF'), findsNothing, reason: '形式を聞くまでもない');
  });

  testWidgets('集めた字があれば出力形式を選べる', (tester) async {
    await collect(tester, 'あ');
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(find.text('TTF'), findsOneWidget);
    expect(find.text('OTF'), findsOneWidget);
  });

  testWidgets('なぞった字を混ぜるかを出力時に選べる', (tester) async {
    await collect(tester, 'あ');
    await tester.runAsync(
      () => store.add(_written('い', mode: PracticeMode.trace)),
    );
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    // 既定は混ぜない。なぞりは 1 字ぶん余分にある。
    expect(find.text('ほかに 1 字'), findsOneWidget);
    expect(find.text('1 字'), findsNWidgets(FontFormat.values.length));

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('2 字'), findsNWidgets(FontFormat.values.length));
  });

  testWidgets('なぞった字が無ければ混ぜる選択は出さない', (tester) async {
    await collect(tester, 'あ');
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(find.text('なぞっただけの字はありません'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
  });
}
