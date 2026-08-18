import 'package:csv/csv.dart';
import 'package:yaml/yaml.dart';

import '../model/word.dart';

/// 単語帳を読めなかった。親に見せる文言をそのまま持つ。
class WordBookFormatException implements Exception {
  const WordBookFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// YAML から読む（SPEC 7.4）。
///
/// 業界標準の形式が無いため、こちらを正とする。CSV は Excel で作れるように
/// 受けるだけの入口で、[parseWordBookCsv] が同じ [WordBook] に落とす。
///
/// ```yaml
/// version: 1
/// name: どうぶつ
/// words:
///   - text: ねこ
///     reading: ねこ
///     tags: [どうぶつ]
/// ```
WordBook parseWordBookYaml(
  String source, {
  required String id,
  required String fallbackName,
}) {
  final Object? document;
  try {
    document = loadYaml(source);
  } on YamlException catch (error) {
    throw WordBookFormatException('YAML として読めません（${error.message}）');
  }
  if (document is! Map) {
    throw WordBookFormatException('単語帳の形になっていません');
  }

  final words = document['words'];
  if (words is! List) {
    throw const WordBookFormatException('words がありません');
  }

  return WordBook(
    id: id,
    name: (document['name'] as Object?)?.toString() ?? fallbackName,
    words: [
      for (final (index, entry) in words.indexed) _word(entry, index + 1),
    ],
  );
}

Word _word(Object? entry, int line) {
  if (entry is! Map) {
    throw WordBookFormatException('$line 個めの語が読めません');
  }
  final text = (entry['text'] as Object?)?.toString().trim() ?? '';
  final reading = (entry['reading'] as Object?)?.toString().trim() ?? '';
  if (text.isEmpty) {
    throw WordBookFormatException('$line 個めの語に text がありません');
  }
  // 読みを必須にするのは、子供が読めない語を出さないため（SPEC 7.4）。
  if (reading.isEmpty) {
    throw WordBookFormatException('「$text」に reading がありません');
  }
  final tags = entry['tags'];
  // 絵は名前だけが載る。中身は単語帳ファイル（.asodict）の側にある。
  final image = (entry['image'] as Object?)?.toString().trim();
  return Word(
    text: text,
    reading: reading,
    image: image == null || image.isEmpty ? null : image,
    tags: [
      if (tags is List)
        for (final tag in tags) tag.toString(),
    ],
  );
}

/// CSV から読む（SPEC 7.4）。
///
/// 親が Excel で作れるようにするための入口。列は ことば・よみ・タグ の順で、
/// 1 行目が見出しなら読み飛ばす。タグは空白か「、」で区切る（カンマは列の
/// 区切りに使われていて書けない）。
WordBook parseWordBookCsv(
  String source, {
  required String id,
  required String name,
}) {
  // 区切りは自動判別に任せる。Excel は地域によって「;」で書き出す。
  // BOM は Excel が付ける。残すと 1 列めの見出しが一致しなくなる。
  final rows = const CsvDecoder().convert(source.replaceFirst('\uFEFF', ''));

  final words = <Word>[];
  for (final (index, row) in rows.indexed) {
    final cells = [for (final cell in row) cell.toString().trim()];
    if (cells.every((cell) => cell.isEmpty)) continue;
    if (index == 0 && _isHeader(cells)) continue;

    final text = cells.isEmpty ? '' : cells[0];
    final reading = cells.length > 1 ? cells[1] : '';
    if (text.isEmpty) {
      throw WordBookFormatException('${index + 1} 行めに ことば がありません');
    }
    if (reading.isEmpty) {
      throw WordBookFormatException('${index + 1} 行め「$text」に よみ がありません');
    }
    words.add(
      Word(
        text: text,
        reading: reading,
        tags: cells.length > 2 && cells[2].isNotEmpty
            ? cells[2].split(RegExp(r'[\s、;]+'))
            : const [],
      ),
    );
  }

  if (words.isEmpty) throw const WordBookFormatException('語が 1 つもありません');
  return WordBook(id: id, name: name, words: words);
}

/// 見出し行か。英語で書く人と日本語で書く人の両方が居る。
bool _isHeader(List<String> cells) =>
    cells.isNotEmpty &&
    const {'text', 'word', 'ことば', 'たんご', '単語'}.contains(cells.first);

/// 取り込んだファイルを読む。形式は拡張子で決める（SPEC 7.4）。
///
/// YAML を正とし、CSV は Excel で作る親のために受ける。単語帳の名前は、
/// YAML なら中の `name`、CSV ならファイル名になる。
WordBook parseWordBookFile({
  required String fileName,
  required String source,
}) {
  final name = fileName.split('/').last.replaceAll(RegExp(r'\.[^.]*$'), '');
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.csv')) {
    return parseWordBookCsv(source, id: fileName, name: name);
  }
  if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
    return parseWordBookYaml(source, id: fileName, fallbackName: name);
  }
  throw const WordBookFormatException('読めるのは .yaml と .csv です');
}
