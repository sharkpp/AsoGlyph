import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../model/user.dart';
import 'recipe_store.dart';
import 'sample_store.dart';
import 'user_store.dart';

/// いま誰が書いているか、と、その人の記録・版（SPEC 7.5）。
///
/// 人を切り替えると、記録も版もまとめて入れ替わる。3 つのストアを別々に
/// 切り替えると、片方だけ前の人のままという状態が作れてしまう。
/// 切り替えの手順をここ 1 か所に閉じ込める。
class Session extends ChangeNotifier {
  Session({
    required this.users,
    required this.samples,
    required this.recipes,
  });

  static Future<Session> open(Database db) async {
    final users = await UserStore.open(db);
    return Session(
      users: users,
      samples: await SampleStore.open(db, userId: users.current.id),
      recipes: await RecipeStore.open(db, userId: users.current.id),
    );
  }

  final UserStore users;
  final SampleStore samples;
  final RecipeStore recipes;

  User get current => users.current;

  /// 書く人を切り替える。
  Future<void> switchTo(String userId) async {
    if (users.current.id == userId) return;
    await users.select(userId);
    await samples.useUser(userId);
    await recipes.useUser(userId);
    notifyListeners();
  }

  /// 人を増やして、その人に切り替える。
  Future<User> addUser({required String name, required Avatar avatar}) async {
    final user = await users.create(name: name, avatar: avatar);
    await switchTo(user.id);
    return user;
  }
}
