/// 起動のときに読むもの（記録・ロック・声・書き順）。
///
/// **読み終わるまで待たずに画面を出す。** `runApp` の前に全部読むと、その
/// あいだ画面が真っ白のまま止まって見える。書き順データは 1 MB を超えるので、
/// 端末が遅いほど長く止まる。読み込みは画面を出したあとに進め、どこまで
/// 進んだかを [BootProgress] で知らせる（[BootScreen]）。
library;

import 'audio/speaker.dart';
import 'kanjivg/stroke_order.dart';
import 'store/app_database.dart';
import 'store/passcode.dart';
import 'store/persistent_storage.dart';
import 'store/session.dart';

/// 起動が終わったときに揃っているもの。
class AppServices {
  const AppServices({
    required this.session,
    required this.locks,
    required this.speaker,
    required this.strokeOrders,
  });

  final Session session;
  final Locks locks;
  final Speaker speaker;
  final StrokeOrderLibrary strokeOrders;
}

/// どこまで進んだか。[done] / [total] の [step] を読んでいる。
typedef BootProgress = void Function(int done, int total, String step);

/// 起動のしかた。テストでは差し替える。
typedef Boot = Future<AppServices> Function(BootProgress report);

/// 起動の段取り。名前は画面に出る。
///
/// 順番には意味がある。**置き場を頼むのがいちばん先**（SPEC 10.1）。
/// データベースを開いてから頼んでも、そのとき既に捨てられているものは
/// 戻らない。
const _steps = ['ようい', 'きろく', 'かぎ', 'こえ', 'かきじゅん'];

/// 実際に読む。
Future<AppServices> bootApp(BootProgress report) async {
  var done = 0;
  Future<T> step<T>(Future<T> Function() load) async {
    report(done, _steps.length, _steps[done]);
    final value = await load();
    done++;
    report(done, _steps.length, done < _steps.length ? _steps[done] : 'できた');
    return value;
  }

  // 置き場を片づけないでほしいと、開く前に頼んでおく（web だけ）。
  // 集めた字は取り戻せない。
  final database = await step(() async {
    await requestPersistentStorage();
    // 記録も版も同じ 1 つのデータベースに置く。
    return openAppDatabase('asoglyph.db');
  });

  final session = await step(() => Session.open(database));
  final locks = await step(Locks.open);
  final speaker = await step(TtsSpeaker.open);
  final strokeOrders = await step(StrokeOrderLibrary.load);

  return AppServices(
    session: session,
    locks: locks,
    speaker: speaker,
    strokeOrders: strokeOrders,
  );
}
