import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../kanjivg/stroke_order.dart';
import '../model/char_set.dart';
import '../model/sample.dart';
import '../store/sample_store.dart';
import 'writing_screen.dart';

/// なぞり以外で書けた字数。充足率も星もこれで数える（SPEC 7.1）。
///
/// なぞった字はお手本の形をなぞったもので、その子の字とは言いにくい。
/// フォントに混ぜるかは出力のたびに選べるため、一覧では別の印で見せる。
int collectedIn(CharSet charSet, SampleStore store) => charSet.chars
    .where((char) => store.latestId(char, includeTraced: false) != null)
    .length;

/// 1 つの文字種の字を並べる画面。
///
/// 文字種を選んでから字を選ぶ、という 2 段にしてある。ひらがな・だくおん・
/// カタカナ・すうじで 127 字あり、漢字（L5）では 1 学年で 80 字が増える。
/// 全部を 1 枚に積むと、子供が自分の字を探せなくなる。
class CharSetScreen extends StatelessWidget {
  const CharSetScreen({
    super.key,
    required this.charSet,
    required this.store,
    required this.speaker,
    required this.strokeOrders,
    required this.mode,
  });

  final CharSet charSet;
  final SampleStore store;
  final Speaker speaker;
  final StrokeOrderLibrary strokeOrders;
  final PracticeMode mode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        leading: IconButton(
          iconSize: 32,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // 題は置かない。すぐ下の輪が名前と充足率をまとめて見せている。
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CharSetRing(charSet: charSet, store: store),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final char in charSet.chars)
                    CharTile(
                      char: char,
                      store: store,
                      speaker: speaker,
                      strokeOrders: strokeOrders,
                      mode: mode,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 文字種の充足率。輪の中に、その文字種を代表する字を置く。
///
/// 字がまだ読めない子には「ひらがな」の文字列は手がかりにならない。
/// あ・ア・が・0 のほうが、どの束かを見分ける印になる。
class CharSetRing extends StatelessWidget {
  const CharSetRing({super.key, required this.charSet, required this.store});

  final CharSet charSet;
  final SampleStore store;

  @override
  Widget build(BuildContext context) {
    final collected = collectedIn(charSet, store);
    final total = charSet.chars.length;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: collected / total,
                strokeWidth: 6,
                backgroundColor: const Color(0xffe4dfd4),
              ),
              Text(
                charSet.chars.first,
                style: TextStyle(
                  fontSize: 24,
                  height: 1,
                  color: collected == 0
                      ? const Color(0xff9c948a)
                      : scheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Text(
          charSet.label,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        Text(
          '$collected / $total',
          style: const TextStyle(color: Color(0xff9c948a)),
        ),
      ],
    );
  }
}

/// 一覧に並ぶ 1 字。押すとその字の書き取りに入る。
class CharTile extends StatelessWidget {
  const CharTile({
    super.key,
    required this.char,
    required this.store,
    required this.speaker,
    required this.strokeOrders,
    required this.mode,
  });

  final String char;
  final SampleStore store;
  final Speaker speaker;
  final StrokeOrderLibrary strokeOrders;
  final PracticeMode mode;

  @override
  Widget build(BuildContext context) {
    // なぞり以外で書けた字。充足率もこちらで数える。
    final collected = store.latestId(char, includeTraced: false) != null;
    // なぞっただけの字。出力時に混ぜるかを選べるので、別の印で見せる。
    final traced = !collected && store.attemptCount(char) > 0;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      // タップターゲットは 64dp 以上（SPEC 9）。
      width: 68,
      height: 68,
      child: Material(
        color: collected ? scheme.primaryContainer : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: collected
                ? scheme.primary
                : traced
                ? const Color(0xffbdb4a6)
                : const Color(0xffe4dfd4),
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => WritingScreen(
                char: char,
                mode: mode,
                store: store,
                speaker: speaker,
                strokeOrder: strokeOrders[char],
              ),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  char,
                  style: TextStyle(
                    fontSize: 32,
                    height: 1,
                    color: collected
                        ? scheme.onPrimaryContainer
                        : const Color(0xff9c948a),
                  ),
                ),
              ),
              if (collected)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Icon(Icons.star, size: 14, color: scheme.primary),
                )
              // 星ではない印にする。なぞりは集まった字と同じ扱いにしない。
              else if (traced)
                const Positioned(
                  right: 4,
                  top: 4,
                  child: Icon(
                    Icons.gesture,
                    size: 14,
                    color: Color(0xffbdb4a6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
