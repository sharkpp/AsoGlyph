import 'package:flutter/material.dart';

import '../model/word.dart';
import '../store/session.dart';
import 'admin_screen.dart' show formatDate;

/// 書いたことばの記録（SPEC 4.2）。おうちの人の画面に置く。
///
/// 消せるのは「この語を書き終えた」という印だけ。**書いた字は消えない**
/// （SPEC 4.1）。星が付いたままだと、もう一度書かせたい語を子供が選ばなくなる。
class WordHistorySection extends StatelessWidget {
  const WordHistorySection({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final history = session.attempts.byWord;

    if (history.isEmpty) {
      return const Text(
        'まだ、ことばを最後まで書いた記録はありません。',
        style: TextStyle(color: Color(0xff9c948a)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '消えるのは「書けた」という印だけです。書いた字は消えません。',
          style: TextStyle(color: Color(0xff9c948a)),
        ),
        for (final entry in history)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              // かっこは外して見せる。書かせない字は入っていない。
              Word(text: entry.word, reading: '').display,
              style: const TextStyle(fontSize: 18),
            ),
            subtitle: Text(
              '${entry.count} 回 ・ ${formatDate(entry.lastAt)}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'この ことばの記録を消す',
              onPressed: () => session.attempts.removeWord(entry.word),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _clear(context),
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('ぜんぶ消す'),
        ),
      ],
    );
  }

  Future<void> _clear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${session.current.displayName} の記録を消しますか？'),
        content: const Text(
          '「このことばを書けた」という印だけを消します。'
          '集めた字も版も消えません。',
        ),
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
    if (ok ?? false) await session.attempts.clear();
  }
}
