/// 語の読み（SPEC 7.4）。
///
/// 読みは**声で読み上げるためだけ**にある。子供が読めない語を出さないよう、
/// どの語にも必ず付ける。表記ではないので、ひらがな 1 本に揃える。
///
/// 揃えないと、同じ「バス」に「ばす」「バス」「BUS」が混ざる。読み上げの
/// エンジンは字面をそのまま読むので、混ざったぶんだけ読まれ方も揺れる。
library;

import 'package:flutter/services.dart';

/// 読みに使える字だけを残し、カタカナはひらがなに直す。
///
/// - カタカナ … ひらがなに直す（バス → ばす）
/// - ひらがな … そのまま
/// - **長音符「ー」… 残す。** ひらがなではないが、これを落とすと
///   「あーく」が「あく」になり、読み上げが別の語になる
/// - 空白 … 残す。「いち に さん」のように区切りたいことがある
/// - それ以外（漢字・英数字・記号）… 落とす。読み上げられないか、
///   読み上げても子供に通じない
String toReading(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    // カタカナ（ァ..ヶ）はひらがな（ぁ..ゖ）へ。並びが 0x60 ずれているだけ。
    if (rune >= 0x30a1 && rune <= 0x30f6) {
      out.writeCharCode(rune - 0x60);
    } else if (rune >= 0x3041 && rune <= 0x3096) {
      out.writeCharCode(rune);
    } else if (rune == 0x30fc || rune == 0x20 || rune == 0x3000) {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// 打ちながら直す。カタカナで打っても、その場でひらがなになる。
///
/// 決めたあとに黙って直すのではなく、打っている手元で直す。あとから
/// 変わると、自分が打ったものと違うものが残ったように見える。
class ReadingInputFormatter extends TextInputFormatter {
  const ReadingInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = toReading(newValue.text);
    if (text == newValue.text) return newValue;

    // 落とした字のぶんだけ、入力位置を戻す。
    final removed = newValue.text.characters.length - text.characters.length;
    final offset = (newValue.selection.baseOffset - removed).clamp(
      0,
      text.length,
    );
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

extension on String {
  List<String> get characters => runes.map(String.fromCharCode).toList();
}
