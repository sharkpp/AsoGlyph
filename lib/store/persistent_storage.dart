/// 端末に残した字が、勝手に消されないようにする。
///
/// web では、記録の置き場（IndexedDB）はブラウザの都合で片づけられることが
/// ある。集めた字は取り戻せないので、消さないでほしいと明示的に頼む。
///
/// web 以外では何もしない。アプリのドキュメント領域は勝手に消えない。
library;

export 'persistent_storage_io.dart'
    if (dart.library.js_interop) 'persistent_storage_web.dart';
