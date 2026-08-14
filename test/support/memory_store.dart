import 'package:asoglyph/store/sample_store.dart';
import 'package:sembast/sembast_memory.dart';

/// テスト用の SampleStore。実装ごとに新しいメモリ DB を割り当てる。
Future<SampleStore> openMemoryStore() async {
  final store = SampleStore(
    await newDatabaseFactoryMemory().openDatabase('asoglyph.db'),
  );
  await store.load();
  return store;
}
