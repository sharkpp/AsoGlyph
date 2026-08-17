import 'package:asoglyph/store/passcode.dart';
import 'package:asoglyph/ui/passcode_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

void main() {
  /// パスコードを聞く画面を出す。通れた結果はリストに積まれる。
  ///
  /// 結果は聞き終わってから返るので、呼び出し側で待ち受けずに集める。
  Future<List<bool>> openGate(WidgetTester tester, Passcode passcode) async {
    final passed = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  passed.add(await unlockAdmin(context, passcode)),
              child: const Text('入る'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('入る'));
    await tester.pumpAndSettle();
    return passed;
  }

  testWidgets('掛けていなければ、そのまま通る', (tester) async {
    final passcode = await openMemoryPasscode();
    await openGate(tester, passcode);
    await tester.pumpAndSettle();

    // 既定は無効（SPEC 7.6）。聞かずに通す。
    expect(find.text('パスコード'), findsNothing);
  });

  testWidgets('掛けていれば聞く', (tester) async {
    final passcode = await openMemoryPasscode(code: '1234');
    await openGate(tester, passcode);

    expect(find.text('パスコード'), findsOneWidget);
  });

  testWidgets('合っていれば通る', (tester) async {
    final passcode = await openMemoryPasscode(code: '1234');
    final passed = await openGate(tester, passcode);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.widgetWithText(FilledButton, '入る'));
    await tester.pumpAndSettle();

    expect(find.text('パスコード'), findsNothing, reason: '閉じて通る');
    expect(passed, [true]);
  });

  testWidgets('違えば通さず、その場で言う', (tester) async {
    final passcode = await openMemoryPasscode(code: '1234');
    await openGate(tester, passcode);

    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.widgetWithText(FilledButton, '入る'));
    await tester.pumpAndSettle();

    expect(find.text('ちがいます'), findsOneWidget);
    expect(find.text('パスコード'), findsOneWidget, reason: '閉じない');
  });

  testWidgets('忘れたときは、おとなの問いを解けば外せる', (tester) async {
    final passcode = await openMemoryPasscode(code: '1234');
    await openGate(tester, passcode);

    await tester.tap(find.text('わすれた'));
    await tester.pumpAndSettle();

    // 集めた字を人質にしない。外すだけ。
    expect(find.textContaining('集めた字も版も消えません'), findsOneWidget);

    // 問いは掛け算。答えを画面から読み取って入れる。
    final question = tester
        .widget<Text>(find.textContaining('×'))
        .data!;
    final parts = question.replaceAll(' は？', '').split(' × ');
    final answer = int.parse(parts[0]) * int.parse(parts[1]);

    await tester.enterText(find.byType(TextField).last, '$answer');
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '外す'));
    });
    await tester.pumpAndSettle();

    expect(passcode.isSet, isFalse);
  });

  testWidgets('おとなの問いを間違えたら外れない', (tester) async {
    final passcode = await openMemoryPasscode(code: '1234');
    await openGate(tester, passcode);

    await tester.tap(find.text('わすれた'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0');
    await tester.tap(find.widgetWithText(FilledButton, '外す'));
    await tester.pumpAndSettle();

    expect(passcode.isSet, isTrue);
  });

  testWidgets('やめれば通らない', (tester) async {
    final passcode = await openMemoryPasscode(code: '1234');
    final passed = await openGate(tester, passcode);

    await tester.tap(find.widgetWithText(TextButton, 'やめる'));
    await tester.pumpAndSettle();

    expect(passed, [false]);
    expect(passcode.isSet, isTrue, reason: 'やめただけで外れはしない');
  });

  group('パスコードの設定', () {
    Future<void> openSettings(WidgetTester tester, Passcode passcode) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPasscodeSettings(context, passcode),
                child: const Text('設定'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('設定'));
      await tester.pumpAndSettle();
    }

    testWidgets('決めると掛かる', (tester) async {
      final passcode = await openMemoryPasscode();
      await openSettings(tester, passcode);

      await tester.enterText(find.byType(TextField), '4321');
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, '決める'));
      });
      await tester.pumpAndSettle();

      expect(passcode.isSet, isTrue);
      expect(passcode.matches('4321'), isTrue);
    });

    testWidgets('空で決めると外れる', (tester) async {
      final passcode = await openMemoryPasscode(code: '1234');
      await openSettings(tester, passcode);

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, '決める'));
      });
      await tester.pumpAndSettle();

      expect(passcode.isSet, isFalse);
    });
  });
}
