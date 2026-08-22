import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../model/word.dart';
import '../practice/question_picker.dart';
import '../store/session.dart';
import '../store/word_book_store.dart';
import '../word/word_image.dart' show extensionOf;
import '../word/word_book_codec.dart';
import '../word/word_book_export.dart';
import '../word/word_book_fetch.dart';
import 'file_types.dart';
import 'word_book_editor.dart';

/// 単語帳の割り振りと手入れ（SPEC 7.4）。おうちの人の画面に置く。
///
/// 単語帳そのものは、みんなで使う 1 つの束。分けるのは「誰にどれを出すか」だけ。
/// 上の子には漢字入りの語、下の子にはひらがなの語、という使い分けができる。
class WordBookSection extends StatelessWidget {
  const WordBookSection({super.key, required this.session});

  final Session session;

  WordBookStore get books => session.books;

  @override
  Widget build(BuildContext context) {
    final user = session.current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${user.displayName} に出す単語帳を選びます。'
          '単語帳そのものは、みんなで使う 1 つです。',
          style: const TextStyle(color: Color(0xff9c948a)),
        ),
        for (final book in books.all)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: user.uses(book.id),
            onChanged: (on) => _toggle(book.id, on ?? false),
            // 概要を出すと 2 行になる。言わないと行がはみ出す。
            isThreeLine: book.description != null,
            title: Row(
              children: [
                Flexible(child: Text(book.name)),
                // アプリに入っているものだと分かるようにする。直せない・
                // 消せないのが、名前だけでは伝わらない。
                if (book.isBundled) ...[
                  const SizedBox(width: 8),
                  _Badge(
                    label: book.isDebugBook ? '動作確認用' : '内蔵',
                    warn: book.isDebugBook,
                  ),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 語の数と作った人。単語帳はいくつでも作れて人にも渡せるので、
                // 名前だけでは一覧で見分けが付かない。
                Text(
                  book.author == null
                      ? '${book.words.length} 語'
                      : '${book.words.length} 語 ・ ${book.author}',
                ),
                if (book.description != null)
                  Text(
                    book.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xff9c948a)),
                  ),
              ],
            ),
            secondary: IconButton(
              icon: Icon(
                book.isBundled ? Icons.visibility_outlined : Icons.edit_outlined,
              ),
              tooltip: book.isBundled ? 'ことばを見る' : 'ことばを直す',
              onPressed: () => _edit(context, book),
            ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.add),
          title: const Text('単語帳を作る'),
          subtitle: const Text('「どうぶつ」「うちのことば」など、いくつでも'),
          onTap: () => _create(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('単語帳を取り込む'),
          subtitle: const Text(
            '単語帳ファイル（.asodict）・YAML・Excel で作った CSV',
          ),
          onTap: () => _import(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.link),
          title: const Text('URL から取り込む'),
          // 渡す側が置き場に上げてあるなら、落としてから選ぶより早い。
          subtitle: const Text('置いてある単語帳を、落とさずに取り込みます'),
          onTap: () => _importUrl(context),
        ),
      ],
    );
  }

  /// この人に出す単語帳を切り替える。最後の 1 つは外させない。
  ///
  /// 全部外すと、おまかせも ことば も子供の画面から消える（SPEC 7.3）。
  Future<void> _toggle(String id, bool on) async {
    final user = session.current;
    final using = {
      for (final book in books.all)
        if (user.uses(book.id)) book.id,
    };
    if (on) {
      using.add(id);
    } else {
      if (using.length <= 1) return;
      using.remove(id);
    }
    await session.users.save(user.copyWith(wordBooks: using));
  }

  Future<void> _edit(BuildContext context, WordBook book) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WordBookEditor(book: book, books: books),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await askWordBookName(context, title: '単語帳の名前');
    if (name == null) return;
    final book = await books.add(WordBook(id: '', name: name, words: const []));
    // 作ったらそのまま語を足せるようにする。空の単語帳だけ残っても使えない。
    if (context.mounted) await _edit(context, book);
  }

  Future<void> _import(BuildContext context) async {
    // web では種類で絞らない。絞ると Safari で単語帳が選べなくなる
    // （lib/ui/file_types.dart）。
    final file = await openFile(acceptedTypeGroups: wordBookTypeGroups);
    if (file == null || !context.mounted) return;

    await _take(context, () => _read(file));
  }

  /// URL から取り込む（SPEC 7.4.1）。
  Future<void> _importUrl(BuildContext context) async {
    final url = await _askUrl(context);
    if (url == null || !context.mounted) return;

    await _take(context, () async {
      final fetched = await fetchWordBook(url);
      return fetched.isBundle
          ? books.importBundle(
              fetched.bytes!,
              name: _withoutExtension(fetched.fileName),
            )
          : books.importText(fetched.text!, fileName: fetched.fileName);
    });
  }

  /// 取り込みの結末を出す。入口（ファイル・URL）で変わらない。
  Future<void> _take(
    BuildContext context,
    Future<WordBook> Function() read,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final book = await read();
      messenger.showSnackBar(
        SnackBar(
          content: Text('「${book.name}」を取り込みました（${book.words.length} 語）'),
        ),
      );
    } on WordBookFormatException catch (error) {
      // 何が悪いのかを言う。直せない指摘は、直しようがないのと同じ。
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      debugPrint('単語帳の取り込みに失敗: $error');
      messenger.showSnackBar(const SnackBar(content: Text('この単語帳は読み込めません')));
    }
  }

  /// 取り込んだファイルを単語帳にする。読み方は拡張子で決める。
  Future<WordBook> _read(XFile file) async =>
      extensionOf(file.name) == wordBookBundleExtension
      ? books.importBundle(
          await file.readAsBytes(),
          name: _withoutExtension(file.name),
        )
      : books.importText(await file.readAsString(), fileName: file.name);
}

/// 単語帳の名前にするために拡張子を落とす。
String _withoutExtension(String fileName) =>
    fileName.replaceAll(RegExp(r'\.[^.]*$'), '');

/// URL を聞く。
Future<String?> _askUrl(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('URL から取り込む'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'URL',
          hintText: 'https://example.com/どうぶつ.yaml',
          helperText: '単語帳ファイル（.asodict）・YAML・CSV を指す URL',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('取り込む'),
        ),
      ],
    ),
  ).then((value) => (value == null || value.isEmpty) ? null : value);
}

/// 「内蔵」「動作確認用」の印。
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.warn});

  final String label;

  /// 配るものには入らない辞書。目立たせて、混ぜたままにしない。
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final color = warn ? const Color(0xffc4553c) : const Color(0xff7a8f6a);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}

/// 語に出てこない字を親に見せる（SPEC 7.6）。
///
/// おまかせは語で出すので、ここに挙がった字はその導線では出てこない。
/// 語を足すか、一覧から直に選ばせることになる。
class MissingCharsSection extends StatelessWidget {
  const MissingCharsSection({super.key, required this.session});

  final Session session;

  WordBookStore get books => session.books;

  @override
  Widget build(BuildContext context) {
    final missing = charsMissingFromWords(session.current, books.all);

    if (missing.isEmpty) {
      return const Text(
        'いま集めている字は、ぜんぶ ことばの中に出てきます。',
        style: TextStyle(color: Color(0xff9c948a)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'この ${missing.length} 字は、いま使っている単語帳のどの語にも出てきません。'
          'おまかせでは出ないので、語を足すか、子供の画面の一覧から選ばせてください。',
          style: const TextStyle(color: Color(0xff9c948a)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final char in missing)
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xffe4dfd4), width: 2),
                ),
                child: Text(
                  char,
                  style: const TextStyle(fontSize: 20, height: 1),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 単語帳の名前・作成者・概要（SPEC 7.4）。
class WordBookDetails {
  const WordBookDetails({required this.name, this.author, this.description});

  final String name;

  /// 書かれていなければ null。空文字は持たない。
  final String? author;
  final String? description;
}

/// 名前と、作った人（＝著作権者）と、概要を聞く。
///
/// 作った人と概要は任意。単語帳は人に渡せる（SPEC 7.4.1）ので、渡った先で
/// 出どころと中身が分かるようにするためのもので、自分だけで使うぶんには
/// 要らない。名前だけは空にできない（一覧で指すものが無くなる）。
Future<WordBookDetails?> askWordBookDetails(
  BuildContext context, {
  required WordBook book,
}) => showDialog<WordBookDetails>(
  context: context,
  builder: (context) => _DetailsDialog(book: book),
);

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.book});

  final WordBook book;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final _name = TextEditingController(text: widget.book.name);
  late final _author = TextEditingController(
    text: widget.book.author ?? '',
  );
  late final _description = TextEditingController(
    text: widget.book.description ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _author.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('この単語帳のこと'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '名前',
                hintText: 'どうぶつ',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _author,
              decoration: const InputDecoration(
                labelText: '作成者',
                hintText: 'おかあさん',
                // 単語帳は人に渡せる。渡った先で出どころが消えないようにする。
                helperText: '作った人。書き出したファイルにも残ります',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              // 1 行に収まらないことのほうが多い。
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: '概要',
                hintText: '4 歳向け。ひらがなだけで書ける語',
                helperText: 'どういう単語帳か。一覧にも出ます',
              ),
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
            final name = _name.text.trim();
            // 名前の無い単語帳は、一覧で指すものが無くなる。
            if (name.isEmpty) return;
            final author = _author.text.trim();
            final description = _description.text.trim();
            Navigator.of(context).pop(
              WordBookDetails(
                name: name,
                author: author.isEmpty ? null : author,
                description: description.isEmpty ? null : description,
              ),
            );
          },
          child: const Text('決める'),
        ),
      ],
    );
  }
}

/// 単語帳の名前を聞く。作るときとコピーを作るときに使う。
///
/// 作った人と概要はここでは聞かない。作る前に聞くと、語を 1 つも入れる前に
/// 書かせることになる。あとから単語帳の画面で足せる（[askWordBookDetails]）。
Future<String?> askWordBookName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'どうぶつ'),
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
