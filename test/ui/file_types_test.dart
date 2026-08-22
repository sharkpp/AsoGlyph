import 'dart:io';

import 'package:asoglyph/ui/file_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// iOS の Info.plist が宣言している種類。識別子 → 拡張子。
Map<String, List<String>> _declaredTypes() {
  final plist = XmlDocument.parse(
    File('ios/Runner/Info.plist').readAsStringSync(),
  );
  final root = plist.rootElement.findElements('dict').single;

  // plist の dict は <key> と値が交互に並ぶ。key の次の兄弟が値になる。
  Iterable<XmlElement> valueOf(XmlElement dict, String key) {
    final children = dict.childElements.toList();
    for (var i = 0; i < children.length - 1; i++) {
      if (children[i].localName == 'key' && children[i].innerText == key) {
        return [children[i + 1]];
      }
    }
    return const [];
  }

  String? stringOf(XmlElement dict, String key) =>
      valueOf(dict, key).firstOrNull?.innerText;

  final types = <String, List<String>>{};
  for (final key in const [
    'UTExportedTypeDeclarations',
    'UTImportedTypeDeclarations',
  ]) {
    for (final array in valueOf(root, key)) {
      for (final declaration in array.findElements('dict')) {
        final id = stringOf(declaration, 'UTTypeIdentifier')!;
        final tags = valueOf(declaration, 'UTTypeTagSpecification').single;
        final extensions = valueOf(tags, 'public.filename-extension').single;
        types[id] = [
          for (final value in extensions.findElements('string')) value.innerText,
        ];
      }
    }
  }
  return types;
}

void main() {
  group('単語帳を選ばせるとき', () {
    test('web では種類で絞らない', () {
      // Safari は accept の拡張子を端末の種類へ直してから見る。直せない
      // .asodict と .yaml が落ちて .csv だけが残るので、単語帳ファイルと
      // YAML が灰色になって選べない。絞らなければどれも選べる。
      expect(wordBookTypeGroupsFor(web: true), isEmpty);
    });

    test('web でなければ絞る', () {
      // iOS は識別子で、Android とデスクトップは拡張子で絞れる。
      expect(wordBookTypeGroupsFor(web: false), [wordBookTypeGroup]);
    });
  });

  /// iOS の選ぶ画面は識別子しか見ない。渡さないとそこで投げて、押しても
  /// 何も出ない（SPEC 7.5 の「控えから戻す」が動かない形になる）。
  test('どの種類にも iOS 用の識別子がある', () {
    for (final group in [backupTypeGroup, wordBookTypeGroup, imageTypeGroup]) {
      expect(
        group.uniformTypeIdentifiers,
        isNotEmpty,
        reason: '${group.label} に識別子が無いと iOS で選べない',
      );
      expect(group.extensions, isNotEmpty, reason: 'Android と web は拡張子で絞る');
    }
  });

  test('独自の識別子は Info.plist の宣言と揃っている', () {
    final declared = _declaredTypes();
    expect(
      declared.keys,
      containsAll(['net.sharkpp.asoglyph.backup']),
      reason: '宣言が無いと、書き出した控えが種類の分からないファイルになる',
    );

    for (final group in [backupTypeGroup, wordBookTypeGroup, imageTypeGroup]) {
      for (final uti in group.uniformTypeIdentifiers!) {
        // 決まったもの（public.png など）は宣言しない。
        if (!uti.startsWith('net.sharkpp.')) continue;
        expect(declared, contains(uti), reason: '$uti の宣言が Info.plist に無い');
        // 宣言した拡張子は、選ぶときの拡張子にも入っていること。
        expect(group.extensions, containsAll(declared[uti]!));
      }
    }
  });

  test('控えの拡張子は 1 つ。宣言もその 1 つを指す', () {
    // 控えは `.asoglyph`（SPEC 7.4.1）。ここが揃っていないと、書き出せている
    // のに戻せない、といういちばん困る形になる。
    expect(backupTypeGroup.extensions, ['asoglyph']);
    expect(_declaredTypes()['net.sharkpp.asoglyph.backup'], ['asoglyph']);
  });
}
