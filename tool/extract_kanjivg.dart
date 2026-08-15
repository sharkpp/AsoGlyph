// KanjiVG から、このアプリが収集対象にしている字の運筆だけを抜き出す。
//
//   dart run tool/extract_kanjivg.dart <kanjivg-YYYYMMDD.xml>
//
// 元データは KanjiVG（CC BY-SA 3.0 / Ulrich Apel, https://kanjivg.tagaini.net/）。
// 出力もライセンス継承のため CC BY-SA 3.0 とし、このスクリプトごとリポジトリで
// 公開する（SPEC 6.3）。
//
// 全 6,702 字を同梱すると 6.4 MB になる。収集対象は多くても 1,200 字ほどで、
// 使わない字を抱える理由がないため、CharSet に載っている字だけを抜く。
// CharSet が増えたら、このスクリプトを流し直せば出力も追随する。
import 'dart:convert';
import 'dart:io';

import 'package:asoglyph/model/char_set.dart';
import 'package:xml/xml.dart';

/// KanjiVG の名前空間。`kvg:element` に対象文字が入っている。
const _kvg = 'http://kanjivg.tagaini.net';

const _output = 'assets/kanjivg/strokes.json';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('使い方: dart run tool/extract_kanjivg.dart <kanjivg.xml>');
    exit(64);
  }

  final document = XmlDocument.parse(File(args.single).readAsStringSync());
  final strokes = <String, List<String>>{};
  for (final kanji in document.rootElement.childElements) {
    final group = kanji.childElements.first;
    final char = group.getAttribute('element', namespaceUri: _kvg);
    if (char == null) continue;
    // 同じ字が複数の異体字として載ることがある。最初のものを正とする。
    strokes.putIfAbsent(
      char,
      () => kanji
          .findAllElements('path')
          .map((path) => path.getAttribute('d')!)
          .toList(),
    );
  }

  final wanted = [for (final set in CharSet.values) ...set.chars];
  final extracted = {
    for (final char in wanted)
      if (strokes.containsKey(char)) char: strokes[char]!,
  };

  final missing = wanted.where((char) => !strokes.containsKey(char));
  if (missing.isNotEmpty) {
    // 「」？ は KanjiVG に無い（SPEC 6.1）。自作するまでは書き順を出せない。
    stderr.writeln('KanjiVG に無い字: ${missing.join()}');
  }

  File(_output).writeAsStringSync('${jsonEncode(extracted)}\n');
  stdout.writeln(
    '${extracted.length} / ${wanted.length} 字を $_output に書いた '
    '(${File(_output).lengthSync() ~/ 1024} KB)',
  );
}
