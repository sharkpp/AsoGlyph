import 'package:asoglyph/ink/ink_canvas.dart';
import 'package:asoglyph/ink/ink_controller.dart';
import 'package:asoglyph/kanjivg/stroke_order.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/ui/glyph_preview.dart';
import 'package:asoglyph/ui/stroke_order_view.dart';
import 'package:asoglyph/ui/writing_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';
import '../support/recording_speaker.dart';

void main() {
  group('InkController', () {
    test('画を書き終えると確定する', () {
      final controller = InkController();
      expect(controller.isEmpty, isTrue);

      controller.begin(100, 100, 0);
      expect(controller.activeStroke, isNotNull);
      expect(controller.strokes, isEmpty);

      controller.extend(200, 200, 0);
      controller.end();
      expect(controller.strokes, hasLength(1));
      expect(controller.strokes.first.points, hasLength(2));
      expect(controller.activeStroke, isNull);
    });

    test('もどすは描画中の画を先に取り消す', () {
      final controller = InkController()
        ..begin(0, 0, 0)
        ..end()
        ..begin(50, 50, 0);

      controller.undo();
      expect(controller.activeStroke, isNull);
      expect(controller.strokes, hasLength(1), reason: '確定済みは残る');

      controller.undo();
      expect(controller.strokes, isEmpty);
    });

    test('経過時間が記録される', () {
      final controller = InkController()..begin(0, 0, 0);
      controller
        ..extend(10, 10, 0)
        ..end();
      expect(controller.strokes.first.points.first.t, 0);
    });
  });

  group('WritingScreen', () {
    late SampleStore store;
    late RecordingSpeaker speaker;
    late StrokeOrderLibrary strokeOrders;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      strokeOrders = await StrokeOrderLibrary.load();
    });

    setUp(() async {
      store = await openMemoryStore();
      speaker = RecordingSpeaker();
    });

    Future<void> pumpScreen(
      WidgetTester tester, {
      String char = 'あ',
      PracticeMode mode = PracticeMode.copy,
      bool withStrokeOrder = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WritingScreen(
            char: char,
            mode: mode,
            store: store,
            speaker: speaker,
            strokeOrder: withStrokeOrder ? strokeOrders[char] : null,
          ),
        ),
      );
    }

    testWidgets('お手本が出て、書き上げるとフォントの字に入れ替わる', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(StrokeOrderView), findsOneWidget, reason: 'お手本');
      expect(find.byType(GlyphPreview), findsNothing);

      await _drawLine(tester);
      await tester.pump();
      await _tapDone(tester);

      expect(find.byType(StrokeOrderView), findsNothing, reason: 'お手本が字形に置き換わる');
      final preview = tester.widget<GlyphPreview>(find.byType(GlyphPreview));
      expect(preview.contours, isNotEmpty, reason: '輪郭が起こせていない');
    });

    testWidgets('お手本は書き順どおりに引かれる', (tester) async {
      await pumpScreen(tester);
      final view = tester.widget<StrokeOrderView>(find.byType(StrokeOrderView));

      expect(view.order.strokeCount, 3, reason: 'あ は 3 画');
      expect(view.progress.value, 0, reason: '開いた直後は 1 画目の書き始め');

      await tester.pump(StrokeOrderView.perStroke);
      expect(view.progress.value, closeTo(1 / 3, 0.05), reason: '1 画ぶん進む');

      await tester.pumpAndSettle();
      expect(view.progress.value, 1, reason: '最後まで引き終わる');
    });

    testWidgets('お手本を押すと書き順を引き直す', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      final view = tester.widget<StrokeOrderView>(find.byType(StrokeOrderView));
      expect(view.progress.value, 1);

      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();

      expect(view.progress.value, 0, reason: '頭から引き直す');
    });

    testWidgets('書き順を持たない字はシステムの字で見せる', (tester) async {
      await pumpScreen(tester, withStrokeOrder: false);

      expect(find.byType(StrokeOrderView), findsNothing);
      expect(find.text('あ'), findsOneWidget);
    });

    testWidgets('できた！を押した時点で記録される', (tester) async {
      await pumpScreen(tester, char: 'き');
      await _drawLine(tester);
      await _tapDone(tester);

      expect(store.attemptCount('き'), 1);
      expect(store.latestMaterialId('き'), isNotNull);

      // sembast はタイマを使う。疑似非同期環境では完了しないため実時間で読む。
      late Sample sample;
      await tester.runAsync(
        () async => sample = await store.read(store.latestMaterialId('き')!),
      );
      expect(sample.strokes, hasLength(1));
      expect(sample.strokes.single.points.length, greaterThan(2));
    });

    testWidgets('もういちど書いても前の記録は消えない', (tester) async {
      await pumpScreen(tester);
      await _drawLine(tester);
      await _tapDone(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'もういちど'));
      await tester.pump();
      expect(find.byType(GlyphPreview), findsNothing, reason: '古い字形を残さない');

      await _drawLine(tester);
      await _tapDone(tester);
      expect(store.attemptCount('あ'), 2, reason: '記録は追記のみ');
    });

    testWidgets('何も書いていないうちは操作できない', (tester) async {
      await pumpScreen(tester);

      for (final icon in [Icons.undo, Icons.delete_outline]) {
        final button = find.widgetWithIcon(OutlinedButton, icon);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      }
      final done = find.widgetWithText(FilledButton, 'できた！');
      expect(tester.widget<FilledButton>(done).onPressed, isNull);
    });

    testWidgets('画面を開いた時点で何を書くかを読み上げる', (tester) async {
      await pumpScreen(tester, char: '3');

      expect(speaker.spoken, ['さん、かいてね'], reason: '数字は読みで言う');
    });

    testWidgets('お手本を押すともう一度読み上げる', (tester) async {
      await pumpScreen(tester);
      speaker.spoken.clear();

      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();

      expect(speaker.spoken, ['あ、かいてね']);
    });

    testWidgets('書き上げるとほめて、読み上げの導線を閉じる', (tester) async {
      await pumpScreen(tester);
      speaker.spoken.clear();

      await _drawLine(tester);
      await _tapDone(tester);

      expect(speaker.spoken, ['できたね！']);
      expect(
        find.byIcon(Icons.volume_up),
        findsNothing,
        reason: '字形が出たあとはお手本を押しても何も起きない',
      );
    });

    testWidgets('もういちどで書き直すとき、また読み上げる', (tester) async {
      await pumpScreen(tester);
      await _drawLine(tester);
      await _tapDone(tester);
      speaker.spoken.clear();

      await tester.tap(find.widgetWithText(OutlinedButton, 'もういちど'));
      await tester.pump();

      expect(speaker.spoken, ['あ、かいてね']);
    });

    testWidgets('画面を出るときは読み上げを止める', (tester) async {
      await pumpScreen(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      expect(speaker.stopped, 1);
    });

    testWidgets('何も見ずに書くモードでは字を出さない', (tester) async {
      await pumpScreen(tester, mode: PracticeMode.free);

      expect(find.byType(StrokeOrderView), findsNothing, reason: '書き順も見せない');
      expect(find.text('あ'), findsNothing, reason: 'お手本を出しては意味がない');
      expect(speaker.spoken, ['あ、かいてね'], reason: '頼れるのは音だけ');

      await _drawLine(tester);
      await _tapDone(tester);

      // 書き上げたあとの字形は、お手本ではなく結果なので出してよい。
      expect(find.byType(GlyphPreview), findsOneWidget);
    });

    testWidgets('書いたときのモードがそのまま記録される', (tester) async {
      await pumpScreen(tester, char: 'き', mode: PracticeMode.free);
      await _drawLine(tester);
      await _tapDone(tester);

      late Sample sample;
      await tester.runAsync(
        () async => sample = await store.read(store.latestMaterialId('き')!),
      );
      expect(sample.mode, PracticeMode.free);
    });

    testWidgets('なぞり書きでは字形を薄く敷く', (tester) async {
      await pumpScreen(tester, mode: PracticeMode.trace);

      // 枠のお手本と、なぞる下敷きの 2 つ。
      final views = tester.widgetList<StrokeOrderView>(
        find.byType(StrokeOrderView),
      );
      expect(views, hasLength(2));

      final guide = views.last;
      expect(guide.progress.value, 1, reason: '全部見えていないとなぞれない');
      expect(guide.color, isNot(views.first.color), reason: '下敷きは薄い色');
    });

    testWidgets('なぞり書きはフォントの素材にしない', (tester) async {
      await pumpScreen(tester, char: 'き', mode: PracticeMode.trace);
      await _drawLine(tester);
      await _tapDone(tester);

      expect(store.attemptCount('き'), 1, reason: '書いた事実は残す');
      expect(
        store.latestMaterialId('き'),
        isNull,
        reason: 'なぞっただけの字はフォントに入れない',
      );
    });

    testWidgets('スタイラス使用中はタッチを無視する', (tester) async {
      await pumpScreen(tester);
      final center = tester.getCenter(find.byType(InkCanvas));

      final stylus = await tester.startGesture(
        center,
        kind: PointerDeviceKind.stylus,
      );
      await stylus.moveBy(const Offset(40, 0));
      await tester.pump();

      // 手のひらが触れても新しい画は始まらない。
      final palm = await tester.startGesture(
        center + const Offset(0, 80),
        kind: PointerDeviceKind.touch,
      );
      await palm.moveBy(const Offset(40, 0));
      await palm.up();
      await stylus.up();
      await tester.pump();

      final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
      expect(canvas.controller.strokes, hasLength(1), reason: 'スタイラスの 1 画だけ');
    });
  });
}

/// 「できた！」を押して字形が出るまで待つ。
///
/// ラスタ化と記録は `Picture.toImage()` や sembast を通る実時間の非同期処理で、
/// ウィジェットテストの疑似非同期環境では [WidgetTester.runAsync] の中でしか
/// 進まない。所要時間は実行環境で変わるため、決め打ちで待たずに結果を待つ。
Future<void> _tapDone(WidgetTester tester) async {
  await tester.runAsync(
    () => tester.tap(find.widgetWithText(FilledButton, 'できた！')),
  );

  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(GlyphPreview).evaluate().isNotEmpty) return;
  }
  fail('字形が出ない');
}

/// キャンバスの中央を横切る線を引く。
Future<void> _drawLine(WidgetTester tester) async {
  final canvas = find.byType(InkCanvas);
  final rect = tester.getRect(canvas);
  final gesture = await tester.startGesture(
    Offset(rect.left + rect.width * 0.25, rect.center.dy),
  );
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(
      Offset(rect.left + rect.width * (0.25 + 0.05 * i), rect.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
}
