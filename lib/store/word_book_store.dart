import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../model/word.dart';
import '../word/word_book_codec.dart';

/// 単語帳の置き場（SPEC 7.4）。
///
/// 同梱の単語帳と、親が取り込んだものを同じ並びで扱う。単語帳は「練習用の
/// 文字列の供給源」であって書いた記録ではないので、人ごとには分けない。
/// 兄弟で同じ単語帳を使う。
class WordBookStore extends ChangeNotifier {
  WordBookStore(this._db);

  static Future<WordBookStore> open(Database db) async {
    final store = WordBookStore(db);
    await store.load();
    return store;
  }

  /// 同梱の単語帳。ここに並べた順に出る。
  ///
  /// 資産の一覧を実行時に引かない。増やすときはこの並びに足す。
  static const _bundled = [
    'assets/words/hiragana.yaml',
    'assets/words/katakana.yaml',
    'assets/words/digits.yaml',
  ];

  static final _books = stringMapStoreFactory.store('wordBooks');

  final Database _db;

  final List<WordBook> _all = [];

  /// 同梱のものが先、取り込んだものがうしろ。
  List<WordBook> get all => List.unmodifiable(_all);

  /// 取り込んだ単語帳か。同梱のものは消させない。
  bool isImported(String id) => !_bundled.contains(id);

  Future<void> load() async {
    _all.clear();
    for (final path in _bundled) {
      _all.add(
        parseWordBookYaml(
          await rootBundle.loadString(path),
          id: path,
          fallbackName: path,
        ),
      );
    }
    for (final record in await _books.find(
      _db,
      finder: Finder(sortOrders: [SortOrder('addedAt')]),
    )) {
      _all.add(_decode(record.key, record.value));
    }
    notifyListeners();
  }

  /// 取り込んだ単語帳を残す。
  Future<WordBook> add(WordBook book) async {
    final saved = WordBook(
      id: const Uuid().v7(),
      name: book.name,
      words: book.words,
    );
    await _books.record(saved.id).put(_db, {
      'name': saved.name,
      'addedAt': DateTime.now().millisecondsSinceEpoch,
      'words': [
        for (final word in saved.words)
          {'text': word.text, 'reading': word.reading, 'tags': word.tags},
      ],
    });
    _all.add(saved);
    notifyListeners();
    return saved;
  }

  /// 取り込んだ単語帳を消す。書いた記録は消えない（SPEC 4.1）。
  Future<void> remove(String id) async {
    if (!isImported(id)) return;
    await _books.record(id).delete(_db);
    _all.removeWhere((book) => book.id == id);
    notifyListeners();
  }

  WordBook _decode(String id, Map<String, Object?> record) => WordBook(
    id: id,
    name: record['name']! as String,
    words: [
      for (final word in (record['words']! as List).cast<Map<String, Object?>>())
        Word(
          text: word['text']! as String,
          reading: word['reading']! as String,
          tags: (word['tags'] as List? ?? const []).cast<String>(),
        ),
    ],
  );
}
