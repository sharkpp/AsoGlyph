/// アプリの印。起動画面と PWA のアイコンで同じものを描く。
///
/// 字は描かない。**枠の中に線を引く**ことがこのアプリのすることで、それだけを
/// 描く。特定の字にすると、その字を知らない子には読めないうえ、フォントか
/// KanjiVG のどちらかに寄りかかることになる（SPEC 6.3）。
///
/// 描き方をここ 1 つに置くのは、アイコン（`tool/generate_web_icons.dart`）と
/// 起動画面で別の絵が出ないようにするため。片方だけ直すと、ホーム画面の
/// アイコンと開いた画面の印が違うものになる。
library;

import 'package:flutter/widgets.dart';

/// アプリの色（[ThemeData] の seed と地の色）。
const appOrange = Color(0xffe8863c);
const appCream = Color(0xfffaf7f0);

/// 印を [side] の正方形に描く。左上は原点。
///
/// [safeArea] は maskable アイコン用。丸く切り取られても中身が欠けないよう、
/// 内側 80% に収める（W3C の安全域）。
///
/// [radius] は地の角丸。アイコンでは 0（端末の側が好きな形に切る）、画面に
/// 出すときは丸めて、アイコンとして見えるようにする。
void paintAppMark(
  Canvas canvas,
  double side, {
  bool safeArea = false,
  double radius = 0,
}) {
  final ground = Rect.fromLTWH(0, 0, side, side);
  if (radius <= 0) {
    canvas.drawRect(ground, Paint()..color = appOrange);
  } else {
    canvas.drawRRect(
      RRect.fromRectAndRadius(ground, Radius.circular(radius)),
      Paint()..color = appOrange,
    );
  }

  // 書き取り枠。このアプリが何をするものかは、この枠がいちばん短く言う。
  final inset = side * (safeArea ? 0.19 : 0.13);
  final frame = Rect.fromLTRB(inset, inset, side - inset, side - inset);
  canvas.drawRRect(
    RRect.fromRectAndRadius(frame, Radius.circular(side * 0.06)),
    Paint()..color = appCream,
  );

  // 十字の補助線。薄く敷く。濃いと字より先に目に入る。
  final guide = Paint()
    ..color = appOrange.withValues(alpha: 0.28)
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
}

/// 枠の中に、手書きの一画を引く。
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
      ..color = appOrange,
  );
}

/// 画面に出す印。起動中の画面に置く。
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: const _MarkPainter(),
    isComplex: true,
    willChange: false,
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) =>
      paintAppMark(canvas, size.shortestSide, radius: size.shortestSide * 0.22);

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
