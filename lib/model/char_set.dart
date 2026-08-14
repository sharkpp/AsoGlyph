/// 収集・出力の対象になる文字のまとまり（SPEC 5）。
///
/// 文字種ごとに収集の開始時期も字幅も異なるため、字の集合は必ずこの単位で扱う。
enum CharSet {
  digits('すうじ', _digits, advanceWidth: 500),
  hiraganaBasic('ひらがな', _hiraganaBasic, advanceWidth: 1000);

  const CharSet(this.label, this.chars, {required this.advanceWidth});

  /// 子供向け画面にも出す名前。
  final String label;

  /// 収集順に並べた対象文字。
  final List<String> chars;

  /// 字送り幅（em 1000 基準）。和文は全角、数字・ラテンは半角に固定する（SPEC 5.2）。
  final int advanceWidth;
}

const _digits = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', //
];

/// 五十音順。行の切れ目でそのまま並べる。
const _hiraganaBasic = [
  'あ', 'い', 'う', 'え', 'お', //
  'か', 'き', 'く', 'け', 'こ', //
  'さ', 'し', 'す', 'せ', 'そ', //
  'た', 'ち', 'つ', 'て', 'と', //
  'な', 'に', 'ぬ', 'ね', 'の', //
  'は', 'ひ', 'ふ', 'へ', 'ほ', //
  'ま', 'み', 'む', 'め', 'も', //
  'や', 'ゆ', 'よ', //
  'ら', 'り', 'る', 'れ', 'ろ', //
  'わ', 'を', 'ん', //
];

/// 文字から所属する CharSet を引く。どこにも属さない文字は null。
CharSet? charSetOf(String char) {
  for (final set in CharSet.values) {
    if (set.chars.contains(char)) return set;
  }
  return null;
}
