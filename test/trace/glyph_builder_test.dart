import 'package:asoglyph/font/geometry.dart';
import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/trace/glyph_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// ブラウザで実際に書いた「あ」。3 画目が 2 画目を横切る。
///
/// この形が曲線の当てはめを暴走させ、制御点が em 枠の外（y = -479）へ飛んで、
/// 字形に細いヒゲが出ていた。
const _drawnA = [
  [
    [263.7, 838.7],
    [742.9, 836.3],
  ],
  [
    [475.7, 718.4],
    [440.2, 215.4],
  ],
  [
    [643.9, 502.5],
    [451.9, 263.9],
    [332.1, 407.7],
    [548.0, 431.6],
    [619.8, 263.9],
  ],
];

/// 折れ線を、書いたときのような点列に開く。
List<Stroke> _strokesOf(List<List<List<double>>> paths) {
  return [
    for (final path in paths)
      Stroke([
        for (var i = 0; i + 1 < path.length; i++)
          for (var s = (i == 0 ? 0 : 1); s <= 8; s++)
            InkPoint(
              x: path[i][0] + (path[i + 1][0] - path[i][0]) * s / 8,
              y: path[i][1] + (path[i + 1][1] - path[i][1]) * s / 8,
              t: (i * 8 + s) * 16,
            ),
      ]),
  ];
}

Iterable<Pt> _allPoints(Contour contour) sync* {
  yield contour.start;
  for (final seg in contour.segs) {
    switch (seg) {
      case LineSeg(:final to):
        yield to;
      case CubicSeg(:final c1, :final c2, :final to):
        yield c1;
        yield c2;
        yield to;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('字形が em 枠から飛び出さない', () async {
    final glyph = await buildGlyph(char: 'あ', strokes: _strokesOf(_drawnA));

    // 輪郭はラスタから起こすので、必ず em 0..1000 の中にある。制御点だけは
    // 当てはめの都合でわずかに外へ出るが、大きく外れるのは暴走した証拠。
    const margin = 50.0;
    for (final contour in glyph.contours) {
      for (final point in _allPoints(contour)) {
        expect(point.x, inInclusiveRange(-margin, 1000 + margin));
        expect(point.y, inInclusiveRange(-margin, 1000 + margin));
      }
    }
  });

  test('書いた線のとおりに輪郭が起きる', () async {
    final glyph = await buildGlyph(char: 'あ', strokes: _strokesOf(_drawnA));

    // 横棒 1 本、本体 1 本、本体が囲む穴 2 つ。
    expect(glyph.contours, hasLength(4));
    expect(glyph.advanceWidth, 1000);
  });
}
