import 'package:flutter/material.dart';

import '../export/resolve_recipe.dart';
import '../model/char_set.dart';
import '../model/font_recipe.dart';
import '../model/user.dart';
import '../store/passcode.dart';
import '../store/recipe_store.dart';
import '../store/sample_store.dart';
import '../store/session.dart';
import '../store/word_book_store.dart';
import 'backup_section.dart';
import 'char_set_screen.dart';
import 'passcode_gate.dart';
import 'recipe_editor.dart';
import 'user_picker.dart';
import 'word_book_section.dart';
import 'word_history_section.dart';

/// 保護者向けの画面（SPEC 7.6）。
///
/// 子供向け画面とは目的が違う。こちらは「集まり具合を見る」「版を作って
/// フォントを出す」ための画面で、字を書く導線は置かない。
class AdminScreen extends StatelessWidget {
  const AdminScreen({
    super.key,
    required this.session,
    required this.locks,
  });

  final Session session;
  final Locks locks;

  SampleStore get store => session.samples;
  RecipeStore get recipes => session.recipes;
  WordBookStore get books => session.books;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        title: const Text('おうちの人へ'),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            store,
            recipes,
            books,
            session.attempts,
            locks.admin,
            locks.switching,
            session,
          ]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const Expanded(child: _Heading('書く人')),
                  FilledButton.icon(
                    onPressed: () => _addUser(context),
                    icon: const Icon(Icons.person_add),
                    label: const Text('ふやす'),
                  ),
                ],
              ),
              for (final user in session.users.all)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AvatarMark(avatar: user.avatar),
                  title: Text(user.displayName),
                  subtitle: Text(
                    user.id == session.current.id ? 'いま書いている人' : '',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '名前と印を変える',
                    onPressed: () => _editUser(context, user),
                  ),
                  onTap: () => session.switchTo(user.id),
                ),
              const SizedBox(height: 24),
              _Heading('${session.current.displayName} の集まり具合'),
              for (final charSet in session.current.visibleCharSets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CharSetRing(charSet: charSet, store: store),
                ),
              const SizedBox(height: 24),
              const _Heading('集める文字種'),
              const Text(
                'ここで外した文字種は、子供の画面に出なくなります。'
                '集めた字は消えません。',
                style: TextStyle(color: Color(0xff9c948a)),
              ),
              for (final charSet in CharSet.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: session.current.visibleCharSets.contains(charSet),
                  onChanged: (on) => _toggleCollecting(charSet, on ?? false),
                  title: Text(charSet.label),
                ),
              const SizedBox(height: 24),
              const _Heading('なぞり書きの下敷き'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: session.current.traceErases,
                onChanged: (on) => _toggleTraceErases(on),
                title: const Text('なぞったところを消す'),
                subtitle: Text(
                  session.current.traceErases
                      ? 'ペンが通ったところから下敷きが消えます。'
                          'はみ出した下敷きを塗りつぶしにいかなくなります'
                      : '書き終えるまで下敷きが残ります。'
                          '線を追うだけで手一杯の子は、消えると引く先を見失います',
                  style: const TextStyle(color: Color(0xff9c948a)),
                ),
              ),
              const SizedBox(height: 24),
              const _Heading('単語帳'),
              WordBookSection(session: session),
              const SizedBox(height: 24),
              const _Heading('ことばに出てこない字'),
              MissingCharsSection(session: session),
              const SizedBox(height: 24),
              const _Heading('書いたことばの記録'),
              WordHistorySection(session: session),
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
              const SizedBox(height: 24),
              const _Heading('控え'),
              BackupSection(session: session),
              const SizedBox(height: 24),
              const _Heading('ロック'),
              _PasscodeTile(
                passcode: locks.admin,
                title: 'この画面のロック',
                whenSet: 'この画面に入るときに聞きます',
                whenUnset: '掛けていません。決めると、子供がここに入れなくなります',
              ),
              _PasscodeTile(
                passcode: locks.switching,
                title: '書く人の切り替えのロック',
                whenSet: '子供の画面で人を切り替えるときに聞きます',
                whenUnset: '掛けていません。決めると、子供がよその人の記録に書けなくなります',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// なぞり書きの下敷きを消すかを変える（SPEC 7.1）。人ごとに覚える。
  Future<void> _toggleTraceErases(bool on) =>
      session.users.save(session.current.copyWith(traceErases: on));

  /// 集める文字種を変える。最後の 1 つは外させない。
  ///
  /// 全部外すと子供の画面が空になり、何をする画面か分からなくなる。
  Future<void> _toggleCollecting(CharSet charSet, bool on) async {
    final user = session.current;
    final collecting = {...user.visibleCharSets};
    if (on) {
      collecting.add(charSet);
    } else {
      if (collecting.length <= 1) return;
      collecting.remove(charSet);
    }
    await session.users.save(user.copyWith(collecting: collecting));
  }

  Future<void> _addUser(BuildContext context) async {
    final details = await askUserDetails(context, title: '書く人をふやす');
    if (details == null) return;
    // 足したらその人に切り替える。続けて書けるようにする。
    await session.addUser(name: details.name, avatar: details.avatar);
  }

  Future<void> _editUser(BuildContext context, User user) async {
    final details = await askUserDetails(
      context,
      title: '名前と印を変える',
      initialName: user.displayName,
      initialAvatar: user.avatar,
    );
    if (details == null) return;
    await session.users.save(
      user.copyWith(displayName: details.name, avatar: details.avatar),
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
    BestPolicy() => 'いちばん よく書けた字',
    AtPolicy(:final time) => '${formatDate(time)} までの字',
  };
  // 文字種ごとの時点指定があるときは、そちらが効いていることを伝える。
  final grouped = recipe.groupRules.isEmpty ? '' : '（文字種ごとに指定あり）';
  return '$sets ・ $when$grouped';
}

String formatDate(DateTime time) =>
    '${time.year}年${time.month}月${time.day}日';

/// パスコードを掛ける・変える・外す入口。掛け先ごとに 1 行。
class _PasscodeTile extends StatelessWidget {
  const _PasscodeTile({
    required this.passcode,
    required this.title,
    required this.whenSet,
    required this.whenUnset,
  });

  final Passcode passcode;
  final String title;
  final String whenSet;
  final String whenUnset;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(passcode.isSet ? Icons.lock : Icons.lock_open),
      title: Text(title),
      subtitle: Text(passcode.isSet ? whenSet : whenUnset),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showPasscodeSettings(context, passcode),
    );
  }
}
