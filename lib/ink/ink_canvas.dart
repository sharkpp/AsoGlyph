import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../trace/stroke_rasterizer.dart';
import 'ink_controller.dart';
import 'stroke.dart';

/// 手書きの入力面。
///
/// 常に正方形として使う。書き取り面の縦横比が変わると字形が歪むため、
/// レイアウト側で `AspectRatio` を掛けて渡すこと。
///
/// 確定した画と描画中の 1 画を別の層に分ける。`RepaintBoundary` で切り、
/// 確定側の `shouldRepaint` を画数の変化だけに絞ることで、運筆中に確定側を
/// 描き直さない（SPEC 9）。
class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.controller,
    this.emSize = 1000,
    this.style = const StrokeStyle(),
    this.inkColor = const Color(0xff1a1a1a),
  });

  final InkController controller;
  final double emSize;
  final StrokeStyle style;
  final Color inkColor;

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<InkCanvas> {
  /// スタイラスが接地している間はタッチを無視する（パームリジェクション）。
  int? _activePointer;
  bool _stylusInUse = false;

  double _emX(Offset local, double size) =>
      (local.dx / size * widget.emSize).clamp(0.0, widget.emSize);

  /// 画面は y が下向き、em 空間は上向き。
  double _emY(Offset local, double size) =>
      ((size - local.dy) / size * widget.emSize).clamp(0.0, widget.emSize);

  bool _shouldIgnore(PointerEvent event) {
    if (event.kind == PointerDeviceKind.stylus) return false;
    return _stylusInUse && event.kind == PointerDeviceKind.touch;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_shouldIgnore(event)) return;
            // 置かれたまま動いていない指は、あとから触れた指に譲る。
            // 画面に手を置いたまま書き始める子がいて、譲らないと以降の入力が
            // すべて無視され、書いたものが 1 画も残らない。
            if (_activePointer != null && widget.controller.activeHasMoved) {
              return;
            }
            if (event.kind == PointerDeviceKind.stylus) _stylusInUse = true;
            _activePointer = event.pointer;
            widget.controller.begin(
              _emX(event.localPosition, size),
              _emY(event.localPosition, size),
              _pressureOf(event),
            );
          },
          onPointerMove: (event) {
            if (event.pointer != _activePointer) return;
            widget.controller.extend(
              _emX(event.localPosition, size),
              _emY(event.localPosition, size),
              _pressureOf(event),
            );
          },
          onPointerUp: (event) {
            if (event.pointer != _activePointer) return;
            _activePointer = null;
            widget.controller.end();
          },
          onPointerCancel: (event) {
            if (event.pointer != _activePointer) return;
            _activePointer = null;
            widget.controller.end();
          },
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                // 確定した画。運筆中は描き直さない。
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _StrokePainter(
                      strokes: widget.controller.strokes,
                      emSize: widget.emSize,
                      style: widget.style,
                      color: widget.inkColor,
                    ),
                  ),
                ),
                // 描画中の 1 画だけ。
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _StrokePainter(
                      strokes: [?widget.controller.activeStroke],
                      emSize: widget.emSize,
                      style: widget.style,
                      color: widget.inkColor,
                      repaintAlways: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 筆圧を取れない入力では 0 を返す。線幅は速度から決める。
double _pressureOf(PointerEvent event) {
  if (event.kind != PointerDeviceKind.stylus) return 0;
  final range = event.pressureMax - event.pressureMin;
  if (range <= 0) return 0;
  return ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter({
    required this.strokes,
    required this.emSize,
    required this.style,
    required this.color,
    this.repaintAlways = false,
  });

  final List<Stroke> strokes;
  final double emSize;
  final StrokeStyle style;
  final Color color;
  final bool repaintAlways;

  @override
  void paint(Canvas canvas, Size size) {
    paintStrokes(
      canvas: canvas,
      strokes: strokes,
      pixelSize: size.shortestSide,
      emSize: emSize,
      style: style,
      color: color,
    );
  }

  @override
  bool shouldRepaint(_StrokePainter old) {
    if (repaintAlways) return true;
    // 確定側は画数が変わったときだけ描き直す。
    return old.strokes.length != strokes.length || old.color != color;
  }
}
