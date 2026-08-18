import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../font/glyph.dart';
import '../model/char_set.dart';
import '../model/font_recipe.dart';

/// フォントの版の置き場。
///
/// 版は解決規則の集合でしかなく、数百バイトで済む（SPEC 4.3）。
/// 生成したフォントそのものは保存しない。同じ版と同じ記録からは
/// 同じバイト列が出るため、持っていても意味がない。
class RecipeStore extends ChangeNotifier {
  RecipeStore(this._db, {required this.userId});

  static Future<RecipeStore> open(Database db, {required String userId}) async {
    final store = RecipeStore(db, userId: userId);
    await store.load();
    return store;
  }

  /// いま読み書きしている人（SPEC 7.5）。版も人ごとに分かれる。
  String userId;

  /// 書く人を切り替える。
  Future<void> useUser(String id) async {
    if (userId == id) return;
    userId = id;
    await load();
  }

  static final _recipes = stringMapStoreFactory.store('recipes');

  final Database _db;

  final List<FontRecipe> _all = [];

  /// 作った順に並ぶ。
  List<FontRecipe> get all => List.unmodifiable(_all);

  Future<void> load() async {
    _all
      ..clear()
      ..addAll(
        (await _recipes.find(
          _db,
          finder: Finder(
            filter: Filter.equals('userId', userId),
            // id は UUID v7。同じミリ秒に作っても並びが一意に決まる。
            sortOrders: [SortOrder('createdAt'), SortOrder(Field.key)],
          ),
        )).map((record) => _decode(record.key, record.value)),
      );
    notifyListeners();
  }

  /// 新しい版を作る。既定は「今の字を全部」。
  Future<FontRecipe> create(String name) async {
    final recipe = FontRecipe.latest(
      id: const Uuid().v7(),
      name: name,
      createdAt: DateTime.now(),
      fontMeta: FontMetadata(familyName: name),
    );
    await save(recipe);
    return recipe;
  }

  /// 版を複製する。名前だけ変えて、規則はそのまま引き継ぐ。
  Future<FontRecipe> duplicate(FontRecipe source, String name) async {
    final copy = FontRecipe(
      id: const Uuid().v7(),
      name: name,
      createdAt: DateTime.now(),
      fontMeta: FontMetadata(familyName: name),
      charSets: source.charSets,
      base: source.base,
      groupRules: source.groupRules,
      charRules: source.charRules,
    );
    await save(copy);
    return copy;
  }

  Future<void> save(FontRecipe recipe) async {
    await _recipes.record(recipe.id).put(_db, {
      ..._encode(recipe),
      'userId': userId,
    });
    final index = _all.indexWhere((r) => r.id == recipe.id);
    if (index < 0) {
      _all.add(recipe);
    } else {
      _all[index] = recipe;
    }
    notifyListeners();
  }

  /// 版を消す。記録（Sample）は消えない。版は導出ビューでしかない。
  Future<void> remove(String id) async {
    await _recipes.record(id).delete(_db);
    _all.removeWhere((recipe) => recipe.id == id);
    notifyListeners();
  }
}

Map<String, Object?> _encode(FontRecipe recipe) => {
  'name': recipe.name,
  'createdAt': recipe.createdAt.millisecondsSinceEpoch,
  'familyName': recipe.fontMeta.familyName,
  'charSets': [for (final set in recipe.charSets) set.name],
  'base': _encodePolicy(recipe.base),
  'groupRules': {
    for (final entry in recipe.groupRules.entries)
      entry.key.name: _encodePolicy(entry.value),
  },
  'charRules': recipe.charRules,
};

FontRecipe _decode(String id, Map<String, Object?> record) {
  final groupRules = (record['groupRules'] as Map).cast<String, Object?>();
  final charRules = (record['charRules'] as Map).cast<String, Object?>();

  return FontRecipe(
    id: id,
    name: record['name']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(record['createdAt']! as int),
    // created は既定の固定値のままにする。同じ版からは同じバイト列が出る。
    fontMeta: FontMetadata(familyName: record['familyName']! as String),
    charSets: {
      for (final name in (record['charSets']! as List).cast<String>())
        CharSet.values.byName(name),
    },
    base: _decodePolicy((record['base']! as Map).cast<String, Object?>()),
    groupRules: {
      for (final entry in groupRules.entries)
        CharSet.values.byName(entry.key): _decodePolicy(
          (entry.value! as Map).cast<String, Object?>(),
        ),
    },
    charRules: charRules.cast<String, String>(),
  );
}

Map<String, Object?> _encodePolicy(Policy policy) => switch (policy) {
  LatestPolicy() => {'type': 'latest'},
  BestPolicy() => {'type': 'best'},
  AtPolicy(:final time) => {
    'type': 'at',
    'time': time.millisecondsSinceEpoch,
  },
};

Policy _decodePolicy(Map<String, Object?> record) =>
    switch (record['type']! as String) {
      'at' => AtPolicy(
        DateTime.fromMillisecondsSinceEpoch(record['time']! as int),
      ),
      'best' => const BestPolicy(),
      _ => const LatestPolicy(),
    };
