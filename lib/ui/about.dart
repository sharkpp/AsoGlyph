import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// KanjiVG のクレジットとライセンス表記（SPEC 6.3 / 10）。
///
/// 子供向けカテゴリは外部リンクの扱いが厳しいため、ブラウザへ飛ばさず
/// アプリの中で読み切れるようにする。URL は文字として置くだけにとどめる。
const _kanjiVgNotice = '''
書き順のお手本に KanjiVG を使っています。

KanjiVG
Copyright (C) 2009-2013 Ulrich Apel
https://kanjivg.tagaini.net/

Creative Commons Attribution-Share Alike 3.0 Licence
https://creativecommons.org/licenses/by-sa/3.0/

このアプリが同梱している書き順データは KanjiVG から必要な字だけを抜き出した
ものであり、同じく CC BY-SA 3.0 で提供します。抽出スクリプトと出力は
リポジトリで公開しています。

このアプリが作るフォントは、お子さんの筆跡だけからできています。
KanjiVG の字形は含まれないため、フォントに CC BY-SA 3.0 は及びません。
''';

/// 「すべてのライセンス」に KanjiVG を載せる。
void registerKanjiVgLicense() {
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(['KanjiVG'], _kanjiVgNotice),
    ),
  );
}

void showAboutAsoGlyph(BuildContext context, {required VoidCallback onClear}) {
  showAboutDialog(
    context: context,
    applicationName: 'あそんでフォント',
    applicationLegalese: '© sharkpp  https://sharkpp.net',
    children: [
      const SizedBox(height: 16),
      const SelectableText(
        _kanjiVgNotice,
        style: TextStyle(fontSize: 13, height: 1.6),
      ),
      const Divider(height: 32),
      // 動作確認のための出口。子供の手が届かないよう、この奥に置く。
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: const Color(0xffb3261e)),
        icon: const Icon(Icons.delete_forever),
        label: const Text('集めた字をぜんぶ消す（テスト用）'),
        onPressed: onClear,
      ),
    ],
  );
}

/// 消す前に一度たしかめる。取り消せない操作なので必ず挟む。
Future<bool> confirmClearAll(BuildContext context) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('集めた字をぜんぶ消しますか？'),
      content: const Text('書いた記録がすべて消えます。元には戻せません。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('やめる'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffb3261e),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('消す'),
        ),
      ],
    ),
  );
  return answer ?? false;
}
