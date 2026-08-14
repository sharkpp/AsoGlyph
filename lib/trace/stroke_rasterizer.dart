import 'dart:typed_data';
import 'dart:ui' as ui;

import '../ink/stroke.dart';
import '../ink/stroke_geometry.dart';

export '../ink/stroke_geometry.dart' show StrokeStyle;

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

  paintStrokes(
    canvas: canvas,
    strokes: strokes,
    pixelSize: imageSize.toDouble(),
    emSize: emSize,
    style: style,
    color: const ui.Color(0xff000000),
  );

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

/// 運筆をキャンバスへ描く。
///
/// 練習画面の表示とフォント生成のラスタ化は、必ずこの 1 つの実装を通す。
/// 描き方がずれると「子供が見た線とフォントの字形が一致する」という
/// ラスタトレース方式の利点（SPEC 8.1）が失われるため。
void paintStrokes({
  required ui.Canvas canvas,
  required List<Stroke> strokes,
  required double pixelSize,
  required double emSize,
  required StrokeStyle style,
  required ui.Color color,
}) {
  final scale = pixelSize / emSize;
  final paint = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..isAntiAlias = true;
  final dotPaint = ui.Paint()
    ..color = color
    ..isAntiAlias = true;

  // em 空間は y が上向き、キャンバスは下向き。
  ui.Offset toCanvas(RenderPoint p) =>
      ui.Offset(p.x * scale, (emSize - p.y) * scale);

  for (final stroke in strokes) {
    final points = renderPoints(stroke, style);
    if (points.isEmpty) continue;

    if (points.length == 1) {
      canvas.drawCircle(
        toCanvas(points.first),
        points.first.width * scale / 2,
        dotPaint,
      );
      continue;
    }

    for (var i = 1; i < points.length; i++) {
      paint.strokeWidth = (points[i - 1].width + points[i].width) / 2 * scale;
      canvas.drawLine(toCanvas(points[i - 1]), toCanvas(points[i]), paint);
    }
  }
}
