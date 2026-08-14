import 'dart:io';
import 'dart:typed_data';

import 'package:asoglyph/font/cubic_to_quadratic.dart';
import 'package:asoglyph/font/font_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final meta = FontMetadata(familyName: 'AsoGlyph Sample');
  final glyphs = _sampleGlyphs();

  group('sfnt コンテナ', () {
    test('TTF は TrueType のバージョンと必須テーブルを持つ', () {
      final font = buildFont(
        meta: meta,
        glyphs: glyphs,
        format: FontFormat.ttf,
      );
      final tables = _readTableDirectory(font);

      expect(_readUint32(font, 0), 0x00010000);
      expect(
        tables.keys,
        containsAll([
          'OS/2',
          'cmap',
          'glyf',
          'head',
          'hhea',
          'hmtx',
          'loca',
          'maxp',
          'name',
          'post',
        ]),
      );
      expect(tables.containsKey('CFF '), isFalse);
    });

    test('OTF は OTTO と CFF テーブルを持ち glyf を持たない', () {
      final font = buildFont(
        meta: meta,
        glyphs: glyphs,
        format: FontFormat.otf,
      );
      final tables = _readTableDirectory(font);

      expect(String.fromCharCodes(font.sublist(0, 4)), 'OTTO');
      expect(tables.keys, contains('CFF '));
      expect(tables.containsKey('glyf'), isFalse);
      expect(tables.containsKey('loca'), isFalse);
    });

    test('テーブルディレクトリはタグ昇順で 4 バイト境界に並ぶ', () {
      final font = buildFont(
        meta: meta,
        glyphs: glyphs,
        format: FontFormat.ttf,
      );
      final tables = _readTableDirectory(font);

      final tags = tables.keys.toList();
      expect(tags, orderedEquals([...tags]..sort()));
      for (final entry in tables.values) {
        expect(entry.offset % 4, 0, reason: 'テーブル開始位置が 4 の倍数でない');
      }
    });

    test('head のチェックサムから求めた総和が規定値になる', () {
      final font = buildFont(
        meta: meta,
        glyphs: glyphs,
        format: FontFormat.ttf,
      );
      expect(_checksum(font), 0xb1b0afba);
    });

    test('同じ入力からは常に同じバイト列が出る', () {
      // FontRecipe による再現可能な生成は、この性質に依存する。
      for (final format in FontFormat.values) {
        final a = buildFont(meta: meta, glyphs: glyphs, format: format);
        final b = buildFont(meta: meta, glyphs: glyphs, format: format);
        expect(a, orderedEquals(b), reason: '$format が非決定的');
      }
    });
  });

  group('cmap', () {
    test('登録した文字がすべて引ける', () {
      final font = buildFont(
        meta: meta,
        glyphs: glyphs,
        format: FontFormat.ttf,
      );
      final lookup = _readCmap(font);

      for (final glyph in glyphs) {
        expect(
          lookup[glyph.codePoint],
          isNotNull,
          reason: 'U+${glyph.codePoint.toRadixString(16)} が cmap にない',
        );
        expect(lookup[glyph.codePoint], greaterThan(0), reason: '.notdef に落ちている');
      }
      expect(lookup[0x20], isNotNull, reason: 'スペースは常に含める');
      expect(lookup[0x3044], isNull, reason: '未収集の文字を載せてはならない');
    });
  });

  group('3 次から 2 次への近似', () {
    test('許容誤差の範囲に収まる', () {
      const p0 = Pt(0, 0);
      const p1 = Pt(100, 400);
      const p2 = Pt(500, 400);
      const p3 = Pt(600, 0);
      const tolerance = 0.5;

      final quads = cubicToQuadratics(p0, p1, p2, p3, tolerance: tolerance);
      expect(quads, isNotEmpty);
      expect(quads.last.to, p3, reason: '終点がずれてはならない');

      // 2 次側は折れ線に展開し、線分までの距離で測る。点の集合との最近傍距離では
      // サンプル間隔ぶんが誤差に上乗せされ、近似の精度を測れない。
      final polyline = <Pt>[];
      var from = p0;
      for (final quad in quads) {
        for (var i = 0; i <= 64; i++) {
          polyline.add(_quadAt(from, quad.control, quad.to, i / 64));
        }
        from = quad.to;
      }

      var worst = 0.0;
      for (var i = 0; i <= 400; i++) {
        final point = _cubicAt(p0, p1, p2, p3, i / 400);
        var nearest = double.infinity;
        for (var j = 0; j < polyline.length - 1; j++) {
          final d = _distanceToSegment(point, polyline[j], polyline[j + 1]);
          if (d < nearest) nearest = d;
        }
        if (nearest > worst) worst = nearest;
      }
      expect(worst, lessThanOrEqualTo(tolerance));
    });

    test('直線に近い曲線は分割されない', () {
      final quads = cubicToQuadratics(
        const Pt(0, 0),
        const Pt(10, 0),
        const Pt(20, 0),
        const Pt(30, 0),
      );
      expect(quads.length, 1);
    });
  });

  group('輪郭', () {
    test('反転すると巻き方向が変わり、元に戻せる', () {
      final contour = _rect(100, 100, 400, 400);
      expect(contour.isClockwise, isTrue);

      final reversed = contour.reversed();
      expect(reversed.isClockwise, isFalse);
      expect(reversed.segs.length, contour.segs.length);

      final restored = reversed.reversed();
      expect(restored.isClockwise, isTrue);
      expect(restored.signedArea, closeTo(contour.signedArea, 1e-9));
    });
  });

  // fontTools による外部検証のために実体を書き出す。build/ は git 管理外。
  test('検証用のサンプルフォントを書き出す', () async {
    final dir = Directory('build/font_samples');
    await dir.create(recursive: true);
    await File('${dir.path}/sample.ttf').writeAsBytes(
      buildFont(meta: meta, glyphs: glyphs, format: FontFormat.ttf),
    );
    await File('${dir.path}/sample.otf').writeAsBytes(
      buildFont(meta: meta, glyphs: glyphs, format: FontFormat.otf),
    );
    expect(await File('${dir.path}/sample.ttf').length(), greaterThan(0));
  });
}

/// 直線のみの矩形。時計回り（TrueType の外周の向き）。
Contour _rect(double x0, double y0, double x1, double y1) => Contour(
  Pt(x0, y0),
  [LineSeg(Pt(x0, y1)), LineSeg(Pt(x1, y1)), LineSeg(Pt(x1, y0))],
);

/// 3 次ベジェ 4 本からなる円。時計回り。
Contour _circle(double cx, double cy, double r) {
  const k = 0.5522847498307936;
  final o = r * k;
  return Contour(Pt(cx, cy + r), [
    CubicSeg(Pt(cx + o, cy + r), Pt(cx + r, cy + o), Pt(cx + r, cy)),
    CubicSeg(Pt(cx + r, cy - o), Pt(cx + o, cy - r), Pt(cx, cy - r)),
    CubicSeg(Pt(cx - o, cy - r), Pt(cx - r, cy - o), Pt(cx - r, cy)),
    CubicSeg(Pt(cx - r, cy + o), Pt(cx - o, cy + r), Pt(cx, cy + r)),
  ]);
}

List<Glyph> _sampleGlyphs() => [
  // 直線のみ
  Glyph(codePoint: 0x0041, advanceWidth: 500, contours: [_rect(50, 0, 450, 700)]),
  // 曲線のみ
  Glyph(codePoint: 0x3042, advanceWidth: 1000, contours: [_circle(500, 350, 350)]),
  // 穴あき。外周と内周で巻き方向が逆になっている必要がある。
  Glyph(
    codePoint: 0x30A2,
    advanceWidth: 1000,
    contours: [_circle(500, 350, 350), _circle(500, 350, 180).reversed()],
  ),
];

Pt _cubicAt(Pt p0, Pt p1, Pt p2, Pt p3, double t) {
  final u = 1 - t;
  return p0 * (u * u * u) +
      p1 * (3 * u * u * t) +
      p2 * (3 * u * t * t) +
      p3 * (t * t * t);
}

double _distanceToSegment(Pt p, Pt a, Pt b) {
  final ab = b - a;
  final lengthSquared = ab.x * ab.x + ab.y * ab.y;
  if (lengthSquared == 0) return (p - a).length;
  final ap = p - a;
  var t = (ap.x * ab.x + ap.y * ab.y) / lengthSquared;
  t = t.clamp(0.0, 1.0);
  return (p - (a + ab * t)).length;
}

Pt _quadAt(Pt p0, Pt c, Pt p1, double t) {
  final u = 1 - t;
  return p0 * (u * u) + c * (2 * u * t) + p1 * (t * t);
}

class _TableEntry {
  const _TableEntry(this.offset, this.length);

  final int offset;
  final int length;
}

Map<String, _TableEntry> _readTableDirectory(Uint8List font) {
  final numTables = _readUint16(font, 4);
  final tables = <String, _TableEntry>{};
  for (var i = 0; i < numTables; i++) {
    final at = 12 + i * 16;
    final tag = String.fromCharCodes(font.sublist(at, at + 4));
    tables[tag] = _TableEntry(_readUint32(font, at + 8), _readUint32(font, at + 12));
  }
  return tables;
}

/// cmap format 4 を読み戻してコードポイントからグリフ ID を引く。
Map<int, int> _readCmap(Uint8List font) {
  final table = _readTableDirectory(font)['cmap']!;
  final base = table.offset;
  final subtable = base + _readUint32(font, base + 4 + 4);

  final segCount = _readUint16(font, subtable + 6) ~/ 2;
  final endBase = subtable + 14;
  final startBase = endBase + segCount * 2 + 2;
  final deltaBase = startBase + segCount * 2;

  final result = <int, int>{};
  for (var i = 0; i < segCount; i++) {
    final start = _readUint16(font, startBase + i * 2);
    final end = _readUint16(font, endBase + i * 2);
    final delta = _readUint16(font, deltaBase + i * 2);
    if (start == 0xffff) continue;
    for (var cp = start; cp <= end; cp++) {
      result[cp] = (cp + delta) & 0xffff;
    }
  }
  return result;
}

int _readUint16(Uint8List d, int at) => (d[at] << 8) | d[at + 1];

int _readUint32(Uint8List d, int at) =>
    (d[at] << 24) | (d[at + 1] << 16) | (d[at + 2] << 8) | d[at + 3];

int _checksum(Uint8List data) {
  var sum = 0;
  for (var i = 0; i < data.length; i += 4) {
    sum = (sum + _readUint32(data, i)) & 0xffffffff;
  }
  return sum;
}
