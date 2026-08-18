import 'package:flutter/material.dart';

import '../model/char_set.dart';
import '../model/word.dart';
import '../store/word_book_store.dart';
import 'word_book_section.dart';

/// 単語帳を直す画面（SPEC 7.4）。
///
/// 変えたその場で保存する。「保存」ボタンは置かない（SPEC 7.6 の版と同じ）。
/// 押し忘れで語が消える導線を作らない。
class WordBookEditor extends StatefulWidget {
  const WordBookEditor({super.key, required this.book, required this.books});

  final WordBook book;
  final WordBookStore books;

  @override
  State<WordBookEditor> createState() => _WordBookEditorState();
}

class _WordBookEditorState extends State<WordBookEditor> {
  late var _book = widget.book;

  Future<void> _update(WordBook next) async {
    setState(() => _book = next);
    await widget.books.save(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        title: Text(_book.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: '名前を変える',
            onPressed: _rename,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'この単語帳を消す',
            onPressed: _remove,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_book.words.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'まだ ことばがありません。\n'
                  '「ことばを足す」で、書かせたい語を入れてください。',
                  style: TextStyle(color: Color(0xff9c948a)),
                ),
              ),
            for (final (index, word) in _book.words.indexed)
              _WordRow(
                word: word,
                onEdit: () => _editWord(index),
                onRemove: () => _removeWord(index),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: _addWord,
              icon: const Icon(Icons.add),
              label: const Text('ことばを足す'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename() async {
    final name = await askWordBookName(
      context,
      title: '単語帳の名前',
      initial: _book.name,
    );
    if (name == null) return;
    await _update(_book.copyWith(name: name));
  }

  Future<void> _addWord() async {
    final word = await _askWord(context);
    if (word == null) return;
    await _update(_book.copyWith(words: [..._book.words, word]));
  }

  Future<void> _editWord(int index) async {
    final word = await _askWord(context, initial: _book.words[index]);
    if (word == null) return;
    final words = [..._book.words]..[index] = word;
    await _update(_book.copyWith(words: words));
  }

  Future<void> _removeWord(int index) async {
    final words = [..._book.words]..removeAt(index);
    await _update(_book.copyWith(words: words));
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「${_book.name}」を消しますか？'),
        // 単語帳は供給源でしかない。ここが誤解されると消すのが怖くなる。
        content: const Text('書いた字も、書き終えた語の記録も消えません。'),
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
    if (!(ok ?? false)) return;
    await widget.books.remove(_book.id);
    if (mounted) Navigator.of(context).pop();
  }
}

class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.word,
    required this.onEdit,
    required this.onRemove,
  });

  final Word word;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final unwritable = unwritableChars(word);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(word.text, style: const TextStyle(fontSize: 20)),
      subtitle: Text(
        unwritable.isEmpty
            ? word.reading
            : '${word.reading} ・ ${unwritable.join()} はまだ集められません',
        style: TextStyle(
          color: unwritable.isEmpty ? null : const Color(0xffc4553c),
        ),
      ),
      onTap: onEdit,
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'この ことばを消す',
        onPressed: onRemove,
      ),
    );
  }
}

/// この語のうち、どの文字種にも入っていない字（SPEC 5）。
///
/// 漢字（L5）を含む語を先に入れておくことはできるが、いま出せないことは
/// 見えていないと困る。集める文字種から外しているだけの字は、ここには挙げない。
List<String> unwritableChars(Word word) => [
  for (final char in word.chars)
    if (charSetOf(char) == null) char,
];

/// ことばと読みを聞く。
Future<Word?> _askWord(BuildContext context, {Word? initial}) {
  final text = TextEditingController(text: initial?.text ?? '');
  final reading = TextEditingController(text: initial?.reading ?? '');

  return showDialog<Word>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initial == null ? 'ことばを足す' : 'ことばを直す'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: text,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'ことば',
              hintText: 'ねこ',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: reading,
            decoration: const InputDecoration(
              labelText: 'よみ',
              // 読みを必須にするのは、子供が読めない語を出さないため（SPEC 7.4）。
              helperText: '声で読み上げます。書けなくても、聞けば分かるように',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: () {
            final word = text.text.trim();
            if (word.isEmpty) return;
            // 読みを書かなかったら、ことばをそのまま読む。かなの語では
            // それで足りるし、ここで止めると入力が進まない。
            final how = reading.text.trim();
            Navigator.of(context).pop(
              Word(text: word, reading: how.isEmpty ? word : how),
            );
          },
          child: const Text('決める'),
        ),
      ],
    ),
  );
}
