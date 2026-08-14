import 'dart:typed_data';

import '../font/geometry.dart';
import 'fit_curves.dart';
import 'marching_squares.dart';
import 'simplify.dart';

/// アルファ値の場からフォントの輪郭を起こす。
///
/// SPEC 8.1 のラスタトレース方式。ストロークの中心線をブーリアン演算で合成せず、
/// 一度描画してから輪郭を追う。自己交差や画の重なりを考えなくてよいうえ、
/// 練習画面で子供が見た線とフォントの字形が一致する。
///
/// 誤差の指定はすべて em 単位。画像の解像度を上げても字形の粗さが変わらないよう、
/// em 空間へ移してから間引きと当てはめを行う。
class ContourTracer {
  const ContourTracer({
    this.threshold = 128,
    this.simplifyTolerance = 0.6,
    this.fitError = 1.2,
    this.minimumArea = 50.0,
  });

  /// 等値線の高さ。アンチエイリアスされたアルファの中間値を取る。
  final int threshold;

  /// RDP の許容誤差。
  final double simplifyTolerance;

  /// 3 次ベジェ当てはめの許容誤差。
  final double fitError;

  /// これより小さい輪郭は描画のノイズとみなして捨てる。
  final double minimumArea;

  /// [alpha] は width*height のアルファ値。画像は正方形を前提とする。
  List<Contour> trace({
    required Uint8List alpha,
    required int imageSize,
    double emSize = 1000,
  }) {
    final polygons = traceContours(
      alpha: alpha,
      width: imageSize,
      height: imageSize,
      threshold: threshold,
    );

    // 画像空間（左上原点・y 下向き）から em 空間（左下原点・y 上向き）へ。
    // y を反転すると巻き方向も反転するため、向きを揃えるのはこの後で行う。
    final scale = emSize / imageSize;
    final inEm = [
      for (final polygon in polygons)
        [for (final p in polygon) Pt(p.x * scale, (imageSize - p.y) * scale)],
    ];

    final kept = [
      for (final polygon in inEm)
        if (signedArea(polygon).abs() / 2 >= minimumArea) polygon,
    ];

    return [for (final polygon in normalizeWinding(kept)) _toContour(polygon)];
  }

  Contour _toContour(List<Pt> polygon) {
    final simplified = simplifyClosed(polygon, simplifyTolerance);
    final pieces = splitAtCorners(simplified, closed: true);

    final segs = <Seg>[];
    for (final piece in pieces) {
      segs.addAll(fitCubics(piece, fitError));
    }
    return Contour(pieces.first.first, segs);
  }
}
