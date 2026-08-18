import 'package:flutter/services.dart';

import '../word/reading.dart';

/// 読みを打ちながら直す（SPEC 7.4）。
///
/// 決めたあとに黙って直すのではなく、打っている手元で直す。あとから変わると、
/// 自分が打ったものと違うものが残ったように見える。
///
/// 直す規則そのものは [toReading] が持つ。取り込んだ単語帳も同じ規則を通るので、
/// 入口が 2 つあっても揺れない。
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
    final removed = newValue.text.runes.length - text.runes.length;
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
