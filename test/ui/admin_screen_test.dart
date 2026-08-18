import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/font_recipe.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/store/passcode.dart';
import 'package:asoglyph/store/recipe_store.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/store/session.dart';
import 'package:asoglyph/ui/admin_screen.dart';
import 'package:asoglyph/ui/char_set_screen.dart';
import 'package:asoglyph/ui/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

Sample _written(String char, {required DateTime at}) => Sample(
  id: '$char-${at.toIso8601String()}',
  char: char,
  mode: PracticeMode.copy,
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

  late Session session;
  late SampleStore store;
  late RecipeStore recipes;
  late Locks locks;

  setUp(() async {
    session = await openMemorySession();
    store = session.samples;
    recipes = session.recipes;
    locks = await openMemoryLocks();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: AdminScreen(session: session, locks: locks)),
    );
  }

  testWidgets('版がまだ無いことを伝える', (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('まだ版がありません'), findsOneWidget);
  });

  testWidgets('版を作ると一覧に出て、編集画面へ入る', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('作る'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'いちねんせい');
    await tester.runAsync(() async {
      await tester.tap(find.text('決める'));
    });
    await tester.pumpAndSettle();

    // 作ったらそのまま中身を決めさせる。
    expect(find.byType(RecipeEditor), findsOneWidget);
    expect(recipes.all.single.name, 'いちねんせい');
  });

  testWidgets('版は何字入るかを見せる', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('い', at: autumn));
      await recipes.create('ぜんぶ');
    });
    await pumpScreen(tester);

    expect(
      find.textContaining('2 / ${totalOf(recipes.all.single)} 字'),
      findsOneWidget,
    );
  });

  testWidgets('版の中身を 1 行で言い表す', (tester) async {
    final recipe = await tester.runAsync(() => recipes.create('あの頃'));
    await tester.runAsync(
      () => recipes.save(
        recipe!.copyWith(
          charSets: {CharSet.hiragana},
          base: AtPolicy(spring),
        ),
      ),
    );
    await pumpScreen(tester);

    // 一覧の 1 行で、出す文字種といつの字かが分かる。
    expect(
      find.text('0 / ${CharSet.hiragana.chars.length} 字 ・ ひらがな ・ 2026年4月1日 までの字'),
      findsOneWidget,
    );
  });

  testWidgets('版を消しても集めた字は消えない', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await recipes.create('消す版');
    });
    await pumpScreen(tester);

    await tester.tap(find.byType(PopupMenuButton<void Function()>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('消す'));
    await tester.pumpAndSettle();

    // 版は導出ビューでしかない。誤解されないよう画面でも断っている。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('集めた字は消えません'),
      ),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '消す'));
    });
    await tester.pumpAndSettle();

    expect(recipes.all, isEmpty);
    expect(store.collectedChars(includeTraced: false), ['あ']);
  });

  testWidgets('集まり具合を文字種ごとに見せる', (tester) async {
    await pumpScreen(tester);

    for (final charSet in CharSet.values) {
      expect(
        find.descendant(
          of: find.byType(CharSetRing),
          matching: find.text(charSet.label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('集める文字種を外すと、集まり具合からも消える', (tester) async {
    await pumpScreen(tester);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(CheckboxListTile, 'カタカナ'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    // 子供の画面に出さない文字種は、集まり具合にも並べない。
    expect(
      find.descendant(
        of: find.byType(CharSetRing),
        matching: find.text('カタカナ'),
      ),
      findsNothing,
    );
    expect(session.current.collecting, isNot(contains(CharSet.katakana)));
  });

  testWidgets('集める文字種を全部は外せない', (tester) async {
    await pumpScreen(tester);

    for (final label in ['カタカナ', 'ひらがな', 'すうじ']) {
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(CheckboxListTile, label));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
    }

    // 全部外すと子供の画面が空になり、何をする画面か分からなくなる。
    expect(session.current.visibleCharSets, hasLength(1));
  });

  testWidgets('ロックは 2 つ別々に掛けられる', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('書く人の切り替えのロック'), 200);

    // 掛け先が違うので、パスコードも別にする（SPEC 7.5 / 7.6）。
    await tester.tap(find.text('書く人の切り替えのロック'));
    await tester.pumpAndSettle();
    expect(find.textContaining('書く人を切り替えるときに聞きます'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4321');
    await tester.runAsync(() async {
      await tester.tap(find.text('決める'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(locks.switching.matches('4321'), isTrue);
    expect(locks.admin.isSet, isFalse, reason: '管理画面のほうは掛かっていない');
  });
}

/// 版の対象字数。テストの期待値を実装と揃えるために使う。
int totalOf(FontRecipe recipe) =>
    recipe.charSets.fold(0, (sum, set) => sum + set.chars.length);
