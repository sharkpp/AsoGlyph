import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../export/font_export.dart';
import '../model/char_set.dart';
import '../model/word.dart';
import '../store/word_book_store.dart';
import '../word/reading.dart';
import '../word/word_book_export.dart';
import '../word/word_image.dart';
import 'file_types.dart';
import 'reading_input.dart';
import 'word_book_section.dart';
import 'word_image_view.dart';

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
          // 内蔵は直せない。名前も語も、消すこともできない。
          if (!_book.isBundled)
            IconButton(
              icon: const Icon(Icons.drive_file_rename_outline),
              tooltip: '名前を変える',
              onPressed: _rename,
            ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '書き出す',
            onPressed: _export,
          ),
          if (!_book.isBundled)
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
            if (_book.isBundled) _buildBundledNote(),
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
                books: widget.books,
                onEdit: _book.isBundled ? null : () => _editWord(index),
                onRemove: _book.isBundled ? null : () => _removeWord(index),
              ),
            const SizedBox(height: 8),
            if (!_book.isBundled)
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

  /// 内蔵だと分かるようにし、直したい人をコピーへ導く。
  Widget _buildBundledNote() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xfff2efe8),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _book.isDebugBook
                  ? 'これは動作確認用の辞書です'
                  : 'これはアプリに入っている単語帳です',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _book.isDebugBook
                  ? '手元でだけ読み込まれます。配るアプリには入りません。'
                  : '直したり消したりはできません。要らない人にはチェックを '
                        '外してください。語を足したいときはコピーを作ります。',
              style: const TextStyle(color: Color(0xff6f665c)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('コピーを作る'),
            ),
          ],
        ),
      ),
    );
  }

  /// 直せるコピーを作って、そのまま開く。
  Future<void> _copy() async {
    final name = await askWordBookName(
      context,
      title: 'コピーの名前',
      initial: '${_book.name} のコピー',
    );
    if (name == null) return;
    final copy = await widget.books.copy(_book, name: name);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => WordBookEditor(book: copy, books: widget.books),
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
    final word = await _askWord(context, books: widget.books);
    if (word == null) return;
    await _update(_book.copyWith(words: [..._book.words, word]));
  }

  Future<void> _editWord(int index) async {
    final word = await _askWord(
      context,
      books: widget.books,
      initial: _book.words[index],
    );
    if (word == null) return;
    final words = [..._book.words]..[index] = word;
    await _update(_book.copyWith(words: words));
  }

  /// 単語帳を持ち出す（SPEC 7.4）。
  ///
  /// 絵を入れている単語帳では、YAML 1 枚だと絵が落ちる。どちらを出すかは
  /// 使い道で変わる（人に渡すなら絵ごと、自分で直すなら YAML）ので選ばせる。
  Future<void> _export() async {
    final withImages = _book.words.any((word) => word.image != null);
    final bundle = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('どの形で書き出しますか', style: TextStyle(fontSize: 18)),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('単語帳ファイル（.asodict）'),
              subtitle: const Text('絵ごと 1 つのファイルにまとめます'),
              onTap: () => Navigator.of(context).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('YAML'),
              subtitle: Text(
                withImages
                    ? '文字だけ。絵は入りません'
                    : 'テキストエディタで直せます',
              ),
              onTap: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (bundle == null) return;

    final name = sanitizeFileName(_book.name);
    if (bundle) {
      await shareBytes(
        bytes: await encodeWordBookBundle(_book, widget.books.readImage),
        fileName: '$name.$wordBookBundleExtension',
        mimeType: 'application/zip',
        text: 'あそんでフォントの単語帳',
      );
    } else {
      await shareBytes(
        bytes: Uint8List.fromList(utf8.encode(encodeWordBookYaml(_book))),
        fileName: '$name.yaml',
        mimeType: 'text/yaml',
        text: 'あそんでフォントの単語帳',
      );
    }
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
    required this.books,
    required this.onEdit,
    required this.onRemove,
  });

  final Word word;
  final WordBookStore books;

  /// 内蔵の単語帳では null。見るだけになる。
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final unwritable = unwritableChars(word);
    final image = word.image;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: image == null
            ? const Icon(Icons.image_outlined, color: Color(0xffbdb4a6))
            : WordImageView(image: image, books: books, size: 48),
      ),
      title: Text.rich(
        TextSpan(
          children: [
            for (final part in word.segments)
              TextSpan(
                text: part.text,
                style: TextStyle(
                  color: part.given ? const Color(0xff9c948a) : null,
                ),
              ),
          ],
        ),
        style: const TextStyle(fontSize: 20),
      ),
      subtitle: Text(
        unwritable.isEmpty
            ? word.reading
            : '${word.reading} ・ ${unwritable.join()} はまだ集められません',
        style: TextStyle(
          color: unwritable.isEmpty ? null : const Color(0xffc4553c),
        ),
      ),
      onTap: onEdit,
      trailing: onRemove == null
          ? null
          : IconButton(
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

/// ことばと読みと絵を聞く。
Future<Word?> _askWord(
  BuildContext context, {
  required WordBookStore books,
  Word? initial,
}) => showDialog<Word>(
  context: context,
  builder: (context) => _WordDialog(books: books, initial: initial),
);

class _WordDialog extends StatefulWidget {
  const _WordDialog({required this.books, this.initial});

  final WordBookStore books;
  final Word? initial;

  @override
  State<_WordDialog> createState() => _WordDialogState();
}

class _WordDialogState extends State<_WordDialog> {
  late final _text = TextEditingController(text: widget.initial?.text ?? '');
  late final _reading = TextEditingController(
    text: widget.initial?.reading ?? '',
  );
  late String? _image = widget.initial?.image;

  /// 絵を落とそうとしているか。落とし先がどこかを目で分かるようにする。
  var _dropping = false;

  /// いま書かせることになる字。かっこの外だけ。
  List<String> get _writable =>
      Word(text: _text.text.trim(), reading: '').chars;

  @override
  void dispose() {
    _text.dispose();
    _reading.dispose();
    super.dispose();
  }

  /// 絵を選ぶ（SPEC 7.4）。
  Future<void> _pickImage() async {
    final file = await openFile(
      acceptedTypeGroups: [imageTypeGroup],
    );
    if (file == null || !mounted) return;
    await _accept(await file.readAsBytes(), file.name);
  }

  /// 落とされた絵を受ける（SPEC 7.4）。
  ///
  /// 親は絵をファイルとして持っている。選ぶ画面を開いて探し直すより、
  /// そのまま落とせるほうが早い。
  ///
  /// 落とせるのは web とデスクトップだけ。iOS・Android では [DropTarget] が
  /// 何もしないので、「絵を選ぶ」がそのまま唯一の道になる。
  Future<void> _acceptDrop(DropDoneDetails details) async {
    // まとめて落とされても、語に付く絵は 1 つ。最初のものだけ受ける。
    final file = details.files.firstOrNull;
    if (file == null) return;
    await _accept(await file.readAsBytes(), file.name);
  }

  /// 大きすぎる絵は断る。縮めない。勝手に縮めると、親が選んだ絵と出てくる絵が
  /// 違うものになる。何 KB あったかを見せて、選び直してもらう。
  Future<void> _accept(Uint8List bytes, String fileName) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    if (!isSupportedImage(fileName)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('入れられるのは PNG・JPEG・WebP・SVG です')),
      );
      return;
    }
    if (bytes.length > maxImageBytes) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'この絵は ${describeSize(bytes.length)} あります。'
            '${describeSize(maxImageBytes)} までの絵を選んでください',
          ),
        ),
      );
      return;
    }

    final id = await widget.books.addImage(bytes, fileName: fileName);
    if (mounted) setState(() => _image = id);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;

    return AlertDialog(
      title: Text(widget.initial == null ? 'ことばを足す' : 'ことばを直す'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'ことば',
                hintText: 'ねこ',
                // 長い名前ぜんぶを書かせると 1 セッションで終わらない。
                helperText: '[かっこ] の中は出しておくだけで、書かせません',
              ),
            ),
            if (_writable.isEmpty && _text.text.trim().isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'ぜんぶ かっこの中です。書かせる字がありません',
                  style: TextStyle(fontSize: 12, color: Color(0xffc4553c)),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _reading,
              // 打っている手元で直す。決めたあとに黙って直すと、自分が
              // 打ったものと違うものが残ったように見える。
              inputFormatters: const [ReadingInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'よみ',
                // 読みを必須にするのは、子供が読めない語を出さないため（SPEC 7.4）。
                helperText: '声で読み上げます。ひらがなで（カタカナは直ります）',
              ),
            ),
            const SizedBox(height: 16),
            DropTarget(
              onDragEntered: (_) => setState(() => _dropping = true),
              onDragExited: (_) => setState(() => _dropping = false),
              onDragDone: (details) async {
                setState(() => _dropping = false);
                await _acceptDrop(details);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _dropping
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _dropping
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xffe4dfd4),
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: image == null
                          ? const Icon(
                              Icons.image_outlined,
                              size: 40,
                              color: Color(0xffbdb4a6),
                            )
                          : WordImageView(
                              image: image,
                              books: widget.books,
                              size: 64,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(image == null ? '絵を選ぶ' : '絵を変える'),
                          ),
                          if (image != null)
                            TextButton(
                              onPressed: () => setState(() => _image = null),
                              child: const Text('絵を外す'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              // 字が読めない子は、絵でしか語を選べない。
              '絵があると、字が読めなくても自分で語を選べます。'
              'ここに絵を落としても入ります。${describeSize(maxImageBytes)} まで。',
              style: const TextStyle(fontSize: 12, color: Color(0xff9c948a)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: () {
            final word = _text.text.trim();
            // 書かせる字が 1 つも無い語は、練習に出しようがない。
            if (word.isEmpty || _writable.isEmpty) return;
            // 読みを書かなかったら、ことばをそのまま読む。かなの語では
            // それで足りるし、ここで止めると入力が進まない。かっこは外し、
            // カタカナはひらがなに直したものを読みにする。
            final how = _reading.text.trim();
            Navigator.of(context).pop(
              Word(
                text: word,
                reading: how.isEmpty
                    ? toReading(Word(text: word, reading: '').display)
                    : how,
                tags: widget.initial?.tags ?? const [],
                image: _image,
              ),
            );
          },
          child: const Text('決める'),
        ),
      ],
    );
  }
}
