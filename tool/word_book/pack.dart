// 単語帳のフォルダを 1 つの .asodict にまとめる（SPEC 7.4.1）。
//
//   dart run tool/word_book/pack.dart <フォルダ> [出力先]
//
// フォルダには単語帳の YAML を 1 つ置き、絵は同じフォルダに並べる。
// YAML の `image:` に書いたファイル名だけを拾って zip に入れる。
//
//   work/どうぶつ/
//     どうぶつ.yaml     ← image: cat.webp と書く
//     cat.webp
//
// 出力先を省くと assets/words/_<フォルダ名>.asodict になる。`_` で始まるので
// デバッグでだけ読み込まれ、リポジトリにも入らない（動作確認用の辞書）。
// 配るものにするときは、出力先を `_` の付かない名前で指定する。
import 'dart:io';
import 'dart:typed_data';

import 'package:asoglyph/word/word_book_codec.dart';
import 'package:asoglyph/word/word_book_export.dart';
import 'package:asoglyph/word/word_image.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('使い方: dart run tool/word_book/pack.dart <フォルダ> [出力先]');
    exit(64);
  }

  final directory = Directory(args.first);
  if (!directory.existsSync()) {
    stderr.writeln('${directory.path} がありません');
    exit(66);
  }

  final files = directory.listSync().whereType<File>().toList();
  final source = files
      .where((file) => file.path.endsWith('.yaml') || file.path.endsWith('.yml'))
      .toList();
  if (source.length != 1) {
    stderr.writeln('YAML はフォルダに 1 つだけ置いてください（${source.length} 個あります）');
    exit(65);
  }

  final name = _baseName(source.single.path);
  final book = parseWordBookYaml(
    source.single.readAsStringSync(),
    id: name,
    fallbackName: name,
  );

  // 絵はファイル名で引く。控えの中では単語帳と同じ名前で並ぶ。
  final images = {
    for (final file in files) _baseNameWithExtension(file.path): file,
  };

  var missing = 0;
  var tooBig = 0;
  final bytes = await encodeWordBookBundle(book, (id) async {
    final file = images[id];
    if (file == null) {
      stderr.writeln('絵が見つかりません: $id');
      missing++;
      return null;
    }
    final data = Uint8List.fromList(file.readAsBytesSync());
    if (!isSupportedImage(id)) {
      stderr.writeln('入れられない形式です: $id');
      missing++;
      return null;
    }
    if (data.length > maxImageBytes) {
      stderr.writeln(
        '大きすぎます: $id（${describeSize(data.length)}／'
        '${describeSize(maxImageBytes)} まで）',
      );
      tooBig++;
      return null;
    }
    return data;
  });

  final output = File(
    args.length > 1
        ? args[1]
        : 'assets/words/_${_directoryName(directory)}.$wordBookBundleExtension',
  );
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(bytes);

  final withImage = book.words.where((word) => word.image != null).length;
  stdout.writeln(
    '${output.path} を書きました\n'
    '  ${book.words.length} 語（絵つき ${withImage - missing - tooBig} 語）\n'
    '  ${describeSize(bytes.length)}',
  );
  if (missing + tooBig > 0) {
    stdout.writeln('  入らなかった絵: ${missing + tooBig} 枚');
  }
}

String _baseName(String path) =>
    _baseNameWithExtension(path).replaceAll(RegExp(r'\.[^.]*$'), '');

String _baseNameWithExtension(String path) => path.split(Platform.pathSeparator).last;

String _directoryName(Directory directory) =>
    directory.path.split(Platform.pathSeparator).where((p) => p.isNotEmpty).last;
