// PWA のアイコンを作る。
//
//   flutter test tool/generate_web_icons.dart
//
// 出すのは web/icons/*.png と web/favicon.png。
//
// 画像編集ソフトを挟まず、アプリと同じ色・同じ書き取り枠で描く。色を変えたく
// なったときに、ここを直して流し直せば全部の大きさが揃う。
//
// 字は描かない。手書きの一画だけを描く。
//
// - フォントの字を焼き込むと、フォントを持たない環境（テストの実行環境も
//   そう）では豆腐になる。実際そうなった
// - KanjiVG の字形も使わない。使うとアイコンが KanjiVG の二次的著作物になり、
//   SA の条件がアイコンにまで及ぶ（SPEC 6.3）
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// アプリの色（ThemeData の seed と地の色）。
const _orange = Color(0xffe8863c);
const _cream = Color(0xfffaf7f0);

void main() {
  test('アイコンを書き出す', () async {
    // 端末のフォントを使うので、実際に字を持っている環境で流す。
    for (final size in [192, 512]) {
      await _write('web/icons/Icon-$size.png', size, safeArea: false);
      await _write('web/icons/Icon-maskable-$size.png', size, safeArea: true);
    }
    await _write('web/favicon.png', 64, safeArea: false);
  });
}

/// [safeArea] は maskable 用。丸く切り取られても字が欠けないよう、
/// 中身を内側 80% に収める（W3C の安全域）。
/// 枠の中に、手書きの一画を引く。
///
/// 特定の字にはしない。字にすると、その字を知らない子には読めないうえ、
/// フォントか KanjiVG のどちらかに寄りかかることになる。
/// 「枠の中に線を引く」ことがこのアプリのすることで、それだけを描く。
void _paintStroke(Canvas canvas, Rect frame) {
  final w = frame.width;
  final path = Path()
    ..moveTo(frame.left + w * 0.20, frame.top + w * 0.30)
    // 右上へ払ってから、大きく回して左下へ抜ける。子供の運筆の勢いを残す。
    ..cubicTo(
      frame.left + w * 0.62,
      frame.top + w * 0.10,
      frame.left + w * 0.92,
      frame.top + w * 0.36,
      frame.left + w * 0.70,
      frame.top + w * 0.62,
    )
    ..cubicTo(
      frame.left + w * 0.52,
      frame.top + w * 0.83,
      frame.left + w * 0.24,
      frame.top + w * 0.74,
      frame.left + w * 0.30,
      frame.top + w * 0.55,
    );

  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _orange,
  );
}

Future<void> _write(String path, int size, {required bool safeArea}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final side = size.toDouble();

  canvas.drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..color = _orange);

  // 書き取り枠。このアプリが何をするものかは、この枠がいちばん短く言う。
  final inset = side * (safeArea ? 0.19 : 0.13);
  final frame = Rect.fromLTRB(inset, inset, side - inset, side - inset);
  canvas.drawRRect(
    RRect.fromRectAndRadius(frame, Radius.circular(side * 0.06)),
    Paint()..color = _cream,
  );

  // 十字の補助線。薄く敷く。濃いと字より先に目に入る。
  final guide = Paint()
    ..color = _orange.withValues(alpha: 0.28)
    ..strokeWidth = side * 0.012;
  canvas
    ..drawLine(
      Offset(frame.center.dx, frame.top),
      Offset(frame.center.dx, frame.bottom),
      guide,
    )
    ..drawLine(
      Offset(frame.left, frame.center.dy),
      Offset(frame.right, frame.center.dy),
      guide,
    );

  _paintStroke(canvas, frame);

  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('$path (${size}x$size)');
}
