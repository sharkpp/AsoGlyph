import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../model/char_set.dart';
import '../model/user.dart';

/// 書く人の置き場と、いま誰が書いているか（SPEC 7.5）。
///
/// 記録と版はこの `current` に属する。人を切り替えたら、両方を読み直す。
class UserStore extends ChangeNotifier {
  UserStore(this._db);

  /// 開く。1 人もいなければ最初の 1 人を作る。
  ///
  /// 設定を求める画面から始めない。アプリは開いた瞬間に書ける状態であってほしい。
  /// 名前と印は、あとから管理画面で直せる。
  static Future<UserStore> open(Database db) async {
    final store = UserStore(db);
    await store.load();
    if (store.all.isEmpty) await store.create(name: 'じぶん', avatar: Avatar.cat);
    return store;
  }

  static final _users = stringMapStoreFactory.store('users');
  static final _settings = stringMapStoreFactory.store('settings');
  static const _currentKey = 'current-user';

  final Database _db;

  final List<User> _all = [];
  String? _currentId;

  /// 作った順に並ぶ。
  List<User> get all => List.unmodifiable(_all);

  /// いま書いている人。1 人以上いれば必ず決まる。
  User get current =>
      _all.firstWhere((user) => user.id == _currentId, orElse: () => _all.first);

  bool get hasMany => _all.length > 1;

  Future<void> load() async {
    _all
      ..clear()
      ..addAll(
        (await _users.find(
          _db,
          finder: Finder(sortOrders: [SortOrder('createdAt')]),
        )).map((record) => _decode(record.key, record.value)),
      );
    _currentId =
        (await _settings.record(_currentKey).get(_db))?['id'] as String?;
    notifyListeners();
  }

  Future<User> create({required String name, required Avatar avatar}) async {
    final user = User(
      id: const Uuid().v7(),
      displayName: name,
      avatar: avatar,
      createdAt: DateTime.now(),
    );
    await _users.record(user.id).put(_db, _encode(user));
    _all.add(user);
    // 最初の 1 人はそのまま書き始められるようにする。
    if (_all.length == 1) await select(user.id);
    notifyListeners();
    return user;
  }

  Future<void> save(User user) async {
    await _users.record(user.id).put(_db, _encode(user));
    final index = _all.indexWhere((u) => u.id == user.id);
    if (index >= 0) _all[index] = user;
    notifyListeners();
  }

  /// 人を消す。記録が 1 つも無い人にだけ使う（[Session.restoreFrom]）。
  Future<void> remove(String id) async {
    await _users.record(id).delete(_db);
    _all.removeWhere((user) => user.id == id);
    notifyListeners();
  }

  /// 書く人を切り替える。記録の読み直しは呼び出し側が行う。
  Future<void> select(String id) async {
    if (_currentId == id) return;
    await _settings.record(_currentKey).put(_db, {'id': id});
    _currentId = id;
    notifyListeners();
  }
}

Map<String, Object?> _encode(User user) => {
  'displayName': user.displayName,
  'avatar': user.avatar.name,
  'createdAt': user.createdAt.millisecondsSinceEpoch,
  'birthMonth': user.birthMonth?.millisecondsSinceEpoch,
  'collecting': [for (final set in user.collecting) set.name],
  'wordBooks': [...user.wordBooks],
};

User _decode(String id, Map<String, Object?> record) {
  final birthMonth = record['birthMonth'] as int?;
  return User(
    id: id,
    displayName: record['displayName']! as String,
    avatar: Avatar.values.byName(record['avatar']! as String),
    createdAt: DateTime.fromMillisecondsSinceEpoch(record['createdAt']! as int),
    birthMonth: birthMonth == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(birthMonth),
    collecting: {
      for (final name in (record['collecting'] as List? ?? []).cast<String>())
        CharSet.values.byName(name),
    },
    wordBooks: (record['wordBooks'] as List? ?? []).cast<String>().toSet(),
  );
}
