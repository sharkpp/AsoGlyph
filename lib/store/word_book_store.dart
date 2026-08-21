import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sembast/blob.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../model/word.dart';
import '../word/word_book_codec.dart';
import '../word/word_book_export.dart';
import '../word/word_image.dart';
import 'bundled_assets.dart';

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
  WordBookStore(this._db, {BundledAssets? assets})
    : _assets = assets ?? const AppBundledAssets();

  static Future<WordBookStore> open(
    Database db, {
    BundledAssets? assets,
    Set<String> preferred = const {},
  }) async {
    final store = WordBookStore(db, assets: assets);
    await store.load();
    // 開くたびに内蔵の辞書を合わせる。空のときだけ入れる作りにすると、
    // あとからアプリに足した辞書が、すでに使っている端末に出てこない。
    await store.syncBundled(preferred: preferred);
    return store;
  }

  static final _books = stringMapStoreFactory.store('wordBooks');

  /// 語に添える絵（SPEC 7.4）。運筆と同じく、実体は別ストアに置く。
  /// 一覧を出すのに要るのは語だけで、全部の絵をメモリに載せる理由がない。
  static final _images = StoreRef<String, Blob>('wordImages');

  final Database _db;
  final BundledAssets _assets;

  final List<WordBook> _all = [];

  /// いちばん最後に入れた時刻。次に入れるものを必ずそのうしろに置く。
  int _lastAddedAt = 0;

  /// 内蔵の辞書の id -> 資産の中身の指紋。
  ///
  /// 中身が変わったかを、開くたびに読み比べるために持つ。
  final Map<String, int> _fingerprints = {};

  /// 作った順に並ぶ。
  List<WordBook> get all => List.unmodifiable(_all);

  WordBook? operator [](String id) =>
      _all.where((book) => book.id == id).firstOrNull;


  Future<void> load() async {
    // 控えから戻したときは、同じ id で中身が入れ替わっていることがある。
    _imageCache.clear();
    final records = await _books.find(
      _db,
      finder: Finder(sortOrders: [SortOrder('addedAt')]),
    );
    _lastAddedAt = records.fold(
      0,
      (last, record) => max(last, record.value['addedAt']! as int),
    );
    _fingerprints
      ..clear()
      ..addEntries(
        records
            .where((record) => record.value['fingerprint'] != null)
            .map(
              (record) =>
                  MapEntry(record.key, record.value['fingerprint']! as int),
            ),
      );
    _all
      ..clear()
      ..addAll(records.map((record) => _decode(record.key, record.value)));
    notifyListeners();
  }

  /// アプリに入っている辞書に合わせる。
  ///
  /// 足りないものを入れ、無くなったものを片づけ、**中身が変わったものは
  /// 入れ替える**。辞書を直したら、開き直せばそれが出る。
  ///
  /// 入れ替えるときも **id は変えない**。誰にどれを出すかは id で覚えている
  /// （[User.wordBooks]）ので、id が変わると割り振りが外れる。並びも変えない。
  ///
  /// **資産 1 つに対して辞書は 1 冊**。2 冊できていたら 1 冊に寄せる。
  /// 内蔵の辞書の id は端末ごとに割り当てるので、控えを別の置き場へ戻すと
  /// （iPad では Safari とホーム画面のアプリでも置き場が別、SPEC 10.1）
  /// 同じ資産のぶんが 2 冊になる。放っておくと、戻すたびに増えていく。
  ///
  /// [preferred] にある id は残す側に選ぶ。誰かに割り振られている辞書を
  /// 消すと、戻したのに単語帳が出ない人ができる。
  Future<void> syncBundled({Set<String> preferred = const {}}) async {
    final assets = await _assets.list();

    // アプリから外した辞書は片づける。動作確認用の辞書を手元から外したとき、
    // その端末に残り続けないようにする。
    for (final book in [..._all]) {
      if (book.source != null && !assets.contains(book.source)) {
        await _delete(book.id);
      }
    }

    final byAsset = <String, WordBook>{};
    for (final book in [..._all]) {
      final source = book.source;
      if (source == null) continue;
      final kept = byAsset[source];
      if (kept == null) {
        byAsset[source] = book;
        continue;
      }
      // 割り振られている側を残す。どちらでもなければ先に入ったほうを残す
      // （_all は入れた順に並ぶ）。
      final replace = preferred.contains(book.id) && !preferred.contains(kept.id);
      byAsset[source] = replace ? book : kept;
      await _delete(replace ? kept.id : book.id);
    }

    for (final asset in assets) {
      await _syncAsset(asset, byAsset[asset]);
    }
    await _sweepImages();
    notifyListeners();
  }

  /// 資産 1 つを、いま入っているものと突き合わせる。
  ///
  /// 指紋が同じなら何もしない。**中身の読み取りはここで初めて行う。**
  /// 絵の入った辞書は開くのに手間が掛かるので、変わっていないうちは開かない。
  Future<void> _syncAsset(String asset, WordBook? existing) async {
    final isBundle = asset.endsWith('.$wordBookBundleExtension');
    // 指紋のために中身は毎回読む。読むだけなら安いが、開くのは高い。
    final Uint8List? bytes;
    final String? text;
    if (isBundle) {
      bytes = await _assets.load(asset);
      text = null;
    } else {
      bytes = null;
      text = await _assets.loadString(asset);
    }
    final fingerprint = Object.hash(
      asset,
      bytes?.length ?? text!.length,
      bytes == null ? text.hashCode : Object.hashAll(bytes),
    );
    if (existing != null && _fingerprints[existing.id] == fingerprint) return;

    // 読み取りは資産を取り終えてから、同期のまま行う。await をまたいで投げると、
    // 捕まえてもテストの土台が「拾われなかった例外」として拾ってしまう。
    final WordBook parsed;
    try {
      parsed = isBundle
          ? _fromBundle(bytes!, asset)
          : parseWordBookYaml(text!, id: asset, fallbackName: asset);
    } catch (error) {
      // 読めない辞書 1 つで、アプリが開かなくなってはいけない。
      // 手で直した単語帳ファイルを置くこともある（動作確認用の辞書）。
      debugPrint('単語帳を読めませんでした: $asset ($error)');
      return;
    }

    final images = isBundle ? await _storeImages(bytes!, asset) : null;
    final book = images == null ? parsed : _relinked(parsed, images);

    if (existing == null) {
      await add(book, source: asset, fingerprint: fingerprint);
      return;
    }
    // 中身だけを入れ替える。id・並び・割り振りはそのまま。
    final replaced = book.copyWith(id: existing.id);
    await _books.record(existing.id).update(_db, {
      ..._encode(replaced),
      'fingerprint': fingerprint,
    });
    _fingerprints[existing.id] = fingerprint;
    _all[_all.indexWhere((entry) => entry.id == existing.id)] = replaced;
  }

  /// 単語帳ファイル（zip）を開く。
  WordBook _fromBundle(Uint8List bytes, String asset) =>
      parseWordBookBundle(bytes, name: asset).book;

  /// 単語帳ファイルの中の絵を端末へ入れる。返るのは 中の名前 -> 端末の id。
  Future<Map<String, String>> _storeImages(Uint8List bytes, String asset) async {
    final bundle = parseWordBookBundle(bytes, name: asset);
    final ids = <String, String>{};
    for (final entry in bundle.images.entries) {
      // 大きすぎる絵は入れない。取り込みと同じ物差しで測る。
      if (entry.value.length > maxImageBytes) continue;
      ids[entry.key] = await addImage(entry.value, fileName: entry.key);
    }
    return ids;
  }

  /// 語の指す絵を、端末に入れた絵の id へ付け替える。
  WordBook _relinked(WordBook book, Map<String, String> ids) => book.copyWith(
    words: [
      for (final word in book.words)
        word.image == null
            ? word
            : ids[word.image!] == null
            ? word.withoutImage()
            : word.copyWith(image: ids[word.image!]),
    ],
  );

  /// 単語帳を足す。取り込みでも、その場で作るときでも通る道はここ 1 つ。
  Future<WordBook> add(
    WordBook book, {
    String? source,
    int? fingerprint,
  }) async {
    final saved = WordBook(
      id: const Uuid().v7(),
      name: book.name,
      words: book.words,
      author: book.author,
      description: book.description,
      source: source,
    );
    // 同じミリ秒に何冊も入る（内蔵の辞書は起動時にまとめて入る）。時刻だけでは
    // 並びが決まらないので、必ず 1 つずつ進めて入れた順にする。
    //
    // id では代われない。UUID v7 はミリ秒から先が乱数で、同じミリ秒の中に
    // 順序を持たない。並びを id に頼ると、開くたびに順番が変わる。
    _lastAddedAt = max(DateTime.now().millisecondsSinceEpoch, _lastAddedAt + 1);
    await _books.record(saved.id).put(_db, {
      ..._encode(saved),
      'addedAt': _lastAddedAt,
      'fingerprint': fingerprint,
    });
    if (fingerprint != null) _fingerprints[saved.id] = fingerprint;
    _all.add(saved);
    notifyListeners();
    return saved;
  }

  /// 内蔵の単語帳をもとに、直せるコピーを作る。
  ///
  /// 内蔵は直せない。語を 1 つ足したいだけの親が、まるごと作り直すことに
  /// ならないよう、ここから始められるようにする。
  /// 作った人と概要はそのまま持っていく。語はその人が選んだものなので、
  /// コピーを作っただけで出どころが消えるのはおかしい。直したい人は
  /// コピーの側で書き替える。
  Future<WordBook> copy(WordBook book, {required String name}) => add(
    WordBook(
      id: '',
      name: name,
      words: book.words,
      author: book.author,
      description: book.description,
    ),
  );

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
    'author': book.author,
    'description': book.description,
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
    author: record['author'] as String?,
    description: record['description'] as String?,
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
