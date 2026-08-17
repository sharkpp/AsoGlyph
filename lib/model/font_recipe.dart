import '../font/glyph.dart';
import 'char_set.dart';

/// どの試行を採るかの規則（SPEC 4.3）。
///
/// SPEC は `best`（スコア最良）も定めているが、スコアは L4 の採点機能で
/// 入る。母集団が無いうちに器だけ作らない。
sealed class Policy {
  const Policy();
}

/// その時点で最新の試行。既定。
class LatestPolicy extends Policy {
  const LatestPolicy();

  @override
  bool operator ==(Object other) => other is LatestPolicy;

  @override
  int get hashCode => (LatestPolicy).hashCode;
}

/// 指定した時刻以前で最新の試行。「あの頃の文字」の実体。
class AtPolicy extends Policy {
  const AtPolicy(this.time);

  final DateTime time;

  @override
  bool operator ==(Object other) => other is AtPolicy && other.time == time;

  @override
  int get hashCode => time.hashCode;
}

/// フォントの版（SPEC 4.3）。
///
/// スナップショットは実体を持たず、解決規則の集合として表現する。
/// 同じレシピと同じ記録からは常に同じフォントが出るため、生成物を保存しない。
///
/// 解決順は `charRules` > `groupRules` > `base`。
class FontRecipe {
  const FontRecipe({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.fontMeta,
    this.charSets = const {},
    this.base = const LatestPolicy(),
    this.groupRules = const {},
    this.charRules = const {},
  });

  /// 何も指定しない既定の版。今の字が全部入る。
  factory FontRecipe.latest({
    required String id,
    required String name,
    required DateTime createdAt,
    required FontMetadata fontMeta,
  }) => FontRecipe(
    id: id,
    name: name,
    createdAt: createdAt,
    fontMeta: fontMeta,
    charSets: CharSet.values.toSet(),
  );

  final String id;

  /// 親が付けた版の名前。フォント名とは別。
  final String name;

  final DateTime createdAt;

  final FontMetadata fontMeta;

  /// 出力対象の文字種。収集対象とは別に決める（SPEC 5）。
  final Set<CharSet> charSets;

  /// 既定の規則。
  ///
  /// `latest`（期間無制限）を既定にする。文字種ごとに収集の開始時期が異なるため、
  /// 単一時点を基準にすると後発の文字種が空になる（SPEC 4.3）。
  final Policy base;

  /// 文字種ごとの規則。「ひらがなは去年、カタカナは今年」を表す。
  final Map<CharSet, Policy> groupRules;

  /// 字ごとの差し替え。文字 -> sampleId。いちばん強い。
  final Map<String, String> charRules;

  /// その文字に効く規則を返す。`charRules` はここでは見ない（id を直に指す）。
  Policy policyFor(CharSet charSet) => groupRules[charSet] ?? base;

  FontRecipe copyWith({
    String? name,
    FontMetadata? fontMeta,
    Set<CharSet>? charSets,
    Policy? base,
    Map<CharSet, Policy>? groupRules,
    Map<String, String>? charRules,
  }) => FontRecipe(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    fontMeta: fontMeta ?? this.fontMeta,
    charSets: charSets ?? this.charSets,
    base: base ?? this.base,
    groupRules: groupRules ?? this.groupRules,
    charRules: charRules ?? this.charRules,
  );
}
