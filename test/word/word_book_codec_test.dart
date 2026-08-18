import 'package:asoglyph/word/word_book_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YAML', () {
    test('SPEC の形をそのまま読める', () {
      final book = parseWordBookYaml('''
version: 1
name: どうぶつ
words:
  - text: ねこ
    reading: ねこ
    image: cat.png
    tags: [どうぶつ]
  - text: きりん
    reading: きりん
''', id: 'test', fallbackName: 'ファイル名');

      expect(book.name, 'どうぶつ');
      expect(book.words.map((word) => word.text), ['ねこ', 'きりん']);
      expect(book.words.first.tags, ['どうぶつ']);
      // 使わない項目があっても読めなくならない。
      expect(book.words.last.tags, isEmpty);
    });

    test('name が無ければファイル名を使う', () {
      final book = parseWordBookYaml(
        'words:\n  - {text: そら, reading: そら}\n',
        id: 'test',
        fallbackName: 'ファイル名',
      );

      expect(book.name, 'ファイル名');
    });

    test('読みが無い語は受けない', () {
      // 子供が読めない語を出さないため、reading は必須（SPEC 7.4）。
      expect(
        () => parseWordBookYaml(
          'words:\n  - {text: 薔薇}\n',
          id: 'test',
          fallbackName: 'x',
        ),
        throwsA(
          isA<WordBookFormatException>().having(
            (error) => error.message,
            'message',
            contains('薔薇'),
          ),
        ),
      );
    });

    test('壊れた YAML は、読めないと言って止まる', () {
      expect(
        () => parseWordBookYaml('words: [', id: 'test', fallbackName: 'x'),
        throwsA(isA<WordBookFormatException>()),
      );
    });

    test('words が無ければ単語帳ではない', () {
      expect(
        () => parseWordBookYaml('name: からっぽ', id: 'test', fallbackName: 'x'),
        throwsA(isA<WordBookFormatException>()),
      );
    });
  });

  group('CSV', () {
    test('見出し付きの表を読める', () {
      final book = parseWordBookCsv(
        'ことば,よみ,タグ\nねこ,ねこ,どうぶつ\nりんご,りんご,たべもの くだもの\n',
        id: 'test',
        name: 'どうぶつ',
      );

      expect(book.words.map((word) => word.text), ['ねこ', 'りんご']);
      // タグはカンマで書けない（列の区切りに使われている）。空白で分ける。
      expect(book.words.last.tags, ['たべもの', 'くだもの']);
    });

    test('見出しが無くても読める', () {
      final book = parseWordBookCsv(
        'ねこ,ねこ\nいぬ,いぬ\n',
        id: 'test',
        name: 'どうぶつ',
      );

      expect(book.words, hasLength(2));
    });

    test('Excel が付ける BOM と改行を落とせる', () {
      final book = parseWordBookCsv(
        '﻿ことば,よみ\r\nねこ,ねこ\r\n',
        id: 'test',
        name: 'どうぶつ',
      );

      expect(book.words.single.text, 'ねこ', reason: '見出しを読み飛ばせている');
    });

    test('数字の語を数として読まない', () {
      final book = parseWordBookCsv('100,ひゃく\n', id: 'test', name: 'すうじ');

      expect(book.words.single.text, '100');
    });

    test('読みの無い行は、何行めかを言って止まる', () {
      expect(
        () => parseWordBookCsv('ねこ,ねこ\nいぬ\n', id: 'test', name: 'x'),
        throwsA(
          isA<WordBookFormatException>().having(
            (error) => error.message,
            'message',
            contains('2 行め'),
          ),
        ),
      );
    });

    test('空の表は受けない', () {
      expect(
        () => parseWordBookCsv('\n\n', id: 'test', name: 'x'),
        throwsA(isA<WordBookFormatException>()),
      );
    });
  });

  group('取り込むファイル', () {
    test('拡張子で形式を決める', () {
      expect(
        parseWordBookFile(
          fileName: '/tmp/どうぶつ.csv',
          source: 'ねこ,ねこ\n',
        ).name,
        'どうぶつ',
        reason: 'CSV の名前はファイル名から',
      );
      expect(
        parseWordBookFile(
          fileName: 'words.yaml',
          source: 'name: のりもの\nwords:\n  - {text: ばす, reading: ばす}\n',
        ).name,
        'のりもの',
        reason: 'YAML は中の name を使う',
      );
    });

    test('知らない拡張子は受けない', () {
      expect(
        () => parseWordBookFile(fileName: 'words.txt', source: 'ねこ'),
        throwsA(isA<WordBookFormatException>()),
      );
    });
  });
}
