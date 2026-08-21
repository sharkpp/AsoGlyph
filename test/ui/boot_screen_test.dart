import 'dart:async';
import 'dart:io';

import 'package:asoglyph/app_version.dart';
import 'package:asoglyph/boot.dart';
import 'package:asoglyph/kanjivg/stroke_order.dart';
import 'package:asoglyph/main.dart';
import 'package:asoglyph/ui/app_mark.dart';
import 'package:asoglyph/ui/boot_screen.dart';
import 'package:asoglyph/ui/collection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';
import '../support/recording_speaker.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late AppServices services;

  setUp(() async {
    services = AppServices(
      session: await openMemorySession(),
      locks: await openMemoryLocks(),
      speaker: RecordingSpeaker(),
      strokeOrders: await StrokeOrderLibrary.load(),
    );
  });

  Future<void> pump(WidgetTester tester, Boot boot) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: BootScreen(boot: boot, builder: (services) => const Text('本体')),
      ),
    );
  }

  testWidgets('印と進み具合を出しながら読む', (tester) async {
    final gate = Completer<void>();
    late BootProgress report;

    await pump(tester, (send) async {
      report = send;
      send(0, 4, 'ようい');
      await gate.future;
      return services;
    });
    await tester.pump();

    // 字が読めない子にも「これはあのアプリだ」と分かるようにする（SPEC 2）。
    expect(find.byType(AppMark), findsOneWidget);
    expect(find.text('あそんでフォント'), findsOneWidget);
    expect(find.text('ようい'), findsOneWidget);
    expect(_progress(tester), 0);

    // 進んだぶんだけ帯が伸びる。ぐるぐる回すだけにはしない。
    report(2, 4, 'こえ');
    await tester.pump();
    expect(_progress(tester), 0.5);
    expect(find.text('こえ'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    // 読み終わると、同じ場所が本体に替わる。
    expect(find.text('本体'), findsOneWidget);
    expect(find.byType(AppMark), findsNothing);
  });

  testWidgets('どのビルドかを出す', (tester) async {
    await pump(tester, (report) => Completer<AppServices>().future);
    await tester.pump();

    // web は同じ URL のものが黙って入れ替わる（SPEC 10.1）。いま動いて
    // いるのがどれかを確かめる手立てが要る。
    expect(find.text(appVersionLabel), findsOneWidget);
  });

  testWidgets('開けなかったときは、そう言って、もういちど押せる', (tester) async {
    var tries = 0;
    await pump(tester, (report) async {
      tries++;
      if (tries == 1) throw StateError('置き場が開きません');
      return services;
    });
    await tester.pumpAndSettle();

    // 黙っていると、帯が止まったまま残る。何が起きたかは親に見せる。
    expect(find.text('うまく ひらけませんでした'), findsOneWidget);
    expect(find.textContaining('置き場が開きません'), findsOneWidget);

    await tester.tap(find.text('もういちど'));
    await tester.pumpAndSettle();

    expect(find.text('本体'), findsOneWidget);
  });

  group('読み込み中の画面（web）', _webPreloaderTests);

  test('焼き込んでいなければ、版の情報は「開発中」と出る', () {
    // 空にはしない。出ていないのか焼き忘れたのかが分からなくなる。
    expect(appVersionLabel, isNotEmpty);
    expect(appVersionLabel, isReleaseBuild ? isNot('開発中') : '開発中');
  });

  testWidgets('アプリは起動中の画面から始まる', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 読み終わるのを待って runApp すると、そのあいだ画面が真っ白になる。
    await tester.pumpWidget(
      AsoGlyphApp(boot: (report) => Completer<AppServices>().future),
    );
    await tester.pump();

    expect(find.byType(BootScreen), findsOneWidget);
    expect(find.byType(CollectionScreen), findsNothing);
  });
}

/// 読み込み中の画面は、Flutter が動き出す前に出るもの。
///
/// この時間は Dart のコードが 1 行も走らないので、[BootScreen] はまだ出せない
/// （SPEC 10.1）。落ちると、開くたびに地の色の板が数秒出たままになる。
void _webPreloaderTests() {
  final html = File('web/index.html').readAsStringSync();

  test('入口に読み込み中の画面が入っている', () {
    expect(html, contains('id="preloader"'));
    // 起動中の画面と同じ印を出す。入れ替わるときに絵が飛ばない。
    expect(html, contains('icons/Icon-192.png'));
  });

  test('最初の絵が出たら消える', () {
    // 消さないと、書き取り面の上に透明な板がかぶさったままになる。
    expect(html, contains('flutter-first-frame'));
    expect(html, contains('preloader.remove()'));
  });

  test('起動中の画面と同じ大きさ・同じ色にしてある', () {
    // 別の大きさにすると、入れ替わったところで絵が飛ぶ。
    expect(html, contains('width: 128px'));
    expect(html, contains('width: 200px'));
    expect(html, contains('#e8863c'));
    expect(html, contains('#faf7f0'));
  });
}

/// 帯がどこまで伸びているか。
double? _progress(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .value;
