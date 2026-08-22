/// URL から単語帳を取ってくる（SPEC 7.4.1）。
///
/// 単語帳は人に渡せる。渡す側が置き場（GitHub や共有ドライブ）に上げてある
/// なら、いちいち落としてから選ばせるより、URL を貼るほうが早い。
///
/// **取ってくるのは単語帳だけ。** こちらから何かを送ることはしない
/// （SPEC 3 のとおり、筆跡は端末から出ない）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'word_book_codec.dart';
import 'word_book_export.dart';

/// 取ってきた単語帳。まだ読んでいない。
///
/// 文字（YAML・CSV）か、単語帳ファイル（zip）のどちらか一方が入る。
class FetchedWordBook {
  const FetchedWordBook({required this.fileName, this.text, this.bytes});

  /// ファイル名にあたるもの。URL の最後の部分から作る。
  /// 拡張子は読み方を決めるのに使う（[parseWordBookFile] と同じ規則）。
  final String fileName;

  final String? text;
  final Uint8List? bytes;

  /// 単語帳ファイル（絵ごとの zip）か。
  bool get isBundle => bytes != null;
}

/// zip の頭。中身から形を見分ける。
///
/// 拡張子の付いていない URL（配る側が `?id=...` で渡すことがある）でも、
/// 絵ごとの単語帳を取り違えないようにする。
const _zipMagic = [0x50, 0x4b, 0x03, 0x04];

/// 取ってくる。読めなかったときは [WordBookFormatException] を投げる。
///
/// 文言はそのまま親に見せる。何が悪いのかを言わないと、直しようがない
/// （SPEC 7.4）。
Future<FetchedWordBook> fetchWordBook(
  String input, {
  http.Client? client,
}) async {
  final url = Uri.tryParse(input.trim());
  if (url == null || (url.scheme != 'http' && url.scheme != 'https')) {
    throw const WordBookFormatException(
      'http:// か https:// で始まる URL を入れてください',
    );
  }

  final owned = client == null;
  final fetch = client ?? http.Client();
  final http.Response response;
  try {
    response = await fetch.get(url);
  } catch (error) {
    // web では、置いてある側が許していない URL は取ってこられない
    // （ブラウザが止める）。落としてから「単語帳を取り込む」で選べば入る。
    throw WordBookFormatException(
      'この URL からは取ってこられませんでした。'
      'ブラウザで開ける URL か確かめてください（$error）',
    );
  } finally {
    if (owned) fetch.close();
  }

  if (response.statusCode != 200) {
    throw WordBookFormatException(
      'この URL からは取ってこられませんでした（${response.statusCode}）',
    );
  }

  final bytes = response.bodyBytes;
  if (bytes.isEmpty) {
    throw const WordBookFormatException('この URL には何も入っていません');
  }

  final name = _fileName(url, response.headers['content-type']);
  if (_looksZip(bytes)) {
    return FetchedWordBook(fileName: name, bytes: bytes);
  }
  try {
    return FetchedWordBook(fileName: name, text: utf8.decode(bytes));
  } on FormatException {
    // 画像や PDF を指していると、ここへ来る。
    throw const WordBookFormatException('この URL のものは単語帳ではありません');
  }
}

bool _looksZip(Uint8List bytes) {
  if (bytes.length < _zipMagic.length) return false;
  for (final (index, byte) in _zipMagic.indexed) {
    if (bytes[index] != byte) return false;
  }
  return true;
}

/// URL からファイル名を作る。
///
/// 拡張子が読み方を決めるので、無ければ補う。CSV かどうかは、
/// 置いてある側が言ってきた種類で決める（Excel から上げたものはこれで当たる）。
/// 分からなければ YAML として読む（こちらが正の形）。
String _fileName(Uri url, String? contentType) {
  final last = url.pathSegments.where((part) => part.isNotEmpty).lastOrNull;
  final name = last == null || last.isEmpty ? 'たんごちょう' : last;

  final lower = name.toLowerCase();
  const known = ['.yaml', '.yml', '.csv', '.$wordBookBundleExtension'];
  if (known.any(lower.endsWith)) return name;

  final type = contentType?.toLowerCase() ?? '';
  if (type.contains('csv')) return '$name.csv';
  if (type.contains('zip')) return '$name.$wordBookBundleExtension';
  return '$name.yaml';
}
