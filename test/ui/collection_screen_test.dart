import 'package:asoglyph/audio/speaker.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/ui/collection_screen.dart';
import 'package:asoglyph/ui/writing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';
import '../support/recording_speaker.dart';

Sample _written(String char) => Sample.now(
  char: char,
  mode: PracticeMode.copy,
  strokes: [
    Stroke(const [
      InkPoint(x: 300, y: 500, t: 0, pressure: 0),
      InkPoint(x: 700, y: 500, t: 20, pressure: 0),
    ]),
  ],
);

void main() {
  late SampleStore store;

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
    expect(find.text('0 / ${CharSet.hiraganaBasic.chars.length}'), findsOneWidget);
    expect(find.text('0 / ${CharSet.digits.chars.length}'), findsOneWidget);
  });

  testWidgets('字を集めると充足率が上がる', (tester) async {
    await collect(tester, 'あ');
    await pumpScreen(tester);

    expect(find.text('1 / ${CharSet.hiraganaBasic.chars.length}'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget, reason: '集めた字に印が付く');
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

  testWidgets('モードを選ぶと声でも伝える', (tester) async {
    final speaker = RecordingSpeaker();
    await pumpScreen(tester, speaker: speaker);

    await tester.tap(find.text('じぶんで'));
    await tester.pumpAndSettle();

    expect(speaker.spoken, ['じぶんで かいてみよう']);
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
