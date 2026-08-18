import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sembast/blob.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../model/word.dart';
import '../word/word_book_codec.dart';
import '../word/word_image.dart';

/// 単語帳の置き場（SPEC 7.4）。
///
/// 単語帳は親が作って直すもの。**人ごとには分けない。** 誰にどれを出すかは
/// [User.wordBooks] が持つ（上の子には漢字入りの語、下の子にはひらがなの語）。
///
/// 同梱の単語帳も、開いたときに取り込んで同じ 1 種類のものとして扱う。
/// 「同梱だから直せない」という段差を作ると、語を 1 つ足したいだけの親が
/// まるごと作り直すことになる。
class WordBookStore extends ChangeNotifier {
  WordBookStore(this._db);

  static Future<WordBookStore> open(Database db) async {
    final store = WordBookStore(db);
    await store.load();
    // まっさらな端末には、はじめの単語帳を入れておく。取り込まなくても
    // その日から語で書ける。
    if (store._all.isEmpty) await store.restoreBundled();
    return store;
  }

  /// はじめから入れておく単語帳。
  static const bundled = [
    'assets/words/hiragana.yaml',
    'assets/words/katakana.yaml',
    'assets/words/digits.yaml',
  ];

  static final _books = stringMapStoreFactory.store('wordBooks');

  /// 語に添える絵（SPEC 7.4）。運筆と同じく、実体は別ストアに置く。
  /// 一覧を出すのに要るのは語だけで、全部の絵をメモリに載せる理由がない。
  static final _images = StoreRef<String, Blob>('wordImages');

  final Database _db;

  final List<WordBook> _all = [];

  /// 作った順に並ぶ。
  List<WordBook> get all => List.unmodifiable(_all);

  WordBook? operator [](String id) =>
      _all.where((book) => book.id == id).firstOrNull;

  /// 同梱の単語帳のうち、いま入っていないもの。
  List<String> get bundledMissing {
    final have = {for (final book in _all) book.source};
    return [
      for (final asset in bundled)
        if (!have.contains(asset)) asset,
    ];
  }

  Future<void> load() async {
    // 控えから戻したときは、同じ id で中身が入れ替わっていることがある。
    _imageCache.clear();
    _all
      ..clear()
      ..addAll(
        (await _books.find(
          _db,
          finder: Finder(sortOrders: [SortOrder('addedAt')]),
        )).map((record) => _decode(record.key, record.value)),
      );
    notifyListeners();
  }

  /// 同梱の単語帳のうち、いま無いものを入れ直す。
  ///
  /// 消したあとに取り戻す道を残しておく。消せるのに戻せないと、親は消すのを
  /// ためらう。
  Future<List<WordBook>> restoreBundled() async {
    final added = <WordBook>[];
    for (final asset in bundledMissing) {
      final book = parseWordBookYaml(
        await rootBundle.loadString(asset),
        id: asset,
        fallbackName: asset,
      );
      added.add(await add(book, source: asset));
    }
    return added;
  }

  /// 単語帳を足す。取り込みでも、その場で作るときでも通る道はここ 1 つ。
  Future<WordBook> add(WordBook book, {String? source}) async {
    final saved = WordBook(
      id: const Uuid().v7(),
      name: book.name,
      words: book.words,
      source: source,
    );
    await _books.record(saved.id).put(_db, {
      ..._encode(saved),
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
    _all.add(saved);
    notifyListeners();
    return saved;
  }

  /// 名前や語を直す。
  Future<void> save(WordBook book) async {
    await _books.record(book.id).update(_db, _encode(book));
    final index = _all.indexWhere((entry) => entry.id == book.id);
    if (index >= 0) _all[index] = book;
    await _sweepImages();
    notifyListeners();
  }

  /// 単語帳を消す。書いた記録も、書き終えた語の履歴も消えない（SPEC 4.1）。
  Future<void> remove(String id) async {
    await _books.record(id).delete(_db);
    _all.removeWhere((book) => book.id == id);
    await _sweepImages();
    notifyListeners();
  }

  /// 絵を入れる。返るのは語に付ける id。
  ///
  /// 大きすぎる絵は断る。呼ぶ前に [maxImageBytes] で確かめること。
  Future<String> addImage(Uint8List bytes, {required String fileName}) async {
    final extension = extensionOf(fileName);
    final id = '${const Uuid().v7()}.$extension';
    await _images.record(id).put(_db, Blob(bytes));
    _imageCache[id] = bytes;
    return id;
  }

  /// 一度読んだ絵は持っておく。一覧では同じ絵を何度も出す。
  final Map<String, Uint8List?> _imageCache = {};

  /// 絵を読み出す。無ければ null。
  Future<Uint8List?> readImage(String id) async {
    if (_imageCache.containsKey(id)) return _imageCache[id];
    final bytes = (await _images.record(id).get(_db))?.bytes;
    _imageCache[id] = bytes;
    return bytes;
  }

  /// もう読んである絵。まだなら null（[readImage] で読む）。
  Uint8List? cachedImage(String id) => _imageCache[id];

  /// どの語からも指されていない絵を片づける。
  ///
  /// 絵は記録ではなく持ち物なので、消えても失われるものはない（SPEC 4.1 の
  /// 「削除しない」は書いた記録の話）。放っておくと端末の中に溜まる。
  Future<void> _sweepImages() async {
    final used = {
      for (final book in _all)
        for (final word in book.words)
          if (word.image != null) word.image!,
    };
    final stored = await _images.findKeys(_db);
    final orphans = stored.where((id) => !used.contains(id)).toList();
    if (orphans.isEmpty) return;
    await _images.records(orphans).delete(_db);
    for (final id in orphans) {
      _imageCache.remove(id);
    }
  }

  Map<String, Object?> _encode(WordBook book) => {
    'name': book.name,
    'source': book.source,
    'words': [
      for (final word in book.words)
        {
          'text': word.text,
          'reading': word.reading,
          'tags': word.tags,
          'image': word.image,
        },
    ],
  };

  WordBook _decode(String id, Map<String, Object?> record) => WordBook(
    id: id,
    name: record['name']! as String,
    source: record['source'] as String?,
    words: [
      for (final word in (record['words']! as List).cast<Map<String, Object?>>())
        Word(
          text: word['text']! as String,
          reading: word['reading']! as String,
          tags: (word['tags'] as List? ?? const []).cast<String>(),
          image: word['image'] as String?,
        ),
    ],
  );
}
