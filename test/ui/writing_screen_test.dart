import 'package:asoglyph/ink/ink_canvas.dart';
import 'package:asoglyph/ink/ink_controller.dart';
import 'package:asoglyph/main.dart';
import 'package:asoglyph/ui/glyph_preview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    testWidgets('線を引くとフォントの字が出る', (tester) async {
      await tester.pumpWidget(const AsoGlyphApp());

      expect(find.text('「あ」を かいてみよう'), findsOneWidget);
      expect(find.byType(GlyphPreview), findsNothing);

      await _drawLine(tester);
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'できた！'))
            .onPressed,
        isNotNull,
      );

      await _tapDone(tester);

      expect(find.byType(GlyphPreview), findsOneWidget);
      final preview = tester.widget<GlyphPreview>(find.byType(GlyphPreview));
      expect(preview.contours, isNotEmpty, reason: '輪郭が起こせていない');

      // 書き出しの導線が現れる。
      expect(find.widgetWithText(FilledButton, 'TTF'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'OTF'), findsOneWidget);
    });

    testWidgets('書き直すとプレビューは無効になる', (tester) async {
      await tester.pumpWidget(const AsoGlyphApp());
      await _drawLine(tester);
      await _tapDone(tester);
      expect(find.byType(GlyphPreview), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'けす'));
      await tester.pump();
      expect(find.byType(GlyphPreview), findsNothing, reason: '古い字形を残さない');
    });

    testWidgets('何も書いていないうちは操作できない', (tester) async {
      await tester.pumpWidget(const AsoGlyphApp());

      for (final label in ['もどす', 'けす']) {
        final button = find.widgetWithText(OutlinedButton, label);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      }
      final done = find.widgetWithText(FilledButton, 'できた！');
      expect(tester.widget<FilledButton>(done).onPressed, isNull);
    });

    testWidgets('スタイラス使用中はタッチを無視する', (tester) async {
      await tester.pumpWidget(const AsoGlyphApp());
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
/// ラスタ化は `Picture.toImage()` を通る実時間の非同期処理で、ウィジェットテストの
/// 疑似非同期環境では [WidgetTester.runAsync] の中でしか完了しない。
Future<void> _tapDone(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.widgetWithText(FilledButton, 'できた！'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pump();
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
