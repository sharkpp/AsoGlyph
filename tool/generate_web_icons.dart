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
//
// 描き方そのものは `lib/ui/app_mark.dart` が持つ。起動中の画面と同じ絵を
// 出すため（片方だけ直すと、ホーム画面のアイコンと開いた画面の印が違う
// ものになる）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:asoglyph/ui/app_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('アイコンを書き出す', () async {
    for (final size in [192, 512]) {
      await _write('web/icons/Icon-$size.png', size, safeArea: false);
      await _write('web/icons/Icon-maskable-$size.png', size, safeArea: true);
    }
    await _write('web/favicon.png', 64, safeArea: false);
  });
}

/// [safeArea] は maskable 用。丸く切り取られても字が欠けないよう、
/// 中身を内側 80% に収める（W3C の安全域）。
Future<void> _write(String path, int size, {required bool safeArea}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // 角は丸めない。端末の側が好きな形に切る。
  paintAppMark(canvas, size.toDouble(), safeArea: safeArea);

  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('$path (${size}x$size)');
}
