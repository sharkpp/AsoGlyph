import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/kanjivg/stroke_order.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/ui/char_set_screen.dart';
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
  Future<void> collect(WidgetTester tester, Sample sample) =>
      tester.runAsync(() => store.add(sample));

  /// 一覧のタイル。輪の中にも代表の字が出るので、必ずタイルに絞って探す。
  Finder tile(String char) => find.widgetWithText(CharTile, char);

  Future<void> pumpScreen(
    WidgetTester tester, {
    CharSet charSet = CharSet.hiragana,
    PracticeMode mode = PracticeMode.copy,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CharSetScreen(
          charSet: charSet,
          store: store,
          speaker: RecordingSpeaker(),
          strokeOrders: strokeOrders,
          mode: mode,
        ),
      ),
    );
  }

  testWidgets('その文字種の字がすべて並ぶ', (tester) async {
    await pumpScreen(tester, charSet: CharSet.katakana);

    // 清音 46 ＋ 濁音・半濁音 25 ＋ 小書き 9 ＋ 長音符。束は分けない。
    expect(find.byType(CharTile), findsNWidgets(81));
    expect(tile('ア'), findsOneWidget);
    expect(tile('ン'), findsOneWidget);
    expect(tile('ポ'), findsOneWidget);
    expect(tile('ャ'), findsOneWidget);
    expect(tile('ー'), findsOneWidget);
  });

  testWidgets('集めた字に星が付く', (tester) async {
    await collect(tester, _written('あ'));
    await pumpScreen(tester);

    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byIcon(Icons.gesture), findsNothing);
  });

  testWidgets('なぞっただけの字は、集めた字とは別の印になる', (tester) async {
    await collect(tester, _written('あ', mode: PracticeMode.trace));
    await pumpScreen(tester);

    // 充足率は動かない。混ぜるかは出力時に選ぶ（SPEC 7.1）。
    expect(find.byIcon(Icons.star), findsNothing);
    // それでも書いた事実は見えるようにする。
    expect(find.byIcon(Icons.gesture), findsOneWidget);
  });

  testWidgets('字をタップすると、選んだモードでその字の書き取りに入る', (tester) async {
    await pumpScreen(tester, mode: PracticeMode.free);

    await tester.tap(tile('き'));
    await tester.pumpAndSettle();

    final screen = tester.widget<WritingScreen>(find.byType(WritingScreen));
    expect(screen.chars, ['き']);
    expect(screen.mode, PracticeMode.free);
  });

  testWidgets('カタカナにも書き順のデータがある', (tester) async {
    await pumpScreen(tester, charSet: CharSet.katakana);

    await tester.tap(tile('ア'));
    await tester.pumpAndSettle();

    // お手本を出せない字があると、その字だけ練習の質が落ちる（SPEC 6.1）。
    final screen = tester.widget<WritingScreen>(find.byType(WritingScreen));
    expect(screen.strokeOrders[screen.chars.single], isNotNull);
  });
}
