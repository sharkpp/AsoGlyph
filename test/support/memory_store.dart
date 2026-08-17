import 'package:asoglyph/store/passcode.dart';
import 'package:asoglyph/store/recipe_store.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:sembast/sembast_memory.dart';

/// テスト用のデータベース。呼ぶたびに新しいメモリ DB を割り当てる。
Future<Database> openMemoryDatabase() =>
    newDatabaseFactoryMemory().openDatabase('asoglyph.db');

/// テスト用の SampleStore。
Future<SampleStore> openMemoryStore() async =>
    SampleStore.open(await openMemoryDatabase());

/// テスト用の RecipeStore。
Future<RecipeStore> openMemoryRecipes() async =>
    RecipeStore.open(await openMemoryDatabase());

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
Future<Passcode> openMemoryPasscode({String? code}) async {
  final store = MemorySecretStore()..value = code;
  return Passcode.open(store);
}
