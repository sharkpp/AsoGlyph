import 'package:uuid/uuid.dart';

import '../ink/stroke.dart';
import 'score.dart';

/// 練習モード（SPEC 7.1）。
enum PracticeMode {
  /// なぞり書き。入口としてのみ提供し、フォントの素材には採用しない。
  trace,

  /// お手本を見て書く。
  copy,

  /// 何も見ずに書く。
  free;
}

/// 1 回の試行。唯一の実データであり、不変・追記のみで削除しない（SPEC 4.1）。
class Sample {
  const Sample({
    required this.id,
    required this.char,
    required this.mode,
    required this.writtenAt,
    required this.strokes,
    this.score,
    this.rejected = false,
  });

  /// 書いたその場で作る。id と時刻はここでしか決めない。
  factory Sample.now({
    required String char,
    required PracticeMode mode,
    required List<Stroke> strokes,
    Score? score,
    bool rejected = false,
  }) {
    return Sample(
      // v7 は時刻を先頭に持つため、id 順がそのまま書いた順になる。
      id: const Uuid().v7(),
      char: char,
      mode: mode,
      writtenAt: DateTime.now(),
      strokes: strokes,
      score: score,
      rejected: rejected,
    );
  }

  final String id;

  /// 対象文字 1 字。
  final String char;

  final PracticeMode mode;
  final DateTime writtenAt;

  /// 正規化 em 空間（0..1000）の運筆。
  final List<Stroke> strokes;

  /// 出題の重み付けに使う測り。採用可否には使わない（SPEC 4.1）。
  final Score? score;

  /// 鏡文字・明らかな書き損じ。**ここだけがフォントへの採否に効く。**
  final bool rejected;

  bool get isEmpty => strokes.every((s) => s.isEmpty);
}
