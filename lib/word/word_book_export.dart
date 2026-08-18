/// 単語帳の書き出しと、絵ごと持ち出す形式（SPEC 7.4）。
///
/// 2 つ出口を持つ。
///
/// - **YAML** … 文字だけ。テキストエディタで直せて、差分も見られる。
///   人に渡すときも、中身が読めるほうが渡しやすい
/// - **`.asodict`** … `words.yaml` と `images/` を入れた zip。絵ごと持ち出せる
///
/// `.dict` ではなく `.asodict` にした。`.dict` は辞書ファイルの拡張子として
/// 広く使われていて、端末の中で取り違えられる。控えの `.asoglyph` とも揃う。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/word.dart';
import 'word_book_codec.dart';

/// 単語帳ファイルの拡張子。
const wordBookBundleExtension = 'asodict';

/// zip の中の単語帳本体。
const _manifest = 'words.yaml';

/// zip の中の絵の置き場。
const _imageDir = 'images';

/// YAML に書き出す。[parseWordBookYaml] がそのまま読み戻せる形にする。
///
/// 絵は名前だけが残る。YAML 1 枚には絵を入れられないので、絵ごと渡すときは
/// [encodeWordBookBundle] を使う。
String encodeWordBookYaml(WordBook book) {
  final out = StringBuffer()
    ..writeln('version: 1')
    ..writeln('name: ${_scalar(book.name)}')
    ..writeln('words:');

  for (final word in book.words) {
    out
      ..writeln('  - text: ${_scalar(word.text)}')
      ..writeln('    reading: ${_scalar(word.reading)}');
    if (word.image != null) {
      out.writeln('    image: ${_scalar(word.image!)}');
    }
    if (word.tags.isNotEmpty) {
      out.writeln('    tags: [${word.tags.map(_scalar).join(', ')}]');
    }
  }
  return out.toString();
}

/// 絵ごと 1 つのファイルにまとめる。
///
/// [readImage] は絵の id からバイト列を返す。読めなかった絵は、語から
/// 名前ごと落とす。指す先の無い名前を書き出すと、戻したときに壊れて見える。
Future<Uint8List> encodeWordBookBundle(
  WordBook book,
  Future<Uint8List?> Function(String id) readImage,
) async {
  final archive = Archive();
  final words = <Word>[];

  for (final word in book.words) {
    final image = word.image;
    if (image == null) {
      words.add(word);
      continue;
    }
    final bytes = await readImage(image);
    if (bytes == null) {
      words.add(word.withoutImage());
      continue;
    }
    words.add(word);
    archive.addFile(ArchiveFile.bytes('$_imageDir/$image', bytes));
  }

  archive.addFile(
    ArchiveFile.string(_manifest, encodeWordBookYaml(book.copyWith(words: words))),
  );
  return ZipEncoder().encodeBytes(archive);
}

/// 読み込んだ単語帳ファイル。絵はまだ端末に入っていない。
class WordBookBundle {
  const WordBookBundle({required this.book, required this.images});

  final WordBook book;

  /// ファイル名 -> バイト列。
  final Map<String, Uint8List> images;
}

/// 単語帳ファイルを読む。
///
/// 中の絵は、語が指しているものだけを拾う。関係ないファイルが入っていても
/// 無視する（親が手で zip を組み直すこともある）。
WordBookBundle parseWordBookBundle(Uint8List bytes, {required String name}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const WordBookFormatException('単語帳ファイルとして読めません');
  }

  final manifest = archive.files
      .where((file) => file.isFile && file.name == _manifest)
      .firstOrNull;
  if (manifest == null) {
    throw const WordBookFormatException('$_manifest が入っていません');
  }

  final book = parseWordBookYaml(
    utf8.decode(manifest.readBytes() ?? const []),
    id: name,
    fallbackName: name,
  );

  final wanted = {
    for (final word in book.words)
      if (word.image != null) word.image!,
  };
  final images = {
    for (final file in archive.files)
      if (file.isFile && file.name.startsWith('$_imageDir/'))
        if (wanted.contains(file.name.substring(_imageDir.length + 1)))
          file.name.substring(_imageDir.length + 1): file.readBytes()!,
  };

  return WordBookBundle(book: book, images: images);
}

/// YAML のスカラを、読み戻せる形にする。
///
/// 「100」を引用符無しで書くと数として読み戻る。数字だけの語（すうじの
/// 単語帳）が壊れるので、素の語として通らないものは必ず引用符でくくる。
String _scalar(String value) {
  final plain =
      value.isNotEmpty &&
      !RegExp(r'^[-+.0-9]').hasMatch(value) &&
      !RegExp(r'''[:#\[\]{},&*!|>'"%@`\n]''').hasMatch(value) &&
      value.trim() == value &&
      !const {'true', 'false', 'null', 'yes', 'no', 'on', 'off'}
          .contains(value.toLowerCase());
  if (plain) return value;
  return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
