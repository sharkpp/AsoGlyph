/// 作ったファイルを端末に渡す（SPEC 7.4.1 / 7.5 / 7.7）。
///
/// 出す先はこちらでは決めない。送り先は端末に任せる（SPEC 3）。
/// ただし**渡し方が web とそれ以外で別物**なので、実装を分けている。
///
/// - web … ブラウザに保存させる（[saveFile] の web 実装）
/// - それ以外 … 共有シートに渡す
library;

export 'file_save_io.dart' if (dart.library.js_interop) 'file_save_web.dart';
