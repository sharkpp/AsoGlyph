@TestOn('browser')
library;

import 'package:asoglyph/store/word_book_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast_web/sembast_web.dart';

import '../support/memory_store.dart' show FakeBundledAssets;

void main() {
  const yaml = '''
version: 1
name: どうぶつ
words:
  - text: ねこ
    reading: ねこ
''';

  test('開き直しても内蔵の辞書は増えない（web / IndexedDB）', () async {
    final assets = FakeBundledAssets({'assets/words/animals.yaml': yaml});
    final name = 'web-test-${DateTime.now().microsecondsSinceEpoch}.db';

    Future<Database> open() => databaseFactoryWeb.openDatabase(name);

    var db = await open();
    var books = await WordBookStore.open(db, assets: assets);
    expect(books.all, hasLength(1));
    final firstId = books.all.single.id;
    await db.close();

    // 開き直す（リロード）。
    db = await open();
    books = await WordBookStore.open(db, assets: assets);
    expect(
      books.all.map((book) => book.source).toList(),
      ['assets/words/animals.yaml'],
      reason: '同じ資産のぶんが 2 冊になってはいけない',
    );
    expect(books.all.single.id, firstId, reason: 'id は変えない（割り振りが外れる）');
    await db.close();
  });
}
