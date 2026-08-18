import 'package:asoglyph/word/reading.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('読みはひらがなに揃える', () {
    test('カタカナはひらがなに直す', () {
      expect(toReading('バス'), 'ばす');
      expect(toReading('ウルトラマンオメガ'), 'うるとらまんおめが');
      expect(toReading('ヴァイオリン'), 'ゔぁいおりん');
    });

    test('長音符は残す', () {
      // これを落とすと「あーく」が「あく」になり、読み上げが別の語になる。
      expect(toReading('ウルトラマンアーク'), 'うるとらまんあーく');
      expect(toReading('けーき'), 'けーき');
    });

    test('空白は残す', () {
      // 「いち に さん」のように区切りたいことがある。
      expect(toReading('いち に さん'), 'いち に さん');
    });

    test('ひらがなはそのまま', () {
      expect(toReading('うるとらまんぶれーざー'), 'うるとらまんぶれーざー');
      expect(toReading('ぱぴぷぺぽ ぁぃぅぇぉ っゃゅょ'), 'ぱぴぷぺぽ ぁぃぅぇぉ っゃゅょ');
    });

    test('読み上げられない字は落とす', () {
      expect(toReading('鼻血'), '');
      expect(toReading('はな血'), 'はな');
      expect(toReading('bus ばす 100'), ' ばす ');
      expect(toReading('ねこ！'), 'ねこ');
    });
  });

  group('打ちながら直す', () {
    const formatter = ReadingInputFormatter();

    TextEditingValue type(String text) => formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );

    test('カタカナで打つと、その場でひらがなになる', () {
      final value = type('バス');

      expect(value.text, 'ばす');
      expect(value.selection.baseOffset, 2, reason: '打っている位置は末尾のまま');
    });

    test('使えない字は入らない', () {
      final value = type('ねこ鼻');

      expect(value.text, 'ねこ');
      expect(value.selection.baseOffset, 2);
    });

    test('そのままでよいときは触らない', () {
      final value = type('ねこ');

      expect(value.text, 'ねこ');
      expect(value.selection.baseOffset, 2);
    });
  });
}
