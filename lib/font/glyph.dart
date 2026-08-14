import 'geometry.dart';

/// 1 文字分のアウトライン。
class Glyph {
  const Glyph({
    required this.codePoint,
    required this.contours,
    required this.advanceWidth,
  });

  /// 空グリフ（.notdef やスペース）。
  const Glyph.blank({required this.codePoint, required this.advanceWidth})
    : contours = const [];

  /// Unicode コードポイント。.notdef は -1。
  final int codePoint;
  final List<Contour> contours;
  final int advanceWidth;

  bool get isBlank => contours.isEmpty;

  Bounds get bounds => Bounds.ofContours(contours);

  /// CFF の charset や PostScript 名に使うグリフ名。
  String get name {
    if (codePoint < 0) return '.notdef';
    if (codePoint == 0x20) return 'space';
    return 'uni${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }
}

/// フォント全体のメタデータ。
class FontMetadata {
  FontMetadata({
    required this.familyName,
    this.styleName = 'Regular',
    this.version = '1.000',
    this.manufacturer = 'sharkpp',
    this.vendorUrl = 'https://sharkpp.net',
    this.vendorId = 'SKPP',
    this.unitsPerEm = 1000,
    this.ascender = 880,
    this.descender = -120,
    this.lineGap = 0,
    DateTime? created,
  }) : created = created ?? _epoch;

  /// フォント生成をレシピの純関数に保つため、作成日時は呼び出し側が与える。
  /// 既定値を固定しているのは、指定しない場合でも出力をバイト単位で再現可能にするため。
  static final DateTime _epoch = DateTime.utc(2026, 1, 1);

  /// head テーブルの created / modified に入る日時。
  final DateTime created;

  final String familyName;
  final String styleName;
  final String version;
  final String manufacturer;
  final String vendorUrl;

  /// OS/2 の achVendID。4 バイトの ASCII。
  final String vendorId;

  final int unitsPerEm;
  final int ascender;
  final int descender;
  final int lineGap;

  String get fullName => styleName == 'Regular'
      ? familyName
      : '$familyName $styleName';

  /// PostScript 名は ASCII かつ空白と特定記号を含められない。
  /// 子供の名前など非 ASCII が入りうるため、必ず正規化して用いる。
  String get postScriptName {
    const forbidden = r'[](){}<>/% ';
    final buffer = StringBuffer();
    for (final rune in '$familyName-$styleName'.runes) {
      if (rune < 0x21 || rune > 0x7e || forbidden.contains(String.fromCharCode(rune))) {
        continue;
      }
      buffer.write(String.fromCharCode(rune));
    }
    final name = buffer.isEmpty ? 'AsoGlyph-Regular' : buffer.toString();
    return name.length <= 63 ? name : name.substring(0, 63);
  }

  String get uniqueId => '$manufacturer: $fullName: $version';
}
