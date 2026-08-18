import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../kanjivg/stroke_order.dart';
import '../model/sample.dart';
import '../model/word.dart';
import '../practice/question_picker.dart';
import '../store/session.dart';
import '../store/word_book_store.dart';
import 'practice_session.dart';
import 'word_image_view.dart';

/// 単語で練習する画面（SPEC 7.4）。
///
/// 単語帳は「練習用の文字列の供給源」であって、意味を教えるためのものでは
/// ない。ここで選んだ語を 1 字ずつ書いていく。
class WordScreen extends StatelessWidget {
  const WordScreen({
    super.key,
    required this.session,
    required this.speaker,
    required this.strokeOrders,
    required this.mode,
  });

  final Session session;
  final Speaker speaker;
  final StrokeOrderLibrary strokeOrders;
  final PracticeMode mode;

  WordBookStore get books => session.books;

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
    // 出すのはその人に割り振られた単語帳だけ（SPEC 7.4）。
    final writable = writableWords(session.current, books.all).map(
      (word) => word.text,
    ).toSet();
    final shown = [
      for (final book in books.all)
        if (session.current.uses(book.id))
          (book, book.words.where((word) => writable.contains(word.text)).toList()),
    ].where((entry) => entry.$2.isNotEmpty).toList();

    if (shown.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'いま書ける語がありません。\n'
            'おうちの人の画面で、使う単語帳か集める文字種を足してください。',
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
                  books: books,
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

/// 一覧に並ぶ 1 語。押すとその語の書き取りに入る。
class _WordTile extends StatelessWidget {
  const _WordTile({
    required this.word,
    required this.books,
    required this.done,
    required this.onTap,
  });

  final Word word;
  final WordBookStore books;

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 字が読めない子は、絵でしか語を選べない（SPEC 7.4）。
              // 字の上に大きく置く。並びは崩れない（横に伸びず縦に伸びる）。
              if (word.image != null) ...[
                WordImageView(image: word.image!, books: books, size: 120),
                const SizedBox(height: 4),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // かっこの中は、書かない字なので薄く出す（SPEC 7.4）。
                  // どこを書くのかが、選ぶ前に分かるようにする。
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final part in word.segments)
                          TextSpan(
                            text: part.text,
                            style: TextStyle(
                              color: part.given
                                  ? const Color(0xff9c948a)
                                  : done
                                  ? scheme.onPrimaryContainer
                                  : const Color(0xff6f665c),
                            ),
                          ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 28, height: 1.2),
                  ),
                  if (done) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.star, size: 16, color: scheme.primary),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
