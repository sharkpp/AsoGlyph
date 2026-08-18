import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../model/word.dart';

/// 単語トライアルの置き場（SPEC 4.2）。
///
/// 「単語単位で履歴を持つ」という要求の実体。書いた記録そのものは
/// [SampleStore] にあり、こちらは並びだけを持つ。記録と同じく人ごとに
/// 分かれる（SPEC 7.5）。
class WordAttemptStore extends ChangeNotifier {
  WordAttemptStore(this._db, {required this.userId});

  static Future<WordAttemptStore> open(
    Database db, {
    required String userId,
  }) async {
    final store = WordAttemptStore(db, userId: userId);
    await store.load();
    return store;
  }

  /// いま読み書きしている人。
  String userId;

  Future<void> useUser(String id) async {
    if (userId == id) return;
    userId = id;
    await load();
  }

  static final _attempts = stringMapStoreFactory.store('wordAttempts');

  final Database _db;

  final List<WordAttempt> _all = [];

  /// 書き終えた順に並ぶ。
  List<WordAttempt> get all => List.unmodifiable(_all);

  Future<void> load() async {
    _all
      ..clear()
      ..addAll(
        (await _attempts.find(
          _db,
          finder: Finder(
            filter: Filter.equals('userId', userId),
            sortOrders: [SortOrder('finishedAt')],
          ),
        )).map(
          (record) => WordAttempt(
            id: record.key,
            word: record.value['word']! as String,
            sampleIds: (record.value['sampleIds']! as List).cast<String>(),
            finishedAt: DateTime.fromMillisecondsSinceEpoch(
              record.value['finishedAt']! as int,
            ),
          ),
        ),
      );
    notifyListeners();
  }

  /// 語を最後まで書けたことを残す。
  Future<WordAttempt> finish({
    required String word,
    required List<String> sampleIds,
  }) async {
    final attempt = WordAttempt(
      id: const Uuid().v7(),
      word: word,
      sampleIds: sampleIds,
      finishedAt: DateTime.now(),
    );
    await _attempts.record(attempt.id).put(_db, {
      'userId': userId,
      'word': attempt.word,
      'sampleIds': attempt.sampleIds,
      'finishedAt': attempt.finishedAt.millisecondsSinceEpoch,
    });
    _all.add(attempt);
    notifyListeners();
    return attempt;
  }

  /// その語を最後まで書けた回数。単語帳の一覧に印を出すのに使う。
  int countOf(String word) =>
      _all.where((attempt) => attempt.word == word).length;
}
