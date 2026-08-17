import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/font_recipe.dart';
import 'package:asoglyph/store/recipe_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

void main() {
  late RecipeStore recipes;
  setUp(() async => recipes = await openMemoryRecipes());

  test('作った版は既定で今の字を全部入れる', () async {
    final recipe = await recipes.create('いまの字');

    expect(recipe.charSets, CharSet.values.toSet());
    expect(recipe.base, const LatestPolicy());
    expect(recipe.fontMeta.familyName, 'いまの字');
  });

  test('規則ごと読み書きできる', () async {
    final created = await recipes.create('あの頃');
    final spring = DateTime.utc(2026, 4, 30);
    await recipes.save(
      created.copyWith(
        charSets: {CharSet.hiragana},
        base: AtPolicy(spring),
        groupRules: {CharSet.hiragana: const LatestPolicy()},
        charRules: {'あ': 'sample-1'},
      ),
    );

    // 開き直しても、版は解決規則の集合として残っている。
    await recipes.load();

    final loaded = recipes.all.single;
    expect(loaded.id, created.id);
    expect(loaded.name, 'あの頃');
    expect(loaded.charSets, {CharSet.hiragana});
    expect(loaded.base, AtPolicy(spring));
    expect(loaded.groupRules, {CharSet.hiragana: const LatestPolicy()});
    expect(loaded.charRules, {'あ': 'sample-1'});
  });

  test('複製は規則を引き継ぎ、別の版になる', () async {
    final source = await recipes.create('もと');
    await recipes.save(source.copyWith(charSets: {CharSet.digits}));

    final copy = await recipes.duplicate(recipes.all.single, 'コピー');

    expect(copy.id, isNot(source.id));
    expect(copy.name, 'コピー');
    expect(copy.charSets, {CharSet.digits});
    expect(recipes.all, hasLength(2));
  });

  test('版を消しても、ほかの版は残る', () async {
    final a = await recipes.create('A');
    await recipes.create('B');

    await recipes.remove(a.id);

    expect(recipes.all.map((r) => r.name), ['B']);
  });

  test('作った順に並ぶ', () async {
    await recipes.create('さいしょ');
    await recipes.create('つぎ');
    await recipes.load();

    expect(recipes.all.map((r) => r.name), ['さいしょ', 'つぎ']);
  });

  test('版を変えると知らせる', () async {
    var notified = 0;
    recipes.addListener(() => notified++);

    await recipes.create('A');
    expect(notified, 1);

    await recipes.remove(recipes.all.single.id);
    expect(notified, 2);
  });

  test('フォントの作成日時は固定のまま', () async {
    // 同じ版と同じ記録からは、同じバイト列が出る必要がある（SPEC 4.3）。
    final recipe = await recipes.create('A');
    await recipes.load();

    expect(recipes.all.single.fontMeta.created, recipe.fontMeta.created);
  });
}
