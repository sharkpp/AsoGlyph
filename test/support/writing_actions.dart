import 'package:asoglyph/ink/ink_canvas.dart';
import 'package:asoglyph/ui/glyph_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「できた！」を押して字形が出るまで待つ。
///
/// ラスタ化と記録は `Picture.toImage()` や sembast を通る実時間の非同期処理で、
/// ウィジェットテストの疑似非同期環境では [WidgetTester.runAsync] の中でしか
/// 進まない。所要時間は実行環境で変わるため、決め打ちで待たずに結果を待つ。
Future<void> tapDone(WidgetTester tester) async {
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

/// 書き上げたあと、自分で次の字へ進むのを待つ（語を書いているとき）。
///
/// ほめ言葉を言い終わるまで進まないので、実時間を進める必要がある。
Future<void> advance(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    if (find.byType(GlyphPreview).evaluate().isEmpty) return;
  }
  fail('つぎの字へ進まない');
}

/// キャンバスの中央を横切る線を引く。
Future<void> drawLine(WidgetTester tester) async {
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
