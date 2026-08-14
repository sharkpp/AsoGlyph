/// 運筆の 1 点。
///
/// 座標は正規化された em 空間（0..1000、左下原点・y 上向き）で持つ。
/// デバイスピクセルで保存すると、スマホとタブレットで書いた字の大きさが揃わず
/// フォントが破綻するため、端末の解像度に依存する値は残さない（SPEC 4.1）。
class InkPoint {
  const InkPoint({
    required this.x,
    required this.y,
    required this.t,
    this.pressure = 0,
  });

  final double x;
  final double y;

  /// ストローク開始からの経過ミリ秒。
  final int t;

  /// 0..1。取得できない入力（指・マウス）では 0 のままにする。
  final double pressure;
}

/// ひと続きの運筆（1 画）。
class Stroke {
  const Stroke(this.points);

  final List<InkPoint> points;

  bool get isEmpty => points.isEmpty;

  /// 筆圧が取れた入力かどうか。スタイラスでのみ真になる。
  bool get hasPressure => points.any((p) => p.pressure > 0);

  /// 描画にかかった時間（ミリ秒）。
  int get duration => points.isEmpty ? 0 : points.last.t - points.first.t;
}
