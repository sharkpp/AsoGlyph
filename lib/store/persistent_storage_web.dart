import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// ブラウザに「この置き場を片づけないで」と頼む。
///
/// 空き容量が減ったとき、ブラウザは断りなく IndexedDB を捨てることがある。
/// 捨てられると集めた字が丸ごと消える。控え（SPEC 7.5）はあるが、
/// 取っていない人のほうが多い。
///
/// 返るのは「消されない状態になったか」。
///
/// - Chrome / Edge … 聞かずに決める（ホーム画面に置いた・よく使っている
///   サイトなら通る）
/// - Firefox … 親に確かめる。断られることがある
/// - Safari … ホーム画面に置いたときだけ通る
///
/// 通らなくても書けなくはならないので、結果で画面を変えることはしない。
Future<bool> requestPersistentStorage() async {
  try {
    final storage = web.window.navigator.storage;
    if ((await storage.persisted().toDart).toDart) return true;
    return (await storage.persist().toDart).toDart;
  } catch (_) {
    // 対応していないブラウザがある。頼めないだけで、書くのには困らない。
    return false;
  }
}
