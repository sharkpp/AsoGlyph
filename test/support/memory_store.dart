import 'package:asoglyph/store/passcode.dart';
import 'package:asoglyph/store/recipe_store.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/store/session.dart';
import 'package:asoglyph/store/bundled_assets.dart';
import 'package:asoglyph/store/word_book_store.dart';
import 'dart:typed_data';

import 'package:sembast/sembast_memory.dart';

/// テスト用のデータベース。呼ぶたびに新しいメモリ DB を割り当てる。
Future<Database> openMemoryDatabase() =>
    newDatabaseFactoryMemory().openDatabase('asoglyph.db');

/// テスト用の SampleStore。1 人しかいない前提の id を使う。
Future<SampleStore> openMemoryStore() async =>
    SampleStore.open(await openMemoryDatabase(), userId: 'test-user');

/// テスト用の RecipeStore。
Future<RecipeStore> openMemoryRecipes() async =>
    RecipeStore.open(await openMemoryDatabase(), userId: 'test-user');

/// テスト用の Session。記録も版も同じ 1 つのメモリ DB に置く。
///
/// 同じ DB を渡すと、開き直したときの姿を確かめられる。
Future<Session> openMemorySession([Database? db]) async =>
    Session.open(db ?? await openMemoryDatabase());

/// テスト用の単語帳。はじめの単語帳が入った状態で開く。
Future<WordBookStore> openMemoryWordBooks([Database? db]) async =>
    WordBookStore.open(db ?? await openMemoryDatabase());

/// テスト用の内蔵辞書。資産の代わりに、その場で書き換えられる中身を返す。
///
/// 資産は実行ファイルの中にあり、テストからは書き換えられない。辞書を
/// 直したときの振る舞い（SPEC 7.4.3）は、これを差し替えて確かめる。
class FakeBundledAssets implements BundledAssets {
  FakeBundledAssets(this.files);

  /// パス -> 中身（YAML の文字列、または単語帳ファイルのバイト列）。
  final Map<String, Object> files;

  @override
  Future<List<String>> list() async => files.keys.toList();

  @override
  Future<String> loadString(String path) async => files[path]! as String;

  @override
  Future<Uint8List> load(String path) async => files[path]! as Uint8List;
}

/// テスト用のパスコード置き場。端末の Keychain を触らない。
class MemorySecretStore implements SecretStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String secret) async => value = secret;

  @override
  Future<void> delete() async => value = null;
}

/// テスト用の Passcode。既定は掛かっていない。
Future<Passcode> openMemoryPasscode({
  String? code,
  PasscodeKind kind = PasscodeKind.admin,
}) async {
  final store = MemorySecretStore()..value = code;
  return Passcode.open(kind, store);
}

/// テスト用のロックひとそろい。既定はどちらも掛かっていない。
Future<Locks> openMemoryLocks({String? admin, String? switching}) async => Locks(
  admin: await openMemoryPasscode(code: admin),
  switching: await openMemoryPasscode(
    code: switching,
    kind: PasscodeKind.switching,
  ),
);
