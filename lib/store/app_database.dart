/// 端末内のデータベースを開く。
///
/// 筆跡はサーバーへ送らない（SPEC 3）。保存先は web では IndexedDB、
/// それ以外ではアプリのドキュメント領域になる。
library;

export 'app_database_io.dart'
    if (dart.library.js_interop) 'app_database_web.dart';
