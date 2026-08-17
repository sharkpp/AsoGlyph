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
