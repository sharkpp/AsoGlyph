import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../model/word.dart';
import '../practice/question_picker.dart';
import '../store/session.dart';
import '../store/word_book_store.dart';
import '../word/word_image.dart';
import '../word/word_book_codec.dart';
import '../word/word_book_export.dart';
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
    final missing = books.bundledMissing;

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
            title: Text(book.name),
            subtitle: Text('${book.words.length} 語'),
            secondary: IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'ことばを直す',
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
        // 消したものを取り戻す道を残しておく。消せるのに戻せないと、親は
        // 消すのをためらう。
        if (missing.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restore),
            title: const Text('はじめの単語帳を入れ直す'),
            subtitle: Text('${missing.length} 冊ぶん'),
            onTap: () => _restore(context),
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
    final file = await openFile(
      acceptedTypeGroups: [
        // 拡張子で絞る。web では uniformTypeIdentifiers が効かない。
        const XTypeGroup(
          label: '単語帳',
          extensions: [wordBookBundleExtension, 'yaml', 'yml', 'csv'],
        ),
      ],
    );
    if (file == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final book = await _read(file);
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

  /// 取り込んだファイルを単語帳にする。
  ///
  /// 単語帳ファイルだけは絵が入っているので、先に絵を端末へ入れてから、
  /// 語の指す先を端末の中の id に付け替える。
  Future<WordBook> _read(XFile file) async {
    if (extensionOf(file.name) != wordBookBundleExtension) {
      return books.add(
        parseWordBookFile(
          fileName: file.name,
          source: await file.readAsString(),
        ),
      );
    }

    final bundle = parseWordBookBundle(
      await file.readAsBytes(),
      name: file.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
    );
    final ids = <String, String>{};
    for (final entry in bundle.images.entries) {
      // 大きすぎる絵は入れない。取り込みでも同じ物差しで測る。
      if (entry.value.length > maxImageBytes) continue;
      ids[entry.key] = await books.addImage(
        entry.value,
        fileName: entry.key,
      );
    }
    return books.add(
      bundle.book.copyWith(
        words: [
          for (final word in bundle.book.words)
            word.image == null
                ? word
                : ids[word.image!] == null
                ? word.withoutImage()
                : word.copyWith(image: ids[word.image!]),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final added = await books.restoreBundled();
    messenger.showSnackBar(
      SnackBar(content: Text('${added.length} 冊を入れ直しました')),
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

/// 単語帳の名前を聞く。
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
