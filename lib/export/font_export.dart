import 'package:flutter/foundation.dart';

import '../font/font_builder.dart';
import 'file_save.dart';

/// 生成したフォントの出口。
///
/// iOS は構成プロファイルなしに、Android は非 root で system フォントを
/// 追加できない。端末への直接インストールは提供せず、ファイルとして
/// 出すところまでを出口とする（SPEC 7.7）。
Future<void> shareFont({
  required Uint8List bytes,
  required String fileName,
  required FontFormat format,
  String? subject,
}) => saveFile(
  bytes: bytes,
  fileName: fileName,
  mimeType: switch (format) {
    FontFormat.ttf => 'font/ttf',
    FontFormat.otf => 'font/otf',
  },
  subject: subject,
);

/// ファイル名に使える形へ落とす。子供の名前など非 ASCII も受け取りうる。
String sanitizeFileName(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
  return cleaned.isEmpty ? 'AsoGlyph' : cleaned;
}
