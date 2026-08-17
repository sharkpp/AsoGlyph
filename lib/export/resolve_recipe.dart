import '../model/font_recipe.dart';
import '../store/sample_store.dart';

/// レシピと記録から、フォントに載せる 文字 -> sampleId を決める（SPEC 4.3）。
///
/// 解決順は `charRules` > `groupRules` > `base`。
/// 素材が 1 つも無い文字は結果に現れない。書いていない字を KanjiVG の字形で
/// 埋めることはしない（SPEC 6.3）。
///
/// フォント生成を純関数に保つため、ここでは運筆を読まない。
Map<String, String> resolveRecipe(
  FontRecipe recipe,
  SampleStore store, {
  required bool includeTraced,
}) {
  final resolved = <String, String>{};

  for (final charSet in recipe.charSets) {
    final policy = recipe.policyFor(charSet);
    for (final char in charSet.chars) {
      final id = _resolveChar(
        char,
        recipe: recipe,
        policy: policy,
        store: store,
        includeTraced: includeTraced,
      );
      if (id != null) resolved[char] = id;
    }
  }

  return resolved;
}

String? _resolveChar(
  String char, {
  required FontRecipe recipe,
  required Policy policy,
  required SampleStore store,
  required bool includeTraced,
}) {
  // 字ごとの差し替えがいちばん強い。なぞりを混ぜるかにも左右されない。
  // 親がその字を名指しで選んでいるため。
  final pinned = recipe.charRules[char];
  // 記録を消したあとのレシピは、指す先を失っていることがある。
  if (pinned != null && store.contains(pinned)) return pinned;

  final history = switch (policy) {
    LatestPolicy() => store.history(char, includeTraced: includeTraced),
    AtPolicy(:final time) => store.history(
      char,
      includeTraced: includeTraced,
      before: time,
    ),
  };
  return history.isEmpty ? null : history.last.id;
}

/// レシピが今の記録で何字ぶんになるか。出力前に見せる。
int resolvedCount(
  FontRecipe recipe,
  SampleStore store, {
  required bool includeTraced,
}) => resolveRecipe(recipe, store, includeTraced: includeTraced).length;

/// レシピの対象に入っている全字数。充足率の分母。
int totalChars(FontRecipe recipe) =>
    recipe.charSets.fold(0, (sum, charSet) => sum + charSet.chars.length);
