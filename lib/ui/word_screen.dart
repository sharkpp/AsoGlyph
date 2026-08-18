import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../kanjivg/stroke_order.dart';
import '../model/sample.dart';
import '../model/word.dart';
import '../store/session.dart';
import '../store/word_book_store.dart';
import 'writing_screen.dart';

/// 単語で練習する画面（SPEC 7.4）。
///
/// 単語帳は「練習用の文字列の供給源」であって、意味を教えるためのものでは
/// ない。ここで選んだ語を 1 字ずつ書いていく。
class WordScreen extends StatelessWidget {
  const WordScreen({
    super.key,
    required this.session,
    required this.books,
    required this.speaker,
    required this.strokeOrders,
    required this.mode,
  });

  final Session session;
  final WordBookStore books;
  final Speaker speaker;
  final StrokeOrderLibrary strokeOrders;
  final PracticeMode mode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        leading: IconButton(
          iconSize: 32,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('ことば'),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([books, session.attempts, session]),
          builder: (context, _) => _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final writable = writableChars(session);
    final shown = [
      for (final book in books.all)
        (book, book.words.where((word) => word.isWritable(writable)).toList()),
    ].where((entry) => entry.$2.isNotEmpty).toList();

    if (shown.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'いま集めている文字種で書ける語がありません。\n'
            'おうちの人の画面で、集める文字種を足すか単語帳を取り込んでください。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xff9c948a)),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (book, words) in shown) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              book.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in words)
                _WordTile(
                  word: word,
                  done: session.attempts.countOf(word.text) > 0,
                  onTap: () => practiceWord(
                    context,
                    word: word,
                    mode: mode,
                    session: session,
                    speaker: speaker,
                    strokeOrders: strokeOrders,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

/// いま集めている文字種の字ぜんぶ。
///
/// これに無い字を含む語は出さない（SPEC 7.4）。書けない字が 1 つ混じると、
/// その語は最後まで書けない。
Set<String> writableChars(Session session) => {
  for (final charSet in session.current.visibleCharSets) ...charSet.chars,
};

/// 語を 1 字ずつ書かせる（SPEC 7.4）。
///
/// 最後まで書けたら単語トライアルとして残す（SPEC 4.2）。途中でやめたときは
/// 残さない。書いた字そのものは 1 字ずつ記録に入っているので、何も失われない。
Future<void> practiceWord(
  BuildContext context, {
  required Word word,
  required PracticeMode mode,
  required Session session,
  required Speaker speaker,
  required StrokeOrderLibrary strokeOrders,
}) async {
  final sampleIds = <String>[];

  for (final (index, char) in word.chars.indexed) {
    // 続けて押されて画面ごと閉じられていたら、そこで終わる。
    if (!context.mounted) return;
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => WritingScreen(
          char: char,
          mode: mode,
          store: session.samples,
          speaker: speaker,
          strokeOrder: strokeOrders[char],
          steps: WritingSteps(
            chars: word.chars,
            index: index,
            reading: word.reading,
          ),
        ),
      ),
    );
    // 書かずに閉じた。やめたところで打ち切る。
    if (id == null) return;
    sampleIds.add(id);
  }

  await session.attempts.finish(word: word.text, sampleIds: sampleIds);
  await speaker.speak('${word.reading}、かけたね！');
}

/// 一覧に並ぶ 1 語。押すとその語の書き取りに入る。
class _WordTile extends StatelessWidget {
  const _WordTile({
    required this.word,
    required this.done,
    required this.onTap,
  });

  final Word word;

  /// 最後まで書けたことがあるか。
  final bool done;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: done ? scheme.primaryContainer : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: done ? scheme.primary : const Color(0xffe4dfd4),
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          // タップターゲットは 64dp 以上（SPEC 9）。
          constraints: const BoxConstraints(minWidth: 96, minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word.text,
                style: TextStyle(
                  fontSize: 28,
                  height: 1.2,
                  color: done
                      ? scheme.onPrimaryContainer
                      : const Color(0xff6f665c),
                ),
              ),
              if (done) ...[
                const SizedBox(width: 6),
                Icon(Icons.star, size: 16, color: scheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
