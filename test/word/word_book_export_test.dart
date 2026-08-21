import 'dart:convert';
import 'dart:typed_data';

import 'package:asoglyph/model/word.dart';
import 'package:asoglyph/word/word_book_codec.dart';
import 'package:asoglyph/word/word_book_export.dart';
import 'package:flutter_test/flutter_test.dart';

final _book = WordBook(
  id: 'b1',
  name: 'どうぶつ',
  words: [
    const Word(text: 'ねこ', reading: 'ねこ', tags: ['どうぶつ']),
    const Word(text: '100', reading: 'ひゃく'),
    const Word(text: 'いぬ', reading: 'いぬ', image: 'dog.png'),
  ],
);

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('YAML への書き出し', () {
    test('書き出して、そのまま読み戻せる', () {
      final yaml = encodeWordBookYaml(_book);
      final back = parseWordBookYaml(yaml, id: 'x', fallbackName: 'x');

      expect(back.name, 'どうぶつ');
      expect(back.words.map((word) => word.text), ['ねこ', '100', 'いぬ']);
      expect(back.words.first.tags, ['どうぶつ']);
      expect(back.words.last.image, 'dog.png');
    });

    test('作った人と概要も書き出して、読み戻せる', () {
      final credited = _book.withCredits(
        author: 'さめ',
        description: '4 歳向け。ひらがなだけで書ける語',
      );

      final back = parseWordBookYaml(
        encodeWordBookYaml(credited),
        id: 'x',
        fallbackName: 'x',
      );

      // 渡した先で出どころが消えないようにする（SPEC 7.4）。
      expect(back.author, 'さめ');
      expect(back.description, '4 歳向け。ひらがなだけで書ける語');
    });

    test('書かれていない作った人と概要は、行そのものを出さない', () {
      // 空の行を出すと、渡した先で「消してある」のか「無い」のかが読めない。
      final yaml = encodeWordBookYaml(_book);

      expect(yaml, isNot(contains('author')));
      expect(yaml, isNot(contains('description')));
    });

    test('数字の語が数にならない', () {
      // 引用符無しで書くと 100 が数として読み戻る。
      final back = parseWordBookYaml(
        encodeWordBookYaml(_book),
        id: 'x',
        fallbackName: 'x',
      );

      expect(back.words[1].text, '100');
      expect(back.words[1].reading, 'ひゃく');
    });

    test('記号や空白の入った語も読み戻せる', () {
      final tricky = WordBook(
        id: 'b',
        name: 'yes',
        words: [
          const Word(text: 'あ: い', reading: 'あい'),
          const Word(text: '#いち', reading: 'いち'),
          const Word(text: 'true', reading: 'とぅるー'),
        ],
      );

      final back = parseWordBookYaml(
        encodeWordBookYaml(tricky),
        id: 'x',
        fallbackName: 'x',
      );

      expect(back.name, 'yes');
      expect(back.words.map((word) => word.text), ['あ: い', '#いち', 'true']);
    });
  });

  group('単語帳ファイル', () {
    test('絵ごと書き出して読み戻せる', () async {
      final bundle = await encodeWordBookBundle(
        _book,
        (id) async => id == 'dog.png' ? _bytes('PNG-DATA') : null,
      );

      final back = parseWordBookBundle(bundle, name: 'どうぶつ');

      expect(back.book.name, 'どうぶつ');
      expect(back.book.words, hasLength(3));
      expect(back.book.words.last.image, 'dog.png');
      expect(utf8.decode(back.images['dog.png']!), 'PNG-DATA');
    });

    test('読めなかった絵は、名前ごと落とす', () async {
      // 指す先の無い名前を書き出すと、戻したときに壊れて見える。
      final bundle = await encodeWordBookBundle(_book, (id) async => null);
      final back = parseWordBookBundle(bundle, name: 'どうぶつ');

      expect(back.book.words.last.image, isNull);
      expect(back.images, isEmpty);
    });

    test('関係ないファイルが入っていても読める', () async {
      final bundle = await encodeWordBookBundle(
        _book,
        (id) async => _bytes('PNG-DATA'),
      );
      final archive = parseWordBookBundle(bundle, name: 'x');

      expect(archive.images.keys, ['dog.png']);
    });

    test('zip でないものは断る', () {
      expect(
        () => parseWordBookBundle(_bytes('ただの文字'), name: 'x'),
        throwsA(isA<WordBookFormatException>()),
      );
    });

    test('words.yaml が無ければ断る', () async {
      // 中身の無い zip を作って渡す。
      final empty = await encodeWordBookBundle(
        const WordBook(id: 'b', name: 'から', words: []),
        (id) async => null,
      );
      final broken = Uint8List.fromList(empty)..[30] = 0x00;

      expect(
        () => parseWordBookBundle(broken, name: 'x'),
        throwsA(isA<WordBookFormatException>()),
      );
    });
  });
}
