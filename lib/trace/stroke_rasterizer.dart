import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../ink/stroke.dart';

/// 線幅の決め方。
class StrokeStyle {
  const StrokeStyle({
    this.baseWidth = 56,
    this.pressureRange = 0.5,
    this.speedRange = 0.4,
    this.referenceSpeed = 2.0,
  });

  /// em 単位の基準線幅。
  final double baseWidth;

  /// 筆圧で変化させる幅の割合。
  final double pressureRange;

  /// 速度で変化させる幅の割合。筆圧が取れない入力で使う。
  final double speedRange;

  /// この速度（em/ミリ秒）で線幅が下限になる。
  final double referenceSpeed;
}

/// ストローク列を描画してアルファ値の場を得る。
///
/// SPEC 8.1 のラスタトレース方式の入口。Skia に一度描かせることで、画の重なりや
/// 自己交差の解決を任せる。ここで描いた形がそのままフォントの字形になるため、
/// 練習画面の描画と同じ経路を通すことに意味がある。
Future<Uint8List> rasterizeStrokes({
  required List<Stroke> strokes,
  required int imageSize,
  double emSize = 1000,
  StrokeStyle style = const StrokeStyle(),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final scale = imageSize / emSize;

  final paint = ui.Paint()
    ..color = const ui.Color(0xff000000)
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..isAntiAlias = true;

  // em 空間は y が上向き、キャンバスは下向き。
  ui.Offset toCanvas(InkPoint p) =>
      ui.Offset(p.x * scale, (emSize - p.y) * scale);

  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    final widths = strokeWidths(stroke, style);

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        toCanvas(stroke.points.first),
        widths.first * scale / 2,
        ui.Paint()..color = const ui.Color(0xff000000),
      );
      continue;
    }

    for (var i = 1; i < stroke.points.length; i++) {
      paint.strokeWidth = (widths[i - 1] + widths[i]) / 2 * scale;
      canvas.drawLine(
        toCanvas(stroke.points[i - 1]),
        toCanvas(stroke.points[i]),
        paint,
      );
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(imageSize, imageSize);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();

  if (data == null) return Uint8List(imageSize * imageSize);

  // RGBA から alpha だけ取り出す。
  final rgba = data.buffer.asUint8List();
  final alpha = Uint8List(imageSize * imageSize);
  for (var i = 0; i < alpha.length; i++) {
    alpha[i] = rgba[i * 4 + 3];
  }
  return alpha;
}

/// 各点での線幅を em 単位で求める。
///
/// 筆圧が取れる入力（スタイラス）では筆圧を、取れない入力（指・マウス）では
/// 速度を使う。速いほど細くするのは、運筆の勢いを字形に残すため。
List<double> strokeWidths(Stroke stroke, StrokeStyle style) {
  final points = stroke.points;
  if (points.isEmpty) return const [];

  if (stroke.hasPressure) {
    return [
      for (final point in points)
        style.baseWidth *
            (1 - style.pressureRange + style.pressureRange * 2 * point.pressure)
                .clamp(1 - style.pressureRange, 1 + style.pressureRange),
    ];
  }

  final widths = <double>[];
  for (var i = 0; i < points.length; i++) {
    final previous = points[i == 0 ? 0 : i - 1];
    final current = points[i];
    final dt = (current.t - previous.t).abs();
    final distance = math.sqrt(
      math.pow(current.x - previous.x, 2) + math.pow(current.y - previous.y, 2),
    );
    final speed = dt == 0 ? 0.0 : distance / dt;
    final ratio = (speed / style.referenceSpeed).clamp(0.0, 1.0);
    widths.add(style.baseWidth * (1 - style.speedRange * ratio));
  }
  return widths;
}
