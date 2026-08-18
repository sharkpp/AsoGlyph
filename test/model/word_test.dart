import 'package:asoglyph/model/word.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('かっこで囲んだところは書かせない', () {
    test('書かせる字と、出しておく字に分かれる', () {
      const word = Word(
        text: '[ウルトラマン]オメガ',
        reading: 'うるとらまんおめが',
      );

      // 長い名前ぜんぶを書かせると 1 セッションで終わらない（SPEC 7.4）。
      expect(word.display, 'ウルトラマンオメガ');
      expect(word.chars, ['オ', 'メ', 'ガ']);
      expect(word.displayChars, hasLength(9));
      expect(word.givenIndices, {0, 1, 2, 3, 4, 5});
    });

    test('かっこが後ろにあってもよい', () {
      const word = Word(text: 'オメガ[のひみつ]', reading: 'おめがのひみつ');

      expect(word.chars, ['オ', 'メ', 'ガ']);
      expect(word.givenIndices, {3, 4, 5, 6});
    });

    test('かっこが途中に何度あってもよい', () {
      const word = Word(text: '[お]はな[し]', reading: 'おはなし');

      expect(word.display, 'おはなし');
      expect(word.chars, ['は', 'な']);
      expect(word.givenIndices, {0, 3});
    });

    test('閉じていないかっこは、そこから先を出しておく扱いにする', () {
      // 取り込んだ単語帳で 1 か所書き損じただけで、読み込みを断るほどの
      // ことではない。
      const word = Word(text: 'オメガ[のひみつ', reading: 'おめがのひみつ');

      expect(word.display, 'オメガのひみつ');
      expect(word.chars, ['オ', 'メ', 'ガ']);
    });

    test('かっこが無ければ、ぜんぶ書かせる', () {
      const word = Word(text: 'ねこ', reading: 'ねこ');

      expect(word.display, 'ねこ');
      expect(word.chars, ['ね', 'こ']);
      expect(word.givenIndices, isEmpty);
    });
  });

  group('書けるかどうか', () {
    test('かっこの中の字は見ない', () {
      const word = Word(text: '[東京]スカイツリー', reading: 'とうきょうすかいつりー');

      // 漢字を集めていなくても、カタカナだけで書ける。
      expect(word.isWritable({'ス', 'カ', 'イ', 'ツ', 'リ', 'ー'}), isTrue);
    });

    test('書かせる字が 1 つも無い語は出さない', () {
      const word = Word(text: '[ぜんぶ]', reading: 'ぜんぶ');

      expect(word.chars, isEmpty);
      expect(word.isWritable({'ぜ', 'ん', 'ぶ'}), isFalse);
    });
  });
}
