/// ファイルを選ばせるときの種類（SPEC 7.4.1 / 7.5）。
///
/// **iOS は拡張子では絞れない。** 選ぶ画面（`UIDocumentPickerViewController`）は
/// 種類の識別子（UTI）しか見ず、`extensions` だけを渡すと file_selector_ios が
/// そこで投げる。押しても何も出ない、という形で表に出る。
///
/// 独自の拡張子（`.asoglyph` / `.asodict`）は `ios/Runner/Info.plist` で
/// 宣言してあり、ここはその識別子を指す。宣言が無いと、書き出した控えは
/// 端末のなかで種類の分からないファイルになり、**選ぶ画面で灰色になって
/// 選べない**（書き出せているのに戻せない、といういちばん困る形になる）。
/// 食い違うと同じことが起きるので、テストで縛ってある。
///
/// Android と web は拡張子で絞る。どちらも識別子は見ない。
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../word/word_book_export.dart' show wordBookBundleExtension;
import '../word/word_image.dart' show imageExtensions;

/// 控え（SPEC 7.5）。
const backupTypeGroup = XTypeGroup(
  label: 'あそんでフォントの控え',
  extensions: ['asoglyph'],
  uniformTypeIdentifiers: ['net.sharkpp.asoglyph.backup'],
);

/// 単語帳（SPEC 7.4.1）。絵ごとの zip・文字だけの YAML・Excel で作った CSV。
///
/// YAML と CSV には、ほかの誰かが宣言した種類で届くこともある。文字として
/// 読める種類（`public.plain-text`）も許して、そこで取りこぼさないようにする。
const wordBookTypeGroup = XTypeGroup(
  label: '単語帳',
  extensions: [wordBookBundleExtension, 'yaml', 'yml', 'csv'],
  uniformTypeIdentifiers: [
    'net.sharkpp.asoglyph.worddict',
    'net.sharkpp.asoglyph.yaml',
    'public.comma-separated-values-text',
    'public.plain-text',
  ],
);

/// 単語帳を選ばせるときに渡すもの。
///
/// **web では絞らない。** ブラウザに渡るのは拡張子の並び（`accept`）で、
/// Safari はそれを端末の種類の識別子へ直してから見る。直せなかったもの
/// （`.asodict` と `.yaml`）は落ち、`.csv` だけが残るので、**単語帳ファイルと
/// YAML が選ぶ画面で灰色になって選べない**。
///
/// 全部落ちたときだけ何でも選べるようになるため、控え（`.asoglyph` だけ）は
/// 選べて単語帳は選べない、という食い違いになっていた。
///
/// 絞らなければどれも選べる。読めるかどうかは読んだところで見て、駄目なら
/// 何が悪いのかを言う（SPEC 7.4）。**選べないより、選んでから断るほうがよい。**
List<XTypeGroup> get wordBookTypeGroups =>
    wordBookTypeGroupsFor(web: kIsWeb);

/// [wordBookTypeGroups] の中身。web かどうかを渡して確かめられるようにする。
List<XTypeGroup> wordBookTypeGroupsFor({required bool web}) =>
    web ? const [] : const [wordBookTypeGroup];

/// 語に添える絵（SPEC 7.4.2）。どれも識別子は決まったものがある。
const imageTypeGroup = XTypeGroup(
  label: 'え',
  extensions: imageExtensions,
  uniformTypeIdentifiers: [
    'public.png',
    'public.jpeg',
    'org.webmproject.webp',
    'public.svg-image',
  ],
);
