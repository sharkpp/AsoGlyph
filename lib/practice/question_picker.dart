/// 次に何の字を書かせるかを決める（SPEC 7.3）。
///
/// 2 つの目的の重み付けとして定義する。
///
/// - **収集カバレッジ優先** … まだ集めていない字を先に出す。
///   フォントが揃うまでは、こちらの重みを大きくする
/// - **難易度優先** … 苦手な字を繰り返し出す。
///   フォントが揃ってからは、こちらの重みを大きくする
///
/// 母集団は本人の履歴のみ。全ユーザー統計はサーバーが要るので採らない。
library;

import 'dart:math';

import '../model/user.dart';
import '../store/sample_store.dart';

/// 1 字ぶんの出しやすさ。
class Question {
  const Question({
    required this.char,
    required this.weight,
    required this.collected,
    required this.difficulty,
  });

  final String char;

  /// 出しやすさ。大きいほど出やすい。
  final double weight;

  /// なぞり以外で書けているか。
  final bool collected;

  /// 苦手さ 0..1。書いたことがない字は 0.5（分からないので真ん中）。
  final double difficulty;
}

/// 苦手さを出すときに見る、直近の試行数。
///
/// 昔うまく書けなかったことを、いつまでも引きずらせない。
const _recentAttempts = 5;

/// その字の苦手さ 0..1（SPEC 7.3）。
///
/// 直近の試行の点、かかった時間、書き直した回数から出す。はねた字
/// （鏡文字・書き損じ）も母集団に入れる。書けなかったという事実そのものが、
/// その字が苦手だという証拠になる。
double difficultyOf(String char, SampleStore store) {
  final attempts = store.attempts(char);
  if (attempts.isEmpty) return 0.5;

  final recent = attempts.length <= _recentAttempts
      ? attempts
      : attempts.sublist(attempts.length - _recentAttempts);

  var total = 0.0;
  for (final attempt in recent) {
    final score = attempt.score;
    // はねた字は、いちばん苦手だったものとして数える。
    if (attempt.rejected) {
      total += 1;
      continue;
    }
    if (score == null) {
      total += 0.5;
      continue;
    }
    // 書き直しとかかった時間も苦手さのうち（SPEC 7.3）。どちらも
    // 上限を決めて足す。1 回書き直しただけで最難になっては困る。
    final struggle =
        (score.retries / 4).clamp(0.0, 1.0) * 0.15 +
        (score.durationMs / 20000).clamp(0.0, 1.0) * 0.1;
    total += ((1 - score.overall) * 0.75 + struggle).clamp(0.0, 1.0);
  }
  return total / recent.length;
}

/// 出題の候補を、出しやすさとともに並べる。
///
/// [coverageBias] は収集カバレッジをどれだけ優先するか（0..1）。
/// 既定は充足率から決める。埋まっていないうちは未収集を優先し、
/// 埋まるにつれて苦手な字の反復へ移る。
List<Question> questionsFor(
  User user,
  SampleStore store, {
  double? coverageBias,
}) {
  final chars = [
    for (final charSet in user.visibleCharSets) ...charSet.chars,
  ];
  if (chars.isEmpty) return const [];

  final collected = {
    for (final char in chars)
      char: store.latestId(char, includeTraced: false) != null,
  };
  final filled = collected.values.where((done) => done).length / chars.length;
  // 充足率がそのまま「未収集をどれだけ優先するか」になる。
  final bias = coverageBias ?? (1 - filled);

  return [
    for (final char in chars)
      () {
        final difficulty = difficultyOf(char, store);
        final coverage = collected[char]! ? 0.0 : 1.0;
        // 重みは必ず正にする。0 にすると、その字は二度と出なくなる。
        final weight =
            0.05 + coverage * bias + difficulty * (1 - bias) * 0.9;
        return Question(
          char: char,
          weight: weight,
          collected: collected[char]!,
          difficulty: difficulty,
        );
      }(),
  ];
}

/// 次に出す字を [count] 字選ぶ。
///
/// 重みつきの抽選にする。上位から順に出すと、同じ字ばかりが続いて飽きる。
/// 同じ字は 1 回のまとまりの中で 2 度出さない。
List<String> pickQuestions(
  User user,
  SampleStore store, {
  int count = 5,
  Random? random,
}) {
  final pool = questionsFor(user, store).toList();
  final rng = random ?? Random();
  final picked = <String>[];

  while (picked.length < count && pool.isNotEmpty) {
    final total = pool.fold(0.0, (sum, question) => sum + question.weight);
    var threshold = rng.nextDouble() * total;
    var index = pool.length - 1;
    for (var i = 0; i < pool.length; i++) {
      threshold -= pool[i].weight;
      if (threshold <= 0) {
        index = i;
        break;
      }
    }
    picked.add(pool.removeAt(index).char);
  }
  return picked;
}
