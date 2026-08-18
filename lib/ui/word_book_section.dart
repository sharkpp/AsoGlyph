import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../store/word_book_store.dart';
import '../word/word_book_codec.dart';

/// 単語帳の取り込みと片づけ（SPEC 7.4）。おうちの人の画面に置く。
///
/// 同梱の単語帳はそのまま使える。ここは、家の中の語（きょうだいの名前、
/// 好きなものの名前）を足すための入口。
class WordBookSection extends StatelessWidget {
  const WordBookSection({super.key, required this.books});

  final WordBookStore books;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: books,
      builder: (context, _) => Column(
        children: [
          for (final book in books.all)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                books.isImported(book.id)
                    ? Icons.menu_book
                    : Icons.auto_stories_outlined,
              ),
              title: Text(book.name),
              subtitle: Text('${book.words.length} 語'),
              // 同梱のものは消させない。消しても取り戻す導線が無い。
              trailing: books.isImported(book.id)
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '片づける',
                      onPressed: () => _remove(context, book.id, book.name),
                    )
                  : null,
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('単語帳を取り込む'),
            subtitle: const Text('YAML か、Excel で作った CSV（ことば・よみ・タグ の順）'),
            onTap: () => _import(context),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final file = await openFile(
      acceptedTypeGroups: [
        // 拡張子で絞る。web では uniformTypeIdentifiers が効かない。
        const XTypeGroup(label: '単語帳', extensions: ['yaml', 'yml', 'csv']),
      ],
    );
    if (file == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final book = parseWordBookFile(
        fileName: file.name,
        source: await file.readAsString(),
      );
      await books.add(book);
      messenger.showSnackBar(
        SnackBar(content: Text('「${book.name}」を取り込みました（${book.words.length} 語）')),
      );
    } on WordBookFormatException catch (error) {
      // 何が悪いのかを言う。直せない指摘は、直しようがないのと同じ。
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      debugPrint('単語帳の取り込みに失敗: $error');
      messenger.showSnackBar(const SnackBar(content: Text('この単語帳は読み込めません')));
    }
  }

  Future<void> _remove(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「$name」を片づけますか？'),
        // 単語帳は供給源でしかない。ここが誤解されると片づけるのが怖くなる。
        content: const Text('書いた字も、書き終えた語の記録も消えません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('片づける'),
          ),
        ],
      ),
    );
    if (ok ?? false) await books.remove(id);
  }
}
