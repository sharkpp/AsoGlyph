import 'package:uuid/uuid.dart';

import '../ink/stroke.dart';

/// 練習モード（SPEC 7.1）。
enum PracticeMode {
  /// なぞり書き。入口としてのみ提供し、フォントの素材には採用しない。
  trace,

  /// お手本を見て書く。
  copy,

  /// 何も見ずに書く。
  free;

  /// フォントの素材として採用してよいか。
  bool get isFontMaterial => this != PracticeMode.trace;
}

/// 1 回の試行。唯一の実データであり、不変・追記のみで削除しない（SPEC 4.1）。
class Sample {
  const Sample({
    required this.id,
    required this.char,
    required this.mode,
    required this.writtenAt,
    required this.strokes,
  });

  /// 書いたその場で作る。id と時刻はここでしか決めない。
  factory Sample.now({
    required String char,
    required PracticeMode mode,
    required List<Stroke> strokes,
  }) {
    return Sample(
      // v7 は時刻を先頭に持つため、id 順がそのまま書いた順になる。
      id: const Uuid().v7(),
      char: char,
      mode: mode,
      writtenAt: DateTime.now(),
      strokes: strokes,
    );
  }

  final String id;

  /// 対象文字 1 字。
  final String char;

  final PracticeMode mode;
  final DateTime writtenAt;

  /// 正規化 em 空間（0..1000）の運筆。
  final List<Stroke> strokes;

  bool get isEmpty => strokes.every((s) => s.isEmpty);
}
