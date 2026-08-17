import 'package:asoglyph/model/char_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readingOf', () {
    test('かなは字面がそのまま読みになる', () {
      expect(readingOf('あ'), 'あ');
      expect(readingOf('ん'), 'ん');
    });

    test('数字には読みを与える', () {
      expect(readingOf('0'), 'ゼロ');
      expect(readingOf('7'), 'なな');
    });

    test('濁音も字面がそのまま読みになる', () {
      expect(readingOf('が'), 'が');
      expect(readingOf('ぽ'), 'ぽ');
    });

    test('カタカナは文字種を頭に付けて呼ぶ', () {
      // 何も見ずに書くモードは音しか頼りがない。「ア」と「あ」は
      // 読みが同じで、そのままでは書き分けられない。
      expect(readingOf('ア'), 'カタカナの ア');
      expect(readingOf('ン'), 'カタカナの ン');
    });

    test('小書きは「ちいさい」を付けて呼ぶ', () {
      // 声だけでは「ゃ」と「や」を区別できない。
      expect(readingOf('ゃ'), 'ちいさい や');
      expect(readingOf('っ'), 'ちいさい つ');
      expect(readingOf('ャ'), 'カタカナの ちいさい ヤ');
    });

    test('長音符にも読みがある', () {
      expect(readingOf('ー'), 'カタカナの のばすぼう');
    });

    test('字面のままでは読めない字に読みが付いている', () {
      for (final char in CharSet.digits.chars) {
        expect(readingOf(char), isNot(char), reason: '$char の読みが無い');
      }
      for (final char in [...CharSet.hiragana.chars, ...CharSet.katakana.chars]
          .where(isSmallKana)) {
        expect(readingOf(char), contains('ちいさい'), reason: '$char の読みが無い');
      }
    });
  });

  group('isSmallKana', () {
    test('小書きの字を見分ける', () {
      expect(isSmallKana('ゃ'), isTrue);
      expect(isSmallKana('ッ'), isTrue);
      expect(isSmallKana('や'), isFalse);
      expect(isSmallKana('ツ'), isFalse);
    });

    test('長音符は小書きではない', () {
      // 「ー」は全角の幅いっぱいに引く。小さく書かせる字ではない。
      expect(isSmallKana('ー'), isFalse);
    });

    test('ひらがなとカタカナで同じ数だけある', () {
      final hiragana = CharSet.hiragana.chars.where(isSmallKana).length;
      final katakana = CharSet.katakana.chars.where(isSmallKana).length;
      expect(hiragana, 9);
      expect(katakana, 9);
    });
  });
}
