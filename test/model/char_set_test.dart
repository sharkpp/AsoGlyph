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

    test('数字は 1 字も読みを落としていない', () {
      for (final char in CharSet.digits.chars) {
        expect(readingOf(char), isNot(char), reason: '$char の読みが無い');
      }
    });
  });
}
