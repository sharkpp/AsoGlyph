import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 共有シートに渡す（AirDrop / メール / Drive 等）。
///
/// **一時ファイルとして書いてから渡す。** 名前と拡張子がそのまま残り、
/// 受け取った側が何のファイルかを見分けられる。iOS では拡張子から種類が
/// 決まる（`ios/Runner/Info.plist` の型宣言、lib/ui/file_types.dart）。
///
/// **文字は一緒に渡さない。** iOS の共有シートは、渡したものを全部
/// 受け取れる送り先だけを並べる。文字を混ぜると「"ファイル"に保存」が
/// それを受け取れず候補から落ちる——**書き出しても端末に残せない**、
/// という形になる。メールの件名（[subject]）は項目ではないので混ざらない。
Future<void> saveFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      fileNameOverrides: [fileName],
      subject: subject,
    ),
  );
}
