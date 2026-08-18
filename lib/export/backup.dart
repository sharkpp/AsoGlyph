/// 端末まるごとの控え（SPEC 7.5）。
///
/// 端末が壊れて子供の字が消えることは許容できない。書く人・記録・版を
/// 1 つのファイルに書き出し、そこから戻せるようにする。
///
/// 中身は記録そのもの（運筆を含む）なので、扱いは端末内の記録と同じ重さになる。
/// 出す先は共有シート任せで、こちらからどこかへ送ることはしない（SPEC 3）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sembast/blob.dart';
import 'package:sembast/sembast.dart';

// 単語トライアル（2）、単語帳（3）、語の絵（4）を足したときに上げた。
// 古い控えは読まない（AGENTS.md）。
const _backupVersion = 4;

final _users = stringMapStoreFactory.store('users');
final _settings = stringMapStoreFactory.store('settings');
final _samples = stringMapStoreFactory.store('samples');
final _strokes = StoreRef<String, Blob>('strokes');
final _recipes = stringMapStoreFactory.store('recipes');
final _attempts = stringMapStoreFactory.store('wordAttempts');
final _wordBooks = stringMapStoreFactory.store('wordBooks');
final _wordImages = StoreRef<String, Blob>('wordImages');

/// 控えを作る。
Future<Uint8List> exportBackup(Database db) async {
  final strokes = await _strokes.find(db);

  final backup = {
    'version': _backupVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'users': await _records(db, _users),
    // 誰が書いていたかも戻す。「戻す」は端末をその時の姿に返すこと。
    'settings': await _records(db, _settings),
    'recipes': await _records(db, _recipes),
    // 単語トライアルも記録のうち（SPEC 4.2）。
    'wordAttempts': await _records(db, _attempts),
    // 単語帳は親が作って直すもの。端末が壊れたら作り直しになる（SPEC 7.4）。
    'wordBooks': await _records(db, _wordBooks),
    'samples': await _records(db, _samples),
    // 運筆と絵はバイト列なので base64 にする。
    'strokes': {
      for (final record in strokes) record.key: base64Encode(record.value.bytes),
    },
    'wordImages': {
      for (final record in await _wordImages.find(db))
        record.key: base64Encode(record.value.bytes),
    },
  };

  return utf8.encode(jsonEncode(backup));
}

/// 控えから戻す。
///
/// 同じ id の記録は上書きし、無いものは足す。いまある記録は消さない。
/// 別の端末の控えを重ねても、どちらの字も残る。
Future<void> importBackup(Database db, Uint8List bytes) async {
  final backup = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

  final version = backup['version'];
  if (version != _backupVersion) {
    throw const FormatException('この控えは読み込めません');
  }

  final strokes = (backup['strokes']! as Map).cast<String, Object?>();

  await db.transaction((txn) async {
    await _put(txn, _users, backup['users']);
    await _put(txn, _settings, backup['settings']);
    await _put(txn, _recipes, backup['recipes']);
    await _put(txn, _attempts, backup['wordAttempts']);
    await _put(txn, _wordBooks, backup['wordBooks']);
    await _put(txn, _samples, backup['samples']);
    for (final entry in strokes.entries) {
      await _strokes
          .record(entry.key)
          .put(txn, Blob(base64Decode(entry.value! as String)));
    }
    for (final entry in (backup['wordImages']! as Map)
        .cast<String, Object?>()
        .entries) {
      await _wordImages
          .record(entry.key)
          .put(txn, Blob(base64Decode(entry.value! as String)));
    }
  });
}

Future<Map<String, Object?>> _records(
  Database db,
  StoreRef<String, Map<String, Object?>> store,
) async => {
  for (final record in await store.find(db)) record.key: record.value,
};

Future<void> _put(
  DatabaseClient txn,
  StoreRef<String, Map<String, Object?>> store,
  Object? records,
) async {
  for (final entry in (records! as Map).cast<String, Object?>().entries) {
    await store
        .record(entry.key)
        .put(txn, (entry.value! as Map).cast<String, Object?>());
  }
}
