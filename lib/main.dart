import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'audio/speaker.dart';
import 'kanjivg/stroke_order.dart';
import 'store/app_database.dart';
import 'store/passcode.dart';
import 'store/session.dart';
import 'ui/about.dart';
import 'ui/collection_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerKanjiVgLicense();
  // 記録も版も同じ 1 つのデータベースに置く。
  final database = await openAppDatabase('asoglyph.db');
  runApp(
    AsoGlyphApp(
      session: await Session.open(database),
      locks: await Locks.open(),
      speaker: await TtsSpeaker.open(),
      strokeOrders: await StrokeOrderLibrary.load(),
    ),
  );
}

class AsoGlyphApp extends StatelessWidget {
  const AsoGlyphApp({
    super.key,
    required this.session,
    required this.locks,
    required this.speaker,
    required this.strokeOrders,
  });

  final Session session;
  final Locks locks;
  final Speaker speaker;
  final StrokeOrderLibrary strokeOrders;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'あそんでフォント',
      debugShowCheckedModeBanner: false,
      // 日付選択など Flutter の部品が英語のまま出ないようにする。
      // 保護者向け画面で日付を選ばせるため、日本語が要る。
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffe8863c)),
        scaffoldBackgroundColor: const Color(0xfffaf7f0),
        useMaterial3: true,
      ),
      home: CollectionScreen(
        session: session,
        locks: locks,
        speaker: speaker,
        strokeOrders: strokeOrders,
      ),
    );
  }
}
