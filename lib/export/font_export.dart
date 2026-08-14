import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../font/font_builder.dart';

/// 生成したフォントの出口。
///
/// iOS は構成プロファイルなしに、Android は非 root で system フォントを追加できない。
/// 端末への直接インストールは提供せず、ファイル共有を出口とする（SPEC 7.7）。
Future<void> shareFont({
  required Uint8List bytes,
  required String fileName,
  required FontFormat format,
  String? text,
}) async {
  final mimeType = switch (format) {
    FontFormat.ttf => 'font/ttf',
    FontFormat.otf => 'font/otf',
  };

  final file = kIsWeb
      // web はファイルシステムを持たないため、そのままバイト列を渡す。
      ? XFile.fromData(bytes, name: fileName, mimeType: mimeType)
      : XFile(
          (await _writeTemporary(bytes, fileName)).path,
          mimeType: mimeType,
        );

  await SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [fileName],
      text: text,
    ),
  );
}

Future<File> _writeTemporary(Uint8List bytes, String fileName) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  return file.writeAsBytes(bytes);
}

/// ファイル名に使える形へ落とす。子供の名前など非 ASCII も受け取りうる。
String sanitizeFileName(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
  return cleaned.isEmpty ? 'AsoGlyph' : cleaned;
}
