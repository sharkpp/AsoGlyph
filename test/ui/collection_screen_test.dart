import 'package:asoglyph/audio/speaker.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/kanjivg/stroke_order.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/ui/collection_screen.dart';
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

void main() {
  late SampleStore store;
  late StrokeOrderLibrary strokeOrders;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    strokeOrders = await StrokeOrderLibrary.load();
  });

  setUp(() async {
    store = await openMemoryStore();
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
          store: store,
          speaker: speaker ?? RecordingSpeaker(),
          strokeOrders: strokeOrders,
        ),
      ),
    );
  }

  /// 字をタップして入った書き取り画面。
  Future<WritingScreen> openWriting(WidgetTester tester, String char) async {
    await tester.tap(find.text(char));
    await tester.pumpAndSettle();
    return tester.widget<WritingScreen>(find.byType(WritingScreen));
  }

  testWidgets('文字種ごとに充足率を出す', (tester) async {
    await pumpScreen(tester);

    expect(find.text('ひらがな'), findsOneWidget);
    expect(find.text('すうじ'), findsOneWidget);
    expect(
      find.text('0 / ${CharSet.hiraganaBasic.chars.length}'),
      findsOneWidget,
    );
    expect(find.text('0 / ${CharSet.digits.chars.length}'), findsOneWidget);
  });

  testWidgets('字を集めると充足率が上がる', (tester) async {
    await collect(tester, 'あ');
    await pumpScreen(tester);

    expect(
      find.text('1 / ${CharSet.hiraganaBasic.chars.length}'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.star), findsOneWidget, reason: '集めた字に印が付く');
  });

  testWidgets('なぞっただけの字は、集めた字とは別の印になる', (tester) async {
    await tester.runAsync(
      () => store.add(_written('あ', mode: PracticeMode.trace)),
    );
    await pumpScreen(tester);

    // 充足率は動かない。なぞった字はフォントに入らない（SPEC 7.1）。
    expect(
      find.text('0 / ${CharSet.hiraganaBasic.chars.length}'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.star), findsNothing);
    // それでも書いた事実は見えるようにする。
    expect(find.byIcon(Icons.gesture), findsWidgets);
  });

  testWidgets('字をタップするとその字の書き取りに入る', (tester) async {
    await pumpScreen(tester);

    expect((await openWriting(tester, 'か')).char, 'か');
  });

  testWidgets('既定はお手本を見て書く', (tester) async {
    await pumpScreen(tester);

    expect((await openWriting(tester, 'か')).mode, PracticeMode.copy);
  });

  testWidgets('じぶんでを選ぶと、その字は何も見ずに書く', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('じぶんで'));
    await tester.pumpAndSettle();

    expect((await openWriting(tester, 'か')).mode, PracticeMode.free);
  });

  testWidgets('なぞり書きも選べる', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('なぞる'));
    await tester.pumpAndSettle();

    expect((await openWriting(tester, 'か')).mode, PracticeMode.trace);
  });

  testWidgets('モードを選ぶと声でも伝える', (tester) async {
    final speaker = RecordingSpeaker();
    await pumpScreen(tester, speaker: speaker);

    await tester.tap(find.text('じぶんで'));
    await tester.pumpAndSettle();

    expect(speaker.spoken, ['じぶんで かいてみよう']);
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
    expect(find.byIcon(Icons.star), findsOneWidget);

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

    expect(store.collectedChars, isEmpty);
    expect(find.byIcon(Icons.star), findsNothing);
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

    expect(store.collectedChars, ['あ']);
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
}
