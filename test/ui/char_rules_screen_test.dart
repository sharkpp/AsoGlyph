import 'package:asoglyph/font/glyph.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/font_recipe.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/ui/char_rules_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

Sample _written(
  String char, {
  required DateTime at,
  PracticeMode mode = PracticeMode.copy,
}) => Sample(
  id: '$char-${at.toIso8601String()}',
  char: char,
  mode: mode,
  writtenAt: at,
  strokes: [
    Stroke(const [
      InkPoint(x: 300, y: 500, t: 0, pressure: 0),
      InkPoint(x: 700, y: 500, t: 20, pressure: 0),
    ]),
  ],
);

void main() {
  final spring = DateTime(2026, 4, 1);
  final autumn = DateTime(2026, 10, 1);

  late SampleStore store;

  setUp(() async => store = await openMemoryStore());

  FontRecipe recipeOf({Map<String, String> charRules = const {}}) => FontRecipe(
    id: 'r',
    name: 'テスト',
    createdAt: DateTime(2026),
    fontMeta: FontMetadata(familyName: 'Test'),
    charSets: CharSet.values.toSet(),
    charRules: charRules,
  );

  Future<FontRecipe?> pumpScreen(
    WidgetTester tester, {
    Map<String, String> charRules = const {},
  }) async {
    FontRecipe? changed;
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CharRulesScreen(
          recipe: recipeOf(charRules: charRules),
          store: store,
          onChanged: (recipe) => changed = recipe,
        ),
      ),
    );
    return changed;
  }

  testWidgets('書いた記録のある字だけが並ぶ', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('ア', at: spring));
    });
    await pumpScreen(tester);

    expect(find.text('あ'), findsOneWidget);
    expect(find.text('ア'), findsOneWidget);
    expect(find.text('い'), findsNothing, reason: '書いていない字は選びようがない');
  });

  testWidgets('字を選ぶと、その字の版が新しい順に並ぶ', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('あ', at: autumn));
    });
    await pumpScreen(tester);

    await tester.tap(find.text('あ'));
    await tester.pumpAndSettle();

    expect(find.text('2026年10月1日'), findsOneWidget);
    expect(find.text('2026年4月1日'), findsOneWidget);
    // 規則へ戻す道も必ず出す。
    expect(find.text('規則どおりにする'), findsOneWidget);
  });

  testWidgets('版を選ぶと、その字だけ差し替わる', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('あ', at: autumn));
    });
    FontRecipe? changed;
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CharRulesScreen(
          recipe: recipeOf(),
          store: store,
          onChanged: (recipe) => changed = recipe,
        ),
      ),
    );

    await tester.tap(find.text('あ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026年4月1日'));
    await tester.pumpAndSettle();

    expect(changed!.charRules, {'あ': 'あ-${spring.toIso8601String()}'});
  });

  testWidgets('規則どおりに戻せる', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
    });
    FontRecipe? changed;
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CharRulesScreen(
          recipe: recipeOf(charRules: {'あ': 'あ-${spring.toIso8601String()}'}),
          store: store,
          onChanged: (recipe) => changed = recipe,
        ),
      ),
    );
    expect(find.byIcon(Icons.push_pin), findsOneWidget, reason: '差し替え中の印');

    await tester.tap(find.text('あ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('規則どおりにする'));
    await tester.pumpAndSettle();

    expect(changed!.charRules, isEmpty);
  });

  testWidgets('なぞった字も選べる', (tester) async {
    // charRules は名指しなので、なぞりを混ぜるかの設定に左右されない。
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring, mode: PracticeMode.trace));
    });
    await pumpScreen(tester);

    await tester.tap(find.text('あ'));
    await tester.pumpAndSettle();

    expect(find.textContaining('なぞって書いた'), findsOneWidget);
  });

  testWidgets('まだ何も書いていなければ、その旨を出す', (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('まだありません'), findsOneWidget);
  });
}
