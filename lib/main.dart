import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'boot.dart';
import 'ui/about.dart';
import 'ui/app_mark.dart';
import 'ui/boot_screen.dart';
import 'ui/collection_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerKanjiVgLicense();
  // 読むのは画面を出したあと（[BootScreen]）。ここで待つと、そのあいだ
  // 画面が真っ白のまま止まって見える。
  runApp(const AsoGlyphApp());
}

class AsoGlyphApp extends StatelessWidget {
  const AsoGlyphApp({super.key, this.boot = bootApp});

  /// 起動のしかた。テストでは差し替える。
  final Boot boot;

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
        colorScheme: ColorScheme.fromSeed(seedColor: appOrange),
        scaffoldBackgroundColor: appCream,
        useMaterial3: true,
      ),
      // 読み終わると、同じ場所が本体に替わる。画面を積み替えないので、
      // 起動が速い端末でも切り替わりが滑って見えない。
      home: BootScreen(
        boot: boot,
        builder: (services) => CollectionScreen(
          session: services.session,
          locks: services.locks,
          speaker: services.speaker,
          strokeOrders: services.strokeOrders,
        ),
      ),
    );
  }
}
