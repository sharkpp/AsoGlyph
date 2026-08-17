import 'package:flutter/foundation.dart';
import 'package:sembast/blob.dart';
import 'package:sembast/sembast.dart';

import '../model/sample.dart';
import 'app_database.dart';
import 'stroke_codec.dart';

/// 書いた記録の置き場。追記のみで、書き換えも削除もしない（SPEC 4.1）。
///
/// 運筆は別ストアに分けてある。一覧・充足率の表示に必要なのは書いた事実だけで、
/// 全文字ぶんの運筆をメモリに載せる理由がないため。
class SampleStore extends ChangeNotifier {
  SampleStore(this._db);

  /// アプリから使う実体を開く。
  static Future<SampleStore> open() async {
    final store = SampleStore(await openAppDatabase('asoglyph.db'));
    await store.load();
    return store;
  }

  static final _meta = stringMapStoreFactory.store('samples');
  static final _strokes = StoreRef<String, Blob>('strokes');

  final Database _db;

  /// 文字 -> 試行。書いた順に並ぶ。
  final Map<String, List<SampleRef>> _byChar = {};

  Future<void> load() async {
    _byChar.clear();
    // id は UUID v7。同じミリ秒に書いた記録でも順序が一意に決まる。
    final records = await _meta.find(
      _db,
      finder: Finder(
        sortOrders: [SortOrder('writtenAt'), SortOrder(Field.key)],
      ),
    );
    for (final record in records) {
      final entry = SampleRef.fromRecord(record.key, record.value);
      _byChar.putIfAbsent(entry.char, () => []).add(entry);
    }
    notifyListeners();
  }

  Future<void> add(Sample sample) async {
    await _db.transaction((txn) async {
      await _meta.record(sample.id).put(txn, {
        'char': sample.char,
        'mode': sample.mode.name,
        'writtenAt': sample.writtenAt.millisecondsSinceEpoch,
      });
      await _strokes
          .record(sample.id)
          .put(txn, Blob(encodeStrokes(sample.strokes)));
    });

    _byChar
        .putIfAbsent(sample.char, () => [])
        .add(SampleRef(sample.id, sample.char, sample.mode, sample.writtenAt));
    notifyListeners();
  }

  /// 記録を全部消す。
  ///
  /// 記録は追記のみで削除しないのが原則（SPEC 4.1）。これはその例外で、
  /// 動作確認のために最初から試し直せるようにするためだけに置いてある。
  Future<void> clear() async {
    await _db.transaction((txn) async {
      await _meta.delete(txn);
      await _strokes.delete(txn);
    });
    _byChar.clear();
    notifyListeners();
  }

  /// その文字を書いた回数。なぞり書きも数える（子供に見せる進捗のため）。
  int attemptCount(String char) => _byChar[char]?.length ?? 0;

  /// その文字の試行を書いた順に返す。運筆は読まない。
  ///
  /// [before] を渡すと、その時刻以前に書いたものだけを返す（`at` 規則）。
  List<SampleRef> history(
    String char, {
    required bool includeTraced,
    DateTime? before,
  }) => [
    for (final entry in _byChar[char] ?? const <SampleRef>[])
      if (includeTraced || entry.mode != PracticeMode.trace)
        if (before == null || !entry.writtenAt.isAfter(before)) entry,
  ];

  /// 素材に使う最新の Sample の id。まだ無ければ null。
  ///
  /// なぞり書きを混ぜるかは呼び出し側が決める。なぞりとそれ以外は別の履歴
  /// として持ち、フォントを出すときに混ぜるかどうかを選べるようにする。
  String? latestId(String char, {required bool includeTraced}) {
    final entries = history(char, includeTraced: includeTraced);
    return entries.isEmpty ? null : entries.last.id;
  }

  /// その id の試行がまだあるか。差し替え（charRules）の指す先を確かめる。
  bool contains(String id) =>
      _byChar.values.any((entries) => entries.any((e) => e.id == id));

  /// 素材が 1 つ以上ある文字。フォントに載せられる字はこれで決まる。
  Iterable<String> collectedChars({required bool includeTraced}) => _byChar.keys
      .where((char) => latestId(char, includeTraced: includeTraced) != null);

  /// 運筆を読み出す。フォント生成のときだけ必要になる。
  Future<Sample> read(String id) async {
    final meta = await _meta.record(id).get(_db);
    final blob = await _strokes.record(id).get(_db);
    if (meta == null || blob == null) {
      throw StateError('Sample $id が見つからない');
    }
    final entry = SampleRef.fromRecord(id, meta);
    return Sample(
      id: id,
      char: entry.char,
      mode: entry.mode,
      writtenAt: entry.writtenAt,
      strokes: decodeStrokes(blob.bytes),
    );
  }
}

/// 記録 1 件のうち、運筆を除いた見出し。
///
/// 一覧・充足率・版の選択に必要なのは書いた事実だけで、全文字ぶんの運筆を
/// メモリに載せる理由がない。運筆は [SampleStore.read] で個別に読む。
class SampleRef {
  const SampleRef(this.id, this.char, this.mode, this.writtenAt);

  factory SampleRef.fromRecord(String id, Map<String, Object?> record) =>
      SampleRef(
        id,
        record['char']! as String,
        PracticeMode.values.byName(record['mode']! as String),
        DateTime.fromMillisecondsSinceEpoch(record['writtenAt']! as int),
      );

  final String id;
  final String char;
  final PracticeMode mode;
  final DateTime writtenAt;
}
