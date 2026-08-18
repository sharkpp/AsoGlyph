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
            // 同じミリ秒に作られたときは id で決める。UUID v7 はミリ秒から
            // 先が乱数なので作った順にはならないが、開くたびに変わることは
            // なくなる。版も単語トライアルも、人の操作 1 つにつき 1 つしか
            // 増えないので、これで足りる。
            sortOrders: [SortOrder('finishedAt'), SortOrder(Field.key)],
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

  /// 語ごとのまとめ。最後に書いたのが新しい順。
  ///
  /// 管理画面で、どの語を書いたかを見せて消せるようにするのに使う。
  List<WordHistory> get byWord {
    final counts = <String, int>{};
    final last = <String, DateTime>{};
    for (final attempt in _all) {
      counts[attempt.word] = (counts[attempt.word] ?? 0) + 1;
      final at = last[attempt.word];
      if (at == null || attempt.finishedAt.isAfter(at)) {
        last[attempt.word] = attempt.finishedAt;
      }
    }
    return [
      for (final word in counts.keys)
        WordHistory(word: word, count: counts[word]!, lastAt: last[word]!),
    ]..sort((a, b) => b.lastAt.compareTo(a.lastAt));
  }

  /// その語の履歴を消す（SPEC 4.2）。
  ///
  /// **書いた字は消えない。** 消えるのは「この語を書き終えた」という印だけで、
  /// 1 字ずつの記録は [SampleStore] にそのまま残る（SPEC 4.1）。
  /// 星が付いたままだと、もう一度書かせたい語を子供が選ばなくなる。
  Future<void> removeWord(String word) async {
    final ids = [
      for (final attempt in _all)
        if (attempt.word == word) attempt.id,
    ];
    if (ids.isEmpty) return;
    await _attempts.records(ids).delete(_db);
    _all.removeWhere((attempt) => attempt.word == word);
    notifyListeners();
  }

  /// いまの人の履歴を全部消す。書いた字は消えない。
  Future<void> clear() async {
    if (_all.isEmpty) return;
    // ほかの人の履歴は消さない。
    await _attempts.records([for (final a in _all) a.id]).delete(_db);
    _all.clear();
    notifyListeners();
  }
}

/// 語ごとの書いた履歴のまとめ。
class WordHistory {
  const WordHistory({
    required this.word,
    required this.count,
    required this.lastAt,
  });

  final String word;
  final int count;
  final DateTime lastAt;
}
