import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/font_recipe.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/score.dart';
import 'package:asoglyph/export/resolve_recipe.dart';
import 'package:asoglyph/store/recipe_store.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/ui/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

Sample _written(String char, {required DateTime at, double? overall}) => Sample(
  id: '$char-${at.toIso8601String()}',
  char: char,
  mode: PracticeMode.copy,
  writtenAt: at,
  score: overall == null
      ? null
      : Score(
          shape: overall,
          strokes: overall,
          fit: overall,
          durationMs: 1000,
          retries: 0,
        ),
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
  late RecipeStore recipes;
  late FontRecipe recipe;

  setUp(() async {
    store = await openMemoryStore();
    recipes = await openMemoryRecipes();
    recipe = await recipes.create('テスト');
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeEditor(
          recipe: recipes.all.single,
          store: store,
          recipes: recipes,
        ),
      ),
    );
  }

  /// 今この版に何字入るか。画面のいちばん上に出ている。
  String summary(WidgetTester tester) =>
      tester.widget<Text>(find.textContaining('字').first).data!;

  testWidgets('入る字数を出す', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('ア', at: autumn));
    });
    await pumpEditor(tester);

    expect(summary(tester), '2 字');
  });

  testWidgets('文字種を外すとその字は入らなくなる', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('ア', at: autumn));
    });
    await pumpEditor(tester);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(CheckboxListTile, 'カタカナ'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    expect(summary(tester), '1 字');
    expect(recipes.all.single.charSets, isNot(contains(CharSet.katakana)));
  });

  testWidgets('変えたその場で保存する', (tester) async {
    await pumpEditor(tester);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(CheckboxListTile, 'すうじ'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    // 「保存」を押させない。押し忘れで版が消える導線を作らない。
    // 読み書きは必ず runAsync の中で行う（sembast はタイマを使う）。
    await tester.runAsync(recipes.load);
    expect(recipes.all.single.charSets, isNot(contains(CharSet.digits)));
  });

  testWidgets('あの頃の字にすると、その日までの字だけになる', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('い', at: autumn));
      // 日付選択そのものは Flutter の部品なので、規則を直に置いて確かめる。
      await recipes.save(recipe.copyWith(base: AtPolicy(spring)));
    });
    // 時系列スライダーの見本は運筆を読む。sembast はタイマを使うため、
    // 画面を組むところごと runAsync の中で進める。
    await tester.runAsync(() async {
      await pumpEditor(tester);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(summary(tester), '1 字', reason: '秋に書いた い は入らない');
    expect(find.textContaining('2026年4月1日 までに書いたもの'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget, reason: '日付をドラッグして選べる');
  });

  testWidgets('入る字が無ければフォントを出さない', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('フォントを出す'));
    await tester.pump();

    expect(find.text('この版に入る字がありません'), findsOneWidget);
  });

  testWidgets('文字種を外すと、その文字種の時点指定も残さない', (tester) async {
    await tester.runAsync(
      () => recipes.save(
        recipe.copyWith(groupRules: {CharSet.katakana: AtPolicy(spring)}),
      ),
    );
    await pumpEditor(tester);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(CheckboxListTile, 'カタカナ'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    expect(recipes.all.single.groupRules, isEmpty);
  });
  testWidgets('いちばん よく書けた字を選べる', (tester) async {
    final tidy = _written('あ', at: DateTime(2026, 4, 1), overall: 0.9);
    await tester.runAsync(() async {
      await store.add(tidy);
      await store.add(_written('あ', at: DateTime(2026, 5, 1), overall: 0.1));
    });
    await pumpEditor(tester);

    await tester.tap(find.text('いちばん よく書けた字'));
    await tester.pumpAndSettle();

    expect(recipes.all.single.base, const BestPolicy());
    expect(
      resolveRecipe(recipes.all.single, store, includeTraced: false)['あ'],
      tidy.id,
    );
  });

}
