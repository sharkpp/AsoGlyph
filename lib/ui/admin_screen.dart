import 'package:flutter/material.dart';

import '../export/resolve_recipe.dart';
import '../model/char_set.dart';
import '../model/font_recipe.dart';
import '../store/recipe_store.dart';
import '../store/sample_store.dart';
import 'char_set_screen.dart';
import 'recipe_editor.dart';

/// 保護者向けの画面（SPEC 7.6）。
///
/// 子供向け画面とは目的が違う。こちらは「集まり具合を見る」「版を作って
/// フォントを出す」ための画面で、字を書く導線は置かない。
class AdminScreen extends StatelessWidget {
  const AdminScreen({
    super.key,
    required this.store,
    required this.recipes,
  });

  final SampleStore store;
  final RecipeStore recipes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        title: const Text('おうちの人へ'),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([store, recipes]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Heading('集まり具合'),
              for (final charSet in CharSet.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CharSetRing(charSet: charSet, store: store),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: _Heading('フォントの版')),
                  FilledButton.icon(
                    onPressed: () => _create(context),
                    icon: const Icon(Icons.add),
                    label: const Text('作る'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (recipes.all.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'まだ版がありません。\n'
                    '「作る」で、出す文字種といつの字かを決めた版を残せます。',
                    style: TextStyle(color: Color(0xff9c948a)),
                  ),
                ),
              for (final recipe in recipes.all)
                _RecipeCard(
                  recipe: recipe,
                  store: store,
                  onOpen: () => _edit(context, recipe),
                  onDuplicate: () => _duplicate(context, recipe),
                  onDelete: () => _delete(context, recipe),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await _askName(context, title: '版の名前', initial: 'いまの字');
    if (name == null) return;
    final recipe = await recipes.create(name);
    if (context.mounted) await _edit(context, recipe);
  }

  Future<void> _edit(BuildContext context, FontRecipe recipe) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            RecipeEditor(recipe: recipe, store: store, recipes: recipes),
      ),
    );
  }

  Future<void> _duplicate(BuildContext context, FontRecipe recipe) async {
    final name = await _askName(
      context,
      title: '複製した版の名前',
      initial: '${recipe.name} のコピー',
    );
    if (name == null) return;
    await recipes.duplicate(recipe, name);
  }

  Future<void> _delete(BuildContext context, FontRecipe recipe) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「${recipe.name}」を消しますか？'),
        // 版は導出ビューでしかない。ここが誤解されると消すのが怖くなる。
        content: const Text('集めた字は消えません。版（どの字を採るかの決めごと）だけを消します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('消す'),
          ),
        ],
      ),
    );
    if (ok ?? false) await recipes.remove(recipe.id);
  }
}

/// 版の名前を聞く。
Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('決める'),
        ),
      ],
    ),
  ).then((value) => (value == null || value.isEmpty) ? null : value);
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
  );
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.store,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });

  final FontRecipe recipe;
  final SampleStore store;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final count = resolvedCount(recipe, store, includeTraced: false);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(recipe.name),
        subtitle: Text('$count / ${totalChars(recipe)} 字 ・ ${describe(recipe)}'),
        onTap: onOpen,
        trailing: PopupMenuButton<void Function()>(
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            PopupMenuItem(value: onDuplicate, child: const Text('複製する')),
            PopupMenuItem(value: onDelete, child: const Text('消す')),
          ],
        ),
      ),
    );
  }
}

/// 版の中身を 1 行で言い表す。
String describe(FontRecipe recipe) {
  final sets = recipe.charSets.isEmpty
      ? '文字種なし'
      : CharSet.values
            .where(recipe.charSets.contains)
            .map((set) => set.label)
            .join('・');
  final when = switch (recipe.base) {
    LatestPolicy() => 'いまの字',
    AtPolicy(:final time) => '${formatDate(time)} までの字',
  };
  // 文字種ごとの時点指定があるときは、そちらが効いていることを伝える。
  final grouped = recipe.groupRules.isEmpty ? '' : '（文字種ごとに指定あり）';
  return '$sets ・ $when$grouped';
}

String formatDate(DateTime time) =>
    '${time.year}年${time.month}月${time.day}日';
