import 'dart:convert';
import 'dart:typed_data';

import 'package:asoglyph/export/backup.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/font_recipe.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/user.dart';
import 'package:asoglyph/model/word.dart';
import 'package:asoglyph/store/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

Sample _written(String char) => Sample.now(
  char: char,
  mode: PracticeMode.copy,
  strokes: [
    Stroke(const [
      InkPoint(x: 300, y: 500, t: 0, pressure: 0),
      InkPoint(x: 700, y: 500, t: 20, pressure: 1),
    ]),
  ],
);

void main() {
  // Session が同梱の単語帳を資産から読む。
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late Session source;
  setUp(() async => source = await openMemorySession());

  test('まっさらな端末に戻すと、空の 1 人が残らない', () async {
    await source.samples.add(_written('あ'));
    final backup = await exportBackup(source.db);

    final restored = await openMemorySession();
    await restored.restoreFrom(backup);

    // 開いたときに作った空の「じぶん」と、控えの「じぶん」が並ばない。
    expect(restored.users.all, hasLength(1));
    expect(restored.samples.collectedChars(includeTraced: false), ['あ']);
  });

  test('使っている端末に戻しても、こちらの人は消えない', () async {
    await source.samples.add(_written('あ'));
    final backup = await exportBackup(source.db);

    final target = await openMemorySession();
    await target.addUser(name: 'あに', avatar: Avatar.car);
    await target.restoreFrom(backup);

    // 空でも、こちらで足した人はそのまま残す。
    expect(target.users.all.map((u) => u.displayName), contains('あに'));
  });

  test('書く人・記録・版をまとめて書き出して戻せる', () async {
    await source.samples.add(_written('あ'));
    await source.recipes.create('いまの字');
    await source.addUser(name: 'いもうと', avatar: Avatar.rabbit);
    await source.samples.add(_written('い'));

    final backup = await exportBackup(source.db);

    // 別の端末を想定した、まっさらな控え先。
    final restored = await openMemorySession();
    await restored.restoreFrom(backup);

    expect(restored.users.all.map((u) => u.displayName), contains('いもうと'));
    // 人ごとに分かれたまま戻る。
    final imouto = restored.users.all.firstWhere(
      (u) => u.displayName == 'いもうと',
    );
    await restored.switchTo(imouto.id);
    expect(restored.samples.collectedChars(includeTraced: false), ['い']);

    final jibun = restored.users.all.firstWhere(
      (u) => u.displayName == 'じぶん',
    );
    await restored.switchTo(jibun.id);
    expect(restored.samples.collectedChars(includeTraced: false), ['あ']);
    expect(restored.recipes.all.map((r) => r.name), ['いまの字']);
  });

  test('運筆がそのまま戻る', () async {
    final sample = _written('あ');
    await source.samples.add(sample);

    final restored = await openMemorySession();
    await restored.restoreFrom(await exportBackup(source.db));

    final back = await restored.samples.read(sample.id);
    expect(back.strokes.single.points, hasLength(2));
    expect(back.strokes.single.points.last.x, 700);
    expect(back.strokes.single.points.last.pressure, 1, reason: '筆圧まで戻る');
  });

  test('版の規則もそのまま戻る', () async {
    final recipe = await source.recipes.create('あの頃');
    final spring = DateTime(2026, 4, 1);
    await source.recipes.save(
      recipe.copyWith(charSets: {CharSet.hiragana}, base: AtPolicy(spring)),
    );

    final restored = await openMemorySession();
    await restored.restoreFrom(await exportBackup(source.db));

    final back = restored.recipes.all.single;
    expect(back.charSets, {CharSet.hiragana});
    expect(back.base, AtPolicy(spring));
  });

  test('戻してもいまある字は消えない', () async {
    await source.samples.add(_written('あ'));
    final backup = await exportBackup(source.db);

    // 控えを取ったあとに書いた字。
    await source.samples.add(_written('か'));
    await source.restoreFrom(backup);

    expect(
      source.samples.collectedChars(includeTraced: false).toList()..sort(),
      ['あ', 'か'],
    );
  });

  test('知らない形式は読み込まない', () async {
    final bogus = Uint8List.fromList(
      utf8.encode(jsonEncode({'version': 99, 'users': <String, Object?>{}})),
    );

    expect(
      () => source.restoreFrom(bogus),
      throwsA(isA<FormatException>()),
    );
  });
  test('単語帳と、語の絵もまとめて戻せる', () async {
    final source = await openMemorySession();
    final id = await source.books.addImage(
      Uint8List.fromList([9, 8, 7]),
      fileName: 'ねこ.png',
    );
    await source.books.add(
      WordBook(
        id: '',
        name: 'うちのことば',
        words: [Word(text: 'ぱぱ', reading: 'ぱぱ', image: id)],
      ),
    );

    final bytes = await exportBackup(source.db);
    final target = await openMemorySession();
    await target.restoreFrom(bytes);

    // 単語帳は親が作って直すもの。端末が壊れたら作り直しになる。
    final restored = target.books.all.firstWhere(
      (book) => book.name == 'うちのことば',
    );
    expect(restored.words.single.text, 'ぱぱ');
    expect(await target.books.readImage(restored.words.single.image!), [9, 8, 7]);
  });

}
