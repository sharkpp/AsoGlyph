import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// ブラウザに保存させる。
///
/// **共有シート（`navigator.share`）には渡さない。** iOS Safari は渡せる
/// ファイルの種類を絞っていて、控え（`.asoglyph`）や単語帳（`.asodict`）は
/// 受け取らない。断られると share_plus は data: URI での保存に落ちるが、
/// **iOS Safari は大きい data: URI を受け付けない**。集めた字ぜんぶを
/// まとめた控えは数 MB になるので、そこで必ず失敗する
/// （押しても何も起きない、という形で表に出る）。
///
/// Blob の URL なら大きさで断られない。iOS でも保存できる。
///
/// [subject] は共有シートのためのもので、ここでは使わない。
Future<void> saveFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..download = fileName
        ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();

  // すぐ解放すると、保存が始まる前に中身が消える端末がある。時間を置いて
  // 解放するが、**呼んだ側は待たせない**（待たせると、保存はもう始まって
  // いるのに画面が動かないままになる）。
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
