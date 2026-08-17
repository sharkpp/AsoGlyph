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
  final Map<String, List<_Entry>> _byChar = {};

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
      final entry = _Entry.fromRecord(record.key, record.value);
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
        .add(_Entry(sample.id, sample.char, sample.mode, sample.writtenAt));
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

  /// 素材として使える最新の Sample の id。まだ無ければ null。
  ///
  /// なぞり書きはフォントに採用しない（SPEC 7.1）。
  String? latestMaterialId(String char) {
    final entries = _byChar[char];
    if (entries == null) return null;
    for (final entry in entries.reversed) {
      if (entry.mode.isFontMaterial) return entry.id;
    }
    return null;
  }

  /// 素材が 1 つ以上ある文字。フォントに載せられる字はこれで決まる。
  Iterable<String> get collectedChars =>
      _byChar.keys.where((char) => latestMaterialId(char) != null);

  /// 運筆を読み出す。フォント生成のときだけ必要になる。
  Future<Sample> read(String id) async {
    final meta = await _meta.record(id).get(_db);
    final blob = await _strokes.record(id).get(_db);
    if (meta == null || blob == null) {
      throw StateError('Sample $id が見つからない');
    }
    final entry = _Entry.fromRecord(id, meta);
    return Sample(
      id: id,
      char: entry.char,
      mode: entry.mode,
      writtenAt: entry.writtenAt,
      strokes: decodeStrokes(blob.bytes),
    );
  }
}

class _Entry {
  const _Entry(this.id, this.char, this.mode, this.writtenAt);

  factory _Entry.fromRecord(String id, Map<String, Object?> record) => _Entry(
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
