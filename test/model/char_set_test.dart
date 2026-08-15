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

    test('濁点は名前で呼ぶ', () {
      expect(readingOf('゛'), 'てんてん');
      expect(readingOf('゜'), 'まる');
    });

    test('字面のままでは読めない字に読みが付いている', () {
      for (final charSet in [CharSet.digits, CharSet.soundMarks]) {
        for (final char in charSet.chars) {
          expect(readingOf(char), isNot(char), reason: '$char の読みが無い');
        }
      }
    });
  });
}
