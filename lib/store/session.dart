import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../export/backup.dart';
import '../model/user.dart';
import 'recipe_store.dart';
import 'sample_store.dart';
import 'user_store.dart';
import 'word_attempt_store.dart';
import 'word_book_store.dart';

/// いま誰が書いているか、と、その人の記録・版（SPEC 7.5）。
///
/// 人を切り替えると、記録も版もまとめて入れ替わる。3 つのストアを別々に
/// 切り替えると、片方だけ前の人のままという状態が作れてしまう。
/// 切り替えの手順をここ 1 か所に閉じ込める。
class Session extends ChangeNotifier {
  Session({
    required this.db,
    required this.users,
    required this.samples,
    required this.recipes,
    required this.attempts,
    required this.books,
  }) {
    // 名前・印・集める文字種が変わったことも、ここを見ていれば分かるようにする。
    // 画面ごとに users を別途購読させると、購読し忘れた画面だけ古いままになる。
    users.addListener(notifyListeners);
  }

  @override
  void dispose() {
    users.removeListener(notifyListeners);
    super.dispose();
  }

  static Future<Session> open(Database db) async {
    final users = await UserStore.open(db);
    return Session(
      db: db,
      users: users,
      samples: await SampleStore.open(db, userId: users.current.id),
      recipes: await RecipeStore.open(db, userId: users.current.id),
      attempts: await WordAttemptStore.open(db, userId: users.current.id),
      books: await WordBookStore.open(db, preferred: _assigned(users)),
    );
  }

  /// 控えの読み書きなど、ストアをまたぐ操作で要る（SPEC 7.5）。
  final Database db;

  final UserStore users;
  final SampleStore samples;
  final RecipeStore recipes;

  /// 単語を書き終えた履歴（SPEC 4.2）。
  final WordAttemptStore attempts;

  /// 単語帳（SPEC 7.4）。人ごとには分かれない。
  ///
  /// 人ごとに分かれないのにここへ置くのは、控えから戻したときに読み直す
  /// 必要があるから。戻す手順が 1 か所にまとまっていないと、単語帳だけ
  /// 前の中身のまま残る。
  final WordBookStore books;

  User get current => users.current;

  /// 誰かに割り振られている単語帳の id（SPEC 7.4）。
  ///
  /// 内蔵の辞書を 1 冊に寄せるとき、どちらを残すかの手がかりになる。
  static Set<String> _assigned(UserStore users) => {
    for (final user in users.all) ...user.wordBooks,
  };

  /// 書く人を切り替える。
  Future<void> switchTo(String userId) async {
    if (users.current.id == userId) return;
    await users.select(userId);
    await samples.useUser(userId);
    await recipes.useUser(userId);
    await attempts.useUser(userId);
    notifyListeners();
  }

  /// 全部読み直す。控えから戻したあとに使う。
  Future<void> reload() async {
    await users.load();
    final id = users.current.id;
    samples.userId = id;
    recipes.userId = id;
    attempts.userId = id;
    await samples.load();
    await recipes.load();
    await attempts.load();
    await books.load();
    // 控えから戻したときは、内蔵の辞書が 1 資産 2 冊になっていることがある
    // （id は端末ごとなので、控えのぶんと手元のぶんが並ぶ）。ここで寄せる。
    await books.syncBundled(preferred: _assigned(users));
    notifyListeners();
  }

  /// 控えから戻す（SPEC 7.5）。
  ///
  /// まっさらな端末には、開いたときに作った空の 1 人がいる。控えを重ねると
  /// その人が空のまま残り、同じ名前が 2 つ並ぶ。**まだ誰も何も書いていない
  /// ときに限り**、その 1 人を片づける。すでに人を分けて使っている端末では
  /// 何も消さない。
  Future<void> restoreFrom(Uint8List bytes) async {
    final placeholder = users.all.length == 1 &&
            samples.collectedChars(includeTraced: true).isEmpty &&
            recipes.all.isEmpty
        ? users.current.id
        : null;

    await importBackup(db, bytes);
    await reload();

    if (placeholder != null && users.all.length > 1) {
      await users.remove(placeholder);
      await reload();
    }
  }

  /// 人を増やして、その人に切り替える。
  Future<User> addUser({required String name, required Avatar avatar}) async {
    final user = await users.create(name: name, avatar: avatar);
    await switchTo(user.id);
    return user;
  }
}
