/// 収集・出力の対象になる文字のまとまり（SPEC 5）。
///
/// 文字種ごとに収集の開始時期も字幅も異なるため、字の集合は必ずこの単位で扱う。
enum CharSet {
  digits('すうじ', _digits, advanceWidth: 500),
  hiraganaBasic('ひらがな', _hiraganaBasic, advanceWidth: 1000),
  hiraganaVoiced('だくおん', _hiraganaVoiced, advanceWidth: 1000);

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

/// 濁音 20 字・半濁音 5 字。清音と同じ並び順にする。
///
/// SPEC 5.1 は清音＋濁点からの合成を既定にしているが、そちらは採らない。
/// 濁音は濁点を足しただけの字ではなく、その子が書いた 1 つの字として残す。
const _hiraganaVoiced = [
  'が', 'ぎ', 'ぐ', 'げ', 'ご', //
  'ざ', 'じ', 'ず', 'ぜ', 'ぞ', //
  'だ', 'ぢ', 'づ', 'で', 'ど', //
  'ば', 'び', 'ぶ', 'べ', 'ぼ', //
  'ぱ', 'ぴ', 'ぷ', 'ぺ', 'ぽ', //
];

/// 文字から所属する CharSet を引く。どこにも属さない文字は null。
CharSet? charSetOf(String char) {
  for (final set in CharSet.values) {
    if (set.chars.contains(char)) return set;
  }
  return null;
}

/// 読み上げるときの読み。かなは字面がそのまま読みになる。
///
/// 字面のままでは読めない字だけ明示する。「0」を「れい」と読むエンジンが
/// あるが、幼児に通じるのは「ゼロ」のほう。濁点・半濁点も名前で呼ぶ。
String readingOf(String char) => _readings[char] ?? char;

const _readings = {
  '0': 'ゼロ', '1': 'いち', '2': 'に', '3': 'さん', '4': 'よん', //
  '5': 'ご', '6': 'ろく', '7': 'なな', '8': 'はち', '9': 'きゅう', //
};
