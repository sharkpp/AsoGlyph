import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:sembast/blob.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../model/word.dart';
import '../word/word_book_codec.dart';
import '../word/word_book_export.dart';
import '../word/word_image.dart';

/// 単語帳の置き場（SPEC 7.4）。
///
/// 単語帳は親が作って直すもの。**人ごとには分けない。** 誰にどれを出すかは
/// [User.wordBooks] が持つ（上の子には漢字入りの語、下の子にはひらがなの語）。
///
/// 単語帳には 2 種類ある。
///
/// - **内蔵**（アプリに入っている）… 親が足さなくても最初からある。
///   直せないし消せない。要る要らないは人ごとのチェックで決める
/// - **自分の**（作った・取り込んだ）… 名前も語も直せるし、消せる
///
/// 内蔵を直せなくしているのは、直せると「元に戻す」道が要るため。
/// 直したいときはコピーを作る（[copy]）。1 タップで済む。
class WordBookStore extends ChangeNotifier {
  WordBookStore(this._db);

  static Future<WordBookStore> open(Database db) async {
    final store = WordBookStore(db);
    await store.load();
    // 開くたびに内蔵の辞書を合わせる。空のときだけ入れる作りにすると、
    // あとからアプリに足した辞書が、すでに使っている端末に出てこない。
    await store.syncBundled();
    return store;
  }

  /// 内蔵の辞書を置く場所。
  static const bundledDir = 'assets/words/';

  /// 動作確認用の辞書の目印。
  ///
  /// **ファイル名が `_` で始まるものは、デバッグでだけ読む。**
  /// リポジトリにも入れない（`.gitignore`）ので、素の取得から作った
  /// リリースには存在しない。手元で試す辞書を、配るものに混ぜないため。
  static bool isDebugAsset(String path) => path.split('/').last.startsWith('_');

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

  /// アプリに入っている辞書に合わせる。
  ///
  /// 足りないものを入れ、無くなったものを片づける。**中身は上書きしない。**
  /// 内蔵は直せないので中身が変わることはないが、アプリを新しくしたときに
  /// 名前だけ変えて別物に入れ替わる、といったことも起こさない。
  Future<void> syncBundled() async {
    final assets = await bundledAssets();

    // アプリから外した辞書は片づける。動作確認用の辞書を手元から外したとき、
    // その端末に残り続けないようにする。
    for (final book in [..._all]) {
      if (book.source != null && !assets.contains(book.source)) {
        await _delete(book.id);
      }
    }

    final have = {for (final book in _all) book.source};
    for (final asset in assets) {
      if (!have.contains(asset)) await _addFromAsset(asset);
    }
    await _sweepImages();
    notifyListeners();
  }

  /// アプリに入っている辞書ファイル。
  ///
  /// 一覧は資産そのものから引く。並びを手で持つと、辞書を足したときに
  /// 書き足し忘れて出てこない。
  Future<List<String>> bundledAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets =
        manifest
            .listAssets()
            .where((path) => path.startsWith(bundledDir))
            .where(
              (path) =>
                  path.endsWith('.yaml') ||
                  path.endsWith('.yml') ||
                  path.endsWith('.$wordBookBundleExtension'),
            )
            // 動作確認用はデバッグでだけ読む。
            .where((path) => kDebugMode || !isDebugAsset(path))
            .toList()
          ..sort();
    // 動作確認用はうしろに寄せる。配る辞書の並びを、手元の都合で崩さない。
    return [
      ...assets.where((path) => !isDebugAsset(path)),
      ...assets.where(WordBookStore.isDebugAsset),
    ];
  }

  /// 資産 1 つを単語帳にする。絵の入った単語帳ファイルも読む。
  Future<WordBook> _addFromAsset(String asset) async {
    if (!asset.endsWith('.$wordBookBundleExtension')) {
      return add(
        parseWordBookYaml(
          await rootBundle.loadString(asset),
          id: asset,
          fallbackName: asset,
        ),
        source: asset,
      );
    }

    final bundle = parseWordBookBundle(
      (await rootBundle.load(asset)).buffer.asUint8List(),
      name: asset,
    );
    final ids = <String, String>{};
    for (final entry in bundle.images.entries) {
      if (entry.value.length > maxImageBytes) continue;
      ids[entry.key] = await addImage(entry.value, fileName: entry.key);
    }
    return add(
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
      source: asset,
    );
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

  /// 内蔵の単語帳をもとに、直せるコピーを作る。
  ///
  /// 内蔵は直せない。語を 1 つ足したいだけの親が、まるごと作り直すことに
  /// ならないよう、ここから始められるようにする。
  Future<WordBook> copy(WordBook book, {required String name}) =>
      add(WordBook(id: '', name: name, words: book.words));

  /// 名前や語を直す。内蔵の単語帳は直せない。
  Future<void> save(WordBook book) async {
    if (book.isBundled) return;
    await _books.record(book.id).update(_db, _encode(book));
    final index = _all.indexWhere((entry) => entry.id == book.id);
    if (index >= 0) _all[index] = book;
    await _sweepImages();
    notifyListeners();
  }

  /// 単語帳を消す。書いた記録も、書き終えた語の履歴も消えない（SPEC 4.1）。
  ///
  /// 内蔵の単語帳は消せない。開き直すたびに戻ってくるので、消せたように
  /// 見えて戻る、といういちばん分かりにくい振る舞いになる。要らない人には
  /// チェックを外してもらう。
  Future<void> remove(String id) async {
    if (this[id]?.isBundled ?? false) return;
    await _delete(id);
    await _sweepImages();
    notifyListeners();
  }

  Future<void> _delete(String id) async {
    await _books.record(id).delete(_db);
    _all.removeWhere((book) => book.id == id);
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
