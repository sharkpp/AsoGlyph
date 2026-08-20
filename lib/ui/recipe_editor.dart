import 'package:flutter/material.dart';

import '../export/resolve_recipe.dart';
import '../model/char_set.dart';
import '../model/font_recipe.dart';
import '../store/recipe_store.dart';
import '../store/sample_store.dart';
import 'admin_screen.dart' show formatDate;
import 'char_rules_screen.dart';
import 'export_sheet.dart';
import 'timeline_slider.dart';

/// 版の中身を決める画面（SPEC 7.6）。
///
/// 「どの文字種を出すか」と「いつの字を採るか」の 2 つが本体。
/// この 2 つで「あの頃の文字」が表せる。
class RecipeEditor extends StatefulWidget {
  const RecipeEditor({
    super.key,
    required this.recipe,
    required this.store,
    required this.recipes,
  });

  final FontRecipe recipe;
  final SampleStore store;
  final RecipeStore recipes;

  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor> {
  late FontRecipe _recipe = widget.recipe;

  SampleStore get store => widget.store;

  /// 版を変えたら、その場で保存する。「保存」ボタンを押させない。
  Future<void> _update(FontRecipe recipe) async {
    setState(() => _recipe = recipe);
    await widget.recipes.save(recipe);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        title: Text(_recipe.name),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Summary(recipe: _recipe, store: store),
              const SizedBox(height: 24),
              const _Heading('出す文字種'),
              for (final charSet in CharSet.values)
                _CharSetRow(
                  charSet: charSet,
                  recipe: _recipe,
                  onToggle: (on) => _toggleCharSet(charSet, on),
                  onPickTime: () => _pickGroupTime(charSet),
                  onClearTime: () => _clearGroupRule(charSet),
                ),
              const SizedBox(height: 24),
              const _Heading('いつの字を採るか'),
              _BasePolicyRow(
                policy: _recipe.base,
                onLatest: () =>
                    _update(_recipe.copyWith(base: const LatestPolicy())),
                onBest: () =>
                    _update(_recipe.copyWith(base: const BestPolicy())),
                onPick: _pickBaseTime,
              ),
              // 「あの頃」がいつかは、日付を見ても分からない。字が変わるのを
              // 見て決められるようにする（SPEC 7.6）。
              if (_recipe.base case AtPolicy(:final time))
                TimelineSlider(
                  recipe: _recipe,
                  store: store,
                  time: time,
                  onChanged: (picked) => _update(
                    // その日いっぱいを含める。
                    _recipe.copyWith(
                      base: AtPolicy(
                        DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              const _Heading('字ごとの差し替え'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('字を選び直す'),
                subtitle: Text(
                  _recipe.charRules.isEmpty
                      ? '規則どおり'
                      : '${_recipe.charRules.length} 字を差し替え中',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openCharRules,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                onPressed: () => _export(context),
                icon: const Icon(Icons.ios_share),
                label: const Text('フォントを出力'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleCharSet(CharSet charSet, bool on) {
    final charSets = {..._recipe.charSets};
    if (on) {
      charSets.add(charSet);
    } else {
      charSets.remove(charSet);
    }
    // 外した文字種の時点指定は残さない。
    final groupRules = {..._recipe.groupRules}..removeWhere(
      (set, _) => !charSets.contains(set),
    );
    _update(_recipe.copyWith(charSets: charSets, groupRules: groupRules));
  }

  Future<void> _pickBaseTime() async {
    final time = await _askDate(context, _recipe.base);
    if (time != null) _update(_recipe.copyWith(base: AtPolicy(time)));
  }

  Future<void> _pickGroupTime(CharSet charSet) async {
    final current = _recipe.groupRules[charSet];
    final time = await _askDate(context, current ?? _recipe.base);
    if (time == null) return;
    _update(
      _recipe.copyWith(
        groupRules: {..._recipe.groupRules, charSet: AtPolicy(time)},
      ),
    );
  }

  void _clearGroupRule(CharSet charSet) {
    _update(
      _recipe.copyWith(
        groupRules: {..._recipe.groupRules}..remove(charSet),
      ),
    );
  }

  void _openCharRules() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CharRulesScreen(
          recipe: _recipe,
          store: store,
          onChanged: _update,
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context) =>
      exportRecipeFont(context, recipe: _recipe, store: store);
}

/// 今この版が何字になるか。規則をいじるたびに動く。
class _Summary extends StatelessWidget {
  const _Summary({required this.recipe, required this.store});

  final FontRecipe recipe;
  final SampleStore store;

  @override
  Widget build(BuildContext context) {
    final count = resolvedCount(recipe, store, includeTraced: false);
    final total = totalChars(recipe);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count 字',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              total == 0
                  ? '文字種を選んでください'
                  : '出す対象 $total 字のうち、書けている字',
              style: const TextStyle(color: Color(0xff9c948a)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharSetRow extends StatelessWidget {
  const _CharSetRow({
    required this.charSet,
    required this.recipe,
    required this.onToggle,
    required this.onPickTime,
    required this.onClearTime,
  });

  final CharSet charSet;
  final FontRecipe recipe;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;
  final VoidCallback onClearTime;

  @override
  Widget build(BuildContext context) {
    final on = recipe.charSets.contains(charSet);
    final rule = recipe.groupRules[charSet];

    return CheckboxListTile(
      value: on,
      onChanged: (value) => onToggle(value ?? false),
      title: Text(charSet.label),
      subtitle: Text(
        switch (rule) {
          AtPolicy(:final time) => '${formatDate(time)} までの字',
          _ => 'ぜんぶの版に合わせる',
        },
      ),
      secondary: on
          ? PopupMenuButton<VoidCallback>(
              tooltip: 'この文字種だけの時点',
              icon: Icon(
                Icons.schedule,
                color: rule == null ? const Color(0xff9c948a) : null,
              ),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(value: onPickTime, child: const Text('時点を決める')),
                if (rule != null)
                  PopupMenuItem(
                    value: onClearTime,
                    child: const Text('ぜんぶの版に合わせる'),
                  ),
              ],
            )
          : null,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

/// 版ぜんぶに効く規則の選び方。
enum _BaseChoice { latest, best, at }

class _BasePolicyRow extends StatelessWidget {
  const _BasePolicyRow({
    required this.policy,
    required this.onLatest,
    required this.onBest,
    required this.onPick,
  });

  final Policy policy;
  final VoidCallback onLatest;
  final VoidCallback onBest;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<_BaseChoice>(
      groupValue: switch (policy) {
        LatestPolicy() => _BaseChoice.latest,
        BestPolicy() => _BaseChoice.best,
        AtPolicy() => _BaseChoice.at,
      },
      onChanged: (choice) => switch (choice ?? _BaseChoice.latest) {
        _BaseChoice.latest => onLatest(),
        _BaseChoice.best => onBest(),
        _BaseChoice.at => onPick(),
      },
      child: Column(
        children: [
          const RadioListTile<_BaseChoice>(
            value: _BaseChoice.latest,
            title: Text('いまの字'),
            subtitle: Text('いちばん新しく書いたもの'),
          ),
          // 点で採否を決めるのではなく、同じ字を何度も書いたときに
          // どれを採るかを選ばせるだけ（SPEC 1 / 4.3）。
          const RadioListTile<_BaseChoice>(
            value: _BaseChoice.best,
            title: Text('いちばん よく書けた字'),
            subtitle: Text('同じ字のうち、お手本に近く書けたもの'),
          ),
          RadioListTile<_BaseChoice>(
            value: _BaseChoice.at,
            title: const Text('あの頃の字'),
            subtitle: Text(
              switch (policy) {
                AtPolicy(:final time) => '${formatDate(time)} までに書いたもの',
                _ => '日付を決める',
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
  );
}

/// 日付を選ばせる。字を集め始める前より昔は選ばせない。
Future<DateTime?> _askDate(BuildContext context, Policy current) {
  final now = DateTime.now();
  final initial = switch (current) {
    AtPolicy(:final time) => time,
    _ => now,
  };
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: now,
    helpText: 'いつまでの字にしますか',
  ).then((date) {
    // その日いっぱいを含める。日付で選ばせて時刻で切ると直感に反する。
    if (date == null) return null;
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  });
}
