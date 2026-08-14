import 'package:flutter/material.dart';

import 'ui/writing_screen.dart';

void main() {
  runApp(const AsoGlyphApp());
}

class AsoGlyphApp extends StatelessWidget {
  const AsoGlyphApp({super.key});

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
      home: const WritingScreen(),
    );
  }
}
