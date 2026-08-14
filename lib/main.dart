import 'package:flutter/material.dart';

import 'store/sample_store.dart';
import 'ui/collection_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AsoGlyphApp(store: await SampleStore.open()));
}

class AsoGlyphApp extends StatelessWidget {
  const AsoGlyphApp({super.key, required this.store});

  final SampleStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'あそんでフォント',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffe8863c)),
        scaffoldBackgroundColor: const Color(0xfffaf7f0),
        useMaterial3: true,
      ),
      home: CollectionScreen(store: store),
    );
  }
}
