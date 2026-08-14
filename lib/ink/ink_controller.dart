import 'package:flutter/foundation.dart';

import 'stroke.dart';

/// 書いている最中の運筆を保持する。
///
/// 座標は正規化 em 空間（0..1000）で受け取る。端末の解像度に依存する値は
/// ここより先に持ち込まない（SPEC 4.1）。
class InkController extends ChangeNotifier {
  final List<Stroke> _strokes = [];
  final List<InkPoint> _active = [];
  Stopwatch? _clock;

  /// 書き終えた画。
  List<Stroke> get strokes => List.unmodifiable(_strokes);

  /// 描いている最中の 1 画。まだ確定していない。
  Stroke? get activeStroke => _active.isEmpty ? null : Stroke(List.of(_active));

  bool get isEmpty => _strokes.isEmpty && _active.isEmpty;

  /// 確定した画とその時点の描画中の画を合わせたもの。
  List<Stroke> get allStrokes => [
    ..._strokes,
    if (_active.isNotEmpty) Stroke(List.of(_active)),
  ];

  void begin(double x, double y, double pressure) {
    _clock = Stopwatch()..start();
    _active
      ..clear()
      ..add(InkPoint(x: x, y: y, t: 0, pressure: pressure));
    notifyListeners();
  }

  void extend(double x, double y, double pressure) {
    if (_active.isEmpty) return;
    _active.add(
      InkPoint(
        x: x,
        y: y,
        t: _clock?.elapsedMilliseconds ?? 0,
        pressure: pressure,
      ),
    );
    notifyListeners();
  }

  void end() {
    _clock?.stop();
    _clock = null;
    if (_active.isEmpty) return;
    _strokes.add(Stroke(List.of(_active)));
    _active.clear();
    notifyListeners();
  }

  void undo() {
    if (_active.isNotEmpty) {
      _active.clear();
    } else if (_strokes.isNotEmpty) {
      _strokes.removeLast();
    }
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    _active.clear();
    _clock = null;
    notifyListeners();
  }
}
