import 'dart:convert';
import 'dart:typed_data';

import 'package:asoglyph/word/word_book_codec.dart';
import 'package:asoglyph/word/word_book_export.dart';
import 'package:asoglyph/word/word_book_fetch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// いつも同じものを返す置き場。
http.Client _serving(
  List<int> body, {
  int status = 200,
  String? contentType,
  Uri? expect,
}) => MockClient((request) async {
  if (expect != null && request.url != expect) {
    return http.Response('', 404);
  }
  return http.Response.bytes(
    body,
    status,
    headers: contentType == null ? const {} : {'content-type': contentType},
  );
});

const _yaml = 'name: どうぶつ\nwords:\n  - {text: ねこ, reading: ねこ}\n';

void main() {
  test('YAML を取ってくる', () async {
    final fetched = await fetchWordBook(
      'https://example.com/どうぶつ.yaml',
      client: _serving(utf8.encode(_yaml)),
    );

    expect(fetched.isBundle, isFalse);
    expect(fetched.text, _yaml);
    // 読み方は拡張子で決まる。名前もここから取る。
    expect(fetched.fileName, 'どうぶつ.yaml');
  });

  test('単語帳ファイルは中身で見分ける', () async {
    // 配る側は「?id=...」のように拡張子の無い URL で渡すこともある。
    final zip = await encodeWordBookBundle(
      parseWordBookYaml(_yaml, id: 'x', fallbackName: 'x'),
      (id) async => null,
    );

    final fetched = await fetchWordBook(
      'https://example.com/download',
      client: _serving(zip),
    );

    expect(fetched.isBundle, isTrue);
    expect(
      parseWordBookBundle(fetched.bytes!, name: 'x').book.words.single.text,
      'ねこ',
    );
  });

  test('拡張子が無いときは、言ってきた種類で CSV を見分ける', () async {
    final fetched = await fetchWordBook(
      'https://example.com/export',
      client: _serving(
        utf8.encode('ねこ,ねこ\n'),
        contentType: 'text/csv; charset=utf-8',
      ),
    );

    expect(fetched.fileName, 'export.csv');
    // そのまま読める形になっている。
    expect(
      parseWordBookFile(fileName: fetched.fileName, source: fetched.text!)
          .words
          .single
          .text,
      'ねこ',
    );
  });

  test('拡張子も種類も分からなければ YAML として読む', () async {
    final fetched = await fetchWordBook(
      'https://example.com/books/1',
      client: _serving(utf8.encode(_yaml)),
    );

    // YAML をこちらの正の形にしてある（SPEC 7.4）。
    expect(fetched.fileName, '1.yaml');
  });

  group('取ってこられなかったとき', () {
    test('http でも https でもない URL は受けない', () {
      expect(
        () => fetchWordBook('example.com/どうぶつ.yaml'),
        throwsA(
          isA<WordBookFormatException>().having(
            (error) => error.message,
            'message',
            contains('http'),
          ),
        ),
      );
    });

    test('無い URL は、いくつが返ってきたかを言う', () {
      expect(
        () => fetchWordBook(
          'https://example.com/none.yaml',
          client: _serving(const [], status: 404),
        ),
        throwsA(
          isA<WordBookFormatException>().having(
            (error) => error.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test('つながらなければ、そう言う', () {
      // web では、置いてある側が許していない URL はブラウザが止める。
      expect(
        () => fetchWordBook(
          'https://example.com/どうぶつ.yaml',
          client: MockClient((_) async => throw http.ClientException('だめ')),
        ),
        throwsA(
          isA<WordBookFormatException>().having(
            (error) => error.message,
            'message',
            contains('取ってこられませんでした'),
          ),
        ),
      );
    });

    test('空の URL は受けない', () {
      expect(
        () => fetchWordBook(
          'https://example.com/どうぶつ.yaml',
          client: _serving(const []),
        ),
        throwsA(isA<WordBookFormatException>()),
      );
    });

    test('絵や PDF を指していたら、単語帳ではないと言う', () {
      expect(
        () => fetchWordBook(
          'https://example.com/cat.png',
          client: _serving(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0xff])),
        ),
        throwsA(
          isA<WordBookFormatException>().having(
            (error) => error.message,
            'message',
            contains('単語帳ではありません'),
          ),
        ),
      );
    });
  });
}
