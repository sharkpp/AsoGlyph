import 'package:asoglyph/ink/ink_canvas.dart';
import 'package:asoglyph/ink/ink_controller.dart';
import 'package:asoglyph/kanjivg/stroke_order.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/ui/glyph_preview.dart';
import 'package:asoglyph/ui/stroke_order_view.dart';
import 'package:asoglyph/ui/writing_guide.dart';
import 'package:asoglyph/ui/writing_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';
import '../support/writing_actions.dart';
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
      bool traceErases = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WritingScreen(
            chars: [char],
            mode: mode,
            traceErases: traceErases,
            store: store,
            speaker: speaker,
            strokeOrders: strokeOrders,
          ),
        ),
      );
    }

    testWidgets('小書きの字は、書き取り枠を小さくして書かせる', (tester) async {
      await pumpScreen(tester, char: 'ゃ');

      // 書き取り面もお手本も、同じ小さい枠にする。書いた大きさがそのまま
      // フォントの字形になるので、枠だけが大きさを決めている（SPEC 5.3）。
      final guides = tester
          .widgetList<WritingGuide>(find.byType(WritingGuide))
          .toList();
      expect(guides, hasLength(2));
      expect(guides.every((guide) => guide.small), isTrue);
    });

    testWidgets('大きい字は枠いっぱいに書かせる', (tester) async {
      await pumpScreen(tester, char: 'や');

      final guides = tester.widgetList<WritingGuide>(
        find.byType(WritingGuide),
      );
      expect(guides.any((guide) => guide.small), isFalse);
    });

    testWidgets('長音符は小さくしない', (tester) async {
      // 「ー」は全角の幅いっぱいに引く字（SPEC 5.3）。
      await pumpScreen(tester, char: 'ー');

      final guides = tester.widgetList<WritingGuide>(
        find.byType(WritingGuide),
      );
      expect(guides.any((guide) => guide.small), isFalse);
    });

    testWidgets('お手本が出て、書き上げるとフォントの字に入れ替わる', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(StrokeOrderView), findsOneWidget, reason: 'お手本');
      expect(find.byType(GlyphPreview), findsNothing);

      await drawLine(tester);
      await tester.pump();
      await tapDone(tester);

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

    testWidgets('引き終わったら画の番号に引き継ぐ', (tester) async {
      await pumpScreen(tester);
      final view = tester.widget<StrokeOrderView>(find.byType(StrokeOrderView));

      expect(view.showNumbers, isTrue);
      expect(view.progress.value, 0, reason: '動いているあいだは順番が目で追える');

      await tester.pumpAndSettle();
      expect(view.progress.value, 1, reason: '止まった字は番号でしか順番が分からない');
    });

    testWidgets('なぞる下敷きには番号を出さない', (tester) async {
      await pumpScreen(tester, mode: PracticeMode.trace);

      final views = tester
          .widgetList<StrokeOrderView>(find.byType(StrokeOrderView))
          .toList();
      // 書き取り面に番号を出すと、幼児がそれごとなぞってしまう。
      expect(views.last.showNumbers, isFalse);
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
      // 「」？ は KanjiVG に無い（SPEC 6.1）。
      await pumpScreen(tester, char: '？');

      expect(strokeOrders['？'], isNull);
      expect(find.byType(StrokeOrderView), findsNothing);
      expect(find.text('？'), findsOneWidget);
    });

    testWidgets('できた！を押した時点で記録される', (tester) async {
      await pumpScreen(tester, char: 'き');
      await drawLine(tester);
      await tapDone(tester);

      expect(store.attemptCount('き'), 1);
      expect(store.latestId('き', includeTraced: false), isNotNull);

      // sembast はタイマを使う。疑似非同期環境では完了しないため実時間で読む。
      late Sample sample;
      await tester.runAsync(
        () async => sample = await store.read(store.latestId('き', includeTraced: false)!),
      );
      expect(sample.strokes, hasLength(1));
      expect(sample.strokes.single.points.length, greaterThan(2));
    });

    testWidgets('もういちど書いても前の記録は消えない', (tester) async {
      await pumpScreen(tester);
      await drawLine(tester);
      await tapDone(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'もういちど'));
      await tester.pump();
      expect(find.byType(GlyphPreview), findsNothing, reason: '古い字形を残さない');

      await drawLine(tester);
      await tapDone(tester);
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

      expect(speaker.spoken, ['さん を かいてね'], reason: '数字は読みで言う');
    });

    testWidgets('お手本を押すともう一度読み上げる', (tester) async {
      await pumpScreen(tester);
      speaker.spoken.clear();

      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();

      expect(speaker.spoken, ['あ を かいてね']);
    });

    testWidgets('書き上げるとほめて、読み上げの導線を閉じる', (tester) async {
      await pumpScreen(tester);
      speaker.spoken.clear();

      await drawLine(tester);
      await tapDone(tester);

      expect(speaker.spoken, ['できたね！']);
      expect(
        find.byIcon(Icons.volume_up),
        findsNothing,
        reason: '字形が出たあとはお手本を押しても何も起きない',
      );
    });

    testWidgets('もういちどで書き直すとき、また読み上げる', (tester) async {
      await pumpScreen(tester);
      await drawLine(tester);
      await tapDone(tester);
      speaker.spoken.clear();

      await tester.tap(find.widgetWithText(OutlinedButton, 'もういちど'));
      await tester.pump();

      expect(speaker.spoken, ['あ を かいてね']);
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
      expect(speaker.spoken, ['あ を かいてね'], reason: '頼れるのは音だけ');

      await drawLine(tester);
      await tapDone(tester);

      // 書き上げたあとの字形は、お手本ではなく結果なので出してよい。
      expect(find.byType(GlyphPreview), findsOneWidget);
    });

    testWidgets('書いたときのモードがそのまま記録される', (tester) async {
      await pumpScreen(tester, char: 'き', mode: PracticeMode.free);
      await drawLine(tester);
      await tapDone(tester);

      late Sample sample;
      await tester.runAsync(
        () async => sample = await store.read(store.latestId('き', includeTraced: false)!),
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
      // 上から子供が書く。下敷きは自分の線より弱くする。
      expect(guide.faded, isTrue);
      expect(views.first.faded, isFalse, reason: 'お手本ははっきり出す');
      expect(guide.colorOf(0).a, lessThan(views.first.colorOf(0).a));
      expect(
        guide.colorOf(0).r,
        views.first.colorOf(0).r,
        reason: '色は変えず、薄さだけを変える',
      );
    });

    testWidgets('画ごとに色を変える', (tester) async {
      await pumpScreen(tester);
      final view = tester.widget<StrokeOrderView>(find.byType(StrokeOrderView));

      // 同じ色で引くと、どこで 1 画が終わるのか分からない。
      expect(view.order.strokeCount, 3, reason: 'あ は 3 画');
      expect(
        {for (var i = 0; i < 3; i++) view.colorOf(i)},
        hasLength(3),
        reason: '隣り合う画が同じ色にならない',
      );
    });

    testWidgets('画が色より多ければ、色は先頭へ戻る', (tester) async {
      await pumpScreen(tester);
      final view = tester.widget<StrokeOrderView>(find.byType(StrokeOrderView));
      final colors = StrokeOrderView.strokeColors.length;

      expect(view.colorOf(colors), view.colorOf(0));
      expect(view.colorOf(colors + 1), view.colorOf(1));
    });

    testWidgets('なぞり書きは別の履歴として残る', (tester) async {
      await pumpScreen(tester, char: 'き', mode: PracticeMode.trace);
      await drawLine(tester);
      await tapDone(tester);

      expect(store.attemptCount('き'), 1, reason: '書いた事実は残す');
      expect(
        speaker.spoken.last,
        contains('なぞれたね'),
        reason: 'できたね！ とは言わない。次の段へ誘う',
      );
      expect(
        store.latestId('き', includeTraced: false),
        isNull,
        reason: 'なぞり以外の履歴には入らない',
      );
      expect(
        store.latestId('き', includeTraced: true),
        isNotNull,
        reason: '混ぜればフォントに使える',
      );
    });

    testWidgets('指を離さずできた！を押しても書きかけの画が残る', (tester) async {
      await pumpScreen(tester, char: 'き');

      // 1 画だけ書いて、指を置いたまま「できた！」を押す。
      final rect = tester.getRect(find.byType(InkCanvas));
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();

      await tapDone(tester);

      late Sample sample;
      await tester.runAsync(
        () async => sample = await store.read(store.latestId('き', includeTraced: false)!),
      );
      expect(sample.strokes, hasLength(1), reason: '書きかけの画を捨てない');
      await gesture.up();
    });

    testWidgets('画面に置いたままの指が、あとから書く指を邪魔しない', (tester) async {
      await pumpScreen(tester);
      final rect = tester.getRect(find.byType(InkCanvas));

      // 端末を持つ手が画面に触れている。動かないまま。
      final resting = await tester.startGesture(rect.topLeft + const Offset(8, 8));
      await tester.pump();

      // もう一方の手で書く。
      final writing = await tester.startGesture(rect.center);
      await writing.moveBy(const Offset(80, 0));
      await writing.up();
      await tester.pump();
      await resting.up();
      await tester.pump();

      final canvas = tester.widget<InkCanvas>(find.byType(InkCanvas));
      expect(canvas.controller.strokes, hasLength(1), reason: '書いた 1 画が残る');

      // 隅に置いたままの指ではなく、真ん中から引いた線が残る。
      final points = canvas.controller.strokes.single.points;
      expect(points.first.x, closeTo(500, 50));
      expect(points.last.x, greaterThan(points.first.x + 100));
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

    testWidgets('書いた字に測りが付く', (tester) async {
      await pumpScreen(tester);
      await drawLine(tester);
      await tester.pump();
      await tapDone(tester);

      // 測るのは出題の重み付けのため。フォントに載せるかは決めない（SPEC 1）。
      final attempt = store.attempts('あ').single;
      expect(attempt.score, isNotNull);
      expect(attempt.score!.strokes, closeTo(1 / 3, 0.01), reason: 'あ は 3 画');
      expect(attempt.score!.retries, 0);
      expect(attempt.rejected, isFalse, reason: 'へたな字ははねない');
      expect(
        store.latestId('あ', includeTraced: false),
        isNotNull,
        reason: '点が低くても素材になる',
      );
    });

    testWidgets('できた！を押したら、もう書けない', (tester) async {
      await pumpScreen(tester);
      await drawLine(tester);
      await tester.pump();
      await tapDone(tester);

      // 押したあとに足した線は、記録に入らないまま画面にだけ残ってしまう。
      final before = store.attempts('あ').single.id;
      await drawLine(tester);
      await tester.pump();

      expect(find.byType(GlyphPreview), findsOneWidget, reason: '字形は消えない');
      expect(store.attempts('あ').single.id, before);
      expect(
        find.widgetWithText(FilledButton, 'できた！'),
        findsNothing,
        reason: '書き直すなら もういちど から',
      );
    });

    testWidgets('なぞり書きは、1 画引くごとに下敷きが減る', (tester) async {
      await pumpScreen(tester, char: 'き', mode: PracticeMode.trace);

      StrokeOrderView guide() => tester
          .widgetList<StrokeOrderView>(find.byType(StrokeOrderView))
          .last;
      expect(guide().order.strokeCount, 4, reason: 'き は 4 画');
      expect(guide().from, 0);

      await drawLine(tester);
      await tester.pump();

      // 残しておくと、自分の線とずれたときに はみ出した下敷きを
      // 塗りつぶそうとする。
      expect(guide().from, 1);

      await drawLine(tester);
      await tester.pump();
      expect(guide().from, 2);
    });

    testWidgets('引いている最中は、ペンが進んだぶんだけ下敷きが消える', (tester) async {
      await pumpScreen(tester, char: 'き', mode: PracticeMode.trace);

      StrokeOrderView guide() => tester
          .widgetList<StrokeOrderView>(find.byType(StrokeOrderView))
          .last;
      expect(guide().erased, 0);

      // 引いている途中で止める。
      final canvas = tester.getRect(find.byType(InkCanvas));
      final gesture = await tester.startGesture(
        Offset(canvas.left + canvas.width * 0.2, canvas.center.dy),
      );
      await tester.pump();
      expect(guide().erased, 0, reason: '置いただけでは消えない');

      await gesture.moveTo(
        Offset(canvas.left + canvas.width * 0.4, canvas.center.dy),
      );
      await tester.pump();
      final halfway = guide().erased;
      expect(halfway, greaterThan(0));
      expect(halfway, lessThan(1), reason: 'まだ引き終わっていない');

      await gesture.moveTo(
        Offset(canvas.left + canvas.width * 0.9, canvas.center.dy),
      );
      await tester.pump();
      expect(guide().erased, greaterThan(halfway), reason: 'ペンについてくる');

      // 引き終わると、その画は丸ごと消えて次の画に移る。
      await gesture.up();
      await tester.pump();
      expect(guide().from, 1);
      expect(guide().erased, 0);
    });

    testWidgets('消さない設定では、下敷きが書き終えるまで残る', (tester) async {
      await pumpScreen(
        tester,
        char: 'き',
        mode: PracticeMode.trace,
        traceErases: false,
      );

      StrokeOrderView guide() => tester
          .widgetList<StrokeOrderView>(find.byType(StrokeOrderView))
          .last;

      // 引いている最中も減らない。線を追うだけで手一杯の子は、消えると
      // 引く先を見失う（SPEC 7.1）。
      final canvas = tester.getRect(find.byType(InkCanvas));
      final gesture = await tester.startGesture(
        Offset(canvas.left + canvas.width * 0.2, canvas.center.dy),
      );
      await gesture.moveTo(
        Offset(canvas.left + canvas.width * 0.9, canvas.center.dy),
      );
      await tester.pump();
      expect(guide().erased, 0);

      // 1 画引き終わっても、その画は残ったまま。
      await gesture.up();
      await tester.pump();
      expect(guide().from, 0);
      expect(guide().order.strokeCount, 4, reason: 'き は 4 画');
    });

    testWidgets('もどすと、消した下敷きが戻る', (tester) async {
      await pumpScreen(tester, char: 'き', mode: PracticeMode.trace);
      await drawLine(tester);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();

      expect(
        tester
            .widgetList<StrokeOrderView>(find.byType(StrokeOrderView))
            .last
            .from,
        0,
      );
    });

    testWidgets('もういちど を押した回数が残る', (tester) async {
      await pumpScreen(tester);
      await drawLine(tester);
      await tester.pump();
      await tapDone(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'もういちど'));
      await tester.pumpAndSettle();
      await drawLine(tester);
      await tester.pump();
      await tapDone(tester);

      // 書き直した回数は苦手さの手がかりになる（SPEC 7.3）。
      expect(store.attempts('あ').last.score!.retries, 1);
    });

  });
}
