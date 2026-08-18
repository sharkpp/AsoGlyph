import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/user.dart';
import 'package:asoglyph/store/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';

Sample _written(String char) => Sample.now(
  char: char,
  mode: PracticeMode.copy,
  strokes: [
    Stroke(const [
      InkPoint(x: 300, y: 500, t: 0, pressure: 0),
      InkPoint(x: 700, y: 500, t: 20, pressure: 0),
    ]),
  ],
);

void main() {
  // Session が同梱の単語帳を資産から読む。
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late Session session;
  setUp(() async => session = await openMemorySession());

  test('開くと必ず 1 人いる', () {
    // 設定を求める画面から始めない。開いた瞬間に書ける。
    expect(session.users.all, hasLength(1));
    expect(session.current.displayName, 'じぶん');
    expect(session.users.hasMany, isFalse);
  });

  test('記録は人ごとに完全に分かれる', () async {
    await session.samples.add(_written('あ'));

    final second = await session.addUser(name: 'いもうと', avatar: Avatar.rabbit);
    expect(session.samples.collectedChars(includeTraced: false), isEmpty);

    await session.samples.add(_written('い'));
    expect(session.samples.collectedChars(includeTraced: false), ['い']);

    // 戻すと、前の人の字がそのまま残っている（SPEC 7.5）。
    await session.switchTo(session.users.all.first.id);
    expect(session.samples.collectedChars(includeTraced: false), ['あ']);
    expect(session.current.id, isNot(second.id));
  });

  test('版も人ごとに分かれる', () async {
    await session.recipes.create('じぶんの版');

    await session.addUser(name: 'いもうと', avatar: Avatar.bird);
    expect(session.recipes.all, isEmpty);

    await session.recipes.create('いもうとの版');
    expect(session.recipes.all.map((r) => r.name), ['いもうとの版']);

    await session.switchTo(session.users.all.first.id);
    expect(session.recipes.all.map((r) => r.name), ['じぶんの版']);
  });

  test('人を足すとその人に切り替わる', () async {
    final added = await session.addUser(name: 'あに', avatar: Avatar.car);

    expect(session.current.id, added.id);
    expect(session.users.hasMany, isTrue);
  });

  test('全消しは、いまの人の記録だけを消す', () async {
    await session.samples.add(_written('あ'));
    final first = session.current.id;

    await session.addUser(name: 'いもうと', avatar: Avatar.star);
    await session.samples.add(_written('い'));
    await session.samples.clear();
    expect(session.samples.collectedChars(includeTraced: false), isEmpty);

    await session.switchTo(first);
    expect(
      session.samples.collectedChars(includeTraced: false),
      ['あ'],
      reason: 'ほかの人の記録は消えない',
    );
  });

  test('名前と印を変えても、その人の記録は変わらない', () async {
    await session.samples.add(_written('あ'));
    await session.users.save(
      session.current.copyWith(displayName: 'はなこ', avatar: Avatar.flower),
    );

    expect(session.current.displayName, 'はなこ');
    expect(session.samples.collectedChars(includeTraced: false), ['あ']);
  });

  test('開き直しても、最後に書いていた人のままになる', () async {
    final second = await session.addUser(name: 'いもうと', avatar: Avatar.cake);
    await session.samples.add(_written('い'));

    // 同じデータベースを開き直す。
    await session.users.load();
    expect(session.users.current.id, second.id);
  });
}
