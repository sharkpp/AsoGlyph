import 'package:flutter/material.dart';

import '../model/font_recipe.dart';
import '../model/sample.dart';
import '../store/sample_store.dart';
import 'admin_screen.dart' show formatDate;
import 'stroke_preview.dart';

/// 字ごとに、どの版を使うかを選び直す画面（SPEC 7.6 / 4.3 の `charRules`）。
///
/// 「今の字。ただし『あ』だけ初めて書けた日の版」を作るためのもの。
class CharRulesScreen extends StatefulWidget {
  const CharRulesScreen({
    super.key,
    required this.recipe,
    required this.store,
    required this.onChanged,
  });

  final FontRecipe recipe;
  final SampleStore store;

  /// 差し替えを変えたら親へ返す。保存は親（版の編集画面）が持つ。
  final ValueChanged<FontRecipe> onChanged;

  @override
  State<CharRulesScreen> createState() => _CharRulesScreenState();
}

class _CharRulesScreenState extends State<CharRulesScreen> {
  late FontRecipe _recipe = widget.recipe;

  SampleStore get store => widget.store;

  void _apply(FontRecipe recipe) {
    setState(() => _recipe = recipe);
    widget.onChanged(recipe);
  }

  /// 選び直せる字。書いた記録が 1 つでもあるものだけを出す。
  List<String> get _chars => [
    for (final charSet in _recipe.charSets)
      for (final char in charSet.chars)
        if (store.attemptCount(char) > 0) char,
  ];

  @override
  Widget build(BuildContext context) {
    final chars = _chars;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        title: const Text('字を選び直す'),
      ),
      body: SafeArea(
        child: chars.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'この版に入る字がまだありません。',
                    style: TextStyle(color: Color(0xff9c948a)),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '規則どおりでよければ、そのままで大丈夫です。\n'
                    '字を押すと、その字だけ別の日に書いたものへ差し替えられます。',
                    style: TextStyle(color: Color(0xff9c948a)),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final char in chars)
                        _CharChip(
                          char: char,
                          pinned: _recipe.charRules.containsKey(char),
                          versions: store.attemptCount(char),
                          onTap: () => _choose(char),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _choose(String char) async {
    final picked = await Navigator.of(context).push<_Pick>(
      MaterialPageRoute<_Pick>(
        builder: (context) => _VersionPicker(
          char: char,
          store: store,
          selected: _recipe.charRules[char],
        ),
      ),
    );
    if (picked == null) return;

    final charRules = {..._recipe.charRules};
    if (picked.sampleId == null) {
      charRules.remove(char);
    } else {
      charRules[char] = picked.sampleId!;
    }
    _apply(_recipe.copyWith(charRules: charRules));
  }
}

/// 選び直しの結果。`sampleId` が null なら規則へ戻す。
class _Pick {
  const _Pick(this.sampleId);

  final String? sampleId;
}

class _CharChip extends StatelessWidget {
  const _CharChip({
    required this.char,
    required this.pinned,
    required this.versions,
    required this.onTap,
  });

  final String char;
  final bool pinned;
  final int versions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 68,
      height: 68,
      child: Material(
        color: pinned ? scheme.primaryContainer : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: pinned ? scheme.primary : const Color(0xffe4dfd4),
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Text(
                  char,
                  style: const TextStyle(fontSize: 30, height: 1),
                ),
              ),
              // 差し替えている字だけ印を出す。
              if (pinned)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Icon(Icons.push_pin, size: 14, color: scheme.primary),
                )
              else if (versions > 1)
                Positioned(
                  right: 4,
                  bottom: 2,
                  child: Text(
                    '$versions',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff9c948a),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1 字ぶんの版を並べて選ばせる。
class _VersionPicker extends StatelessWidget {
  const _VersionPicker({
    required this.char,
    required this.store,
    required this.selected,
  });

  final String char;
  final SampleStore store;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    // 新しいものを先に出す。ふつうは直近から選ぶ。
    final refs = store.history(char, includeTraced: true).reversed.toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        title: Text('「$char」の版'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.rule),
              title: const Text('規則どおりにする'),
              subtitle: const Text('版の「いつの字を採るか」に任せる'),
              selected: selected == null,
              onTap: () => Navigator.of(context).pop(const _Pick(null)),
            ),
            const Divider(),
            for (final ref in refs)
              _VersionTile(
                ref: ref,
                store: store,
                selected: ref.id == selected,
                onTap: () => Navigator.of(context).pop(_Pick(ref.id)),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime time) =>
    '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.ref,
    required this.store,
    required this.selected,
    required this.onTap,
  });

  final SampleRef ref;
  final SampleStore store;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? scheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: SizedBox(
          width: 56,
          height: 56,
          child: FutureBuilder<Sample>(
            // 運筆は 1 件ずつ読む。一覧で全部を抱えない。
            future: store.read(ref.id),
            builder: (context, snapshot) {
              final sample = snapshot.data;
              if (sample == null) return const SizedBox.shrink();
              return StrokePreview(strokes: sample.strokes);
            },
          ),
        ),
        title: Text(formatDate(ref.writtenAt)),
        // 同じ日に何度も書くので、日付だけでは見分けが付かない。
        // 版を選ぶ手がかりは日付が主で、時刻は添えるだけにする。
        subtitle: Text(
          '${switch (ref.mode) {
            PracticeMode.trace => 'なぞって書いた',
            PracticeMode.copy => 'お手本を見て書いた',
            PracticeMode.free => '何も見ずに書いた',
          }} ・ ${_formatTime(ref.writtenAt)}',
        ),
        trailing: selected ? const Icon(Icons.check) : null,
      ),
    );
  }
}
