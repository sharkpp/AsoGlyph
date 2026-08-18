/// 1 回の試行の測り（SPEC 4.1）。
///
/// **出題の重み付けにだけ使う。フォントへの採用可否には使わない。**
/// 子供の字の魅力はその歪みにあり、整った字を書かせることが目的ではない
/// （SPEC 1）。ここで低く出た字も、そのままフォントに載る。
///
/// 例外は鏡文字と明らかな書き損じだけで、それは [Sample.rejected] が持つ。
class Score {
  const Score({
    required this.shape,
    required this.strokes,
    required this.fit,
    required this.durationMs,
    required this.retries,
  });

  /// お手本との形の近さ 0..1。書き順データが無い字では null。
  final double? shape;

  /// 画数の一致 0..1。書き順データが無い字では null。
  final double? strokes;

  /// 枠への収まり 0..1。お手本と同じ大きさ・位置に書けているか。
  ///
  /// 書き取り面は入力を枠内に丸めるので、はみ出しそのものは記録に残らない
  /// （SPEC 4.1 の正規化 em 空間）。代わりに、お手本と比べて小さすぎないか・
  /// 寄りすぎていないかを見る。フォントに載せたとき字の大きさが揃わない
  /// のは、はみ出しではなくこちらが原因になる。
  final double? fit;

  /// 書き上げるまでにかかった時間（ミリ秒）。画をまたいだ間は数えない。
  final int durationMs;

  /// 「もういちど」を押した回数。
  final int retries;

  /// 形・画数・収まりをまとめた 0..1。測れないものは外して平均する。
  double get overall {
    final terms = <(double, double)>[
      if (shape != null) (shape!, 0.5),
      if (strokes != null) (strokes!, 0.3),
      if (fit != null) (fit!, 0.2),
    ];
    if (terms.isEmpty) return 0.5;
    final weight = terms.fold(0.0, (sum, term) => sum + term.$2);
    return terms.fold(0.0, (sum, term) => sum + term.$1 * term.$2) / weight;
  }

  Map<String, Object?> toRecord() => {
    'shape': shape,
    'strokes': strokes,
    'fit': fit,
    'durationMs': durationMs,
    'retries': retries,
  };

  static Score fromRecord(Map<String, Object?> record) => Score(
    shape: (record['shape'] as num?)?.toDouble(),
    strokes: (record['strokes'] as num?)?.toDouble(),
    fit: (record['fit'] as num?)?.toDouble(),
    durationMs: (record['durationMs'] as num?)?.toInt() ?? 0,
    retries: (record['retries'] as num?)?.toInt() ?? 0,
  );
}
