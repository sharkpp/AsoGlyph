# KanjiVG 由来の書き順データ

`strokes.json` は [KanjiVG](https://kanjivg.tagaini.net/) から、このアプリが収集
対象にしている字の運筆だけを抜き出したものです。

- 元データ: KanjiVG r20250816 (`kanjivg-20250816.xml.gz`)
- 著作: Copyright (C) 2009-2013 Ulrich Apel
- ライセンス: [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
- 変換スクリプト: [`tool/extract_kanjivg.dart`](../../tool/extract_kanjivg.dart)

**このファイルは KanjiVG の二次的著作物であり、同じく CC BY-SA 3.0 で提供します。**

## 形式

### `strokes.json` — 書かせる字の運筆

```json
{ "あ": ["M31.01,33c0.88,...", "..."], ... }
```

文字 → 画順に並んだ SVG パス。座標系は KanjiVG のまま viewBox `0 0 109 109`。
em 1000 に直すときは 1000/109 倍します。

収録は `CharSet` に載っている 171 字（すうじ 10・ひらがな 80・カタカナ 81）。
かなは清音 46 ＋ 濁音 20 ＋ 半濁音 5 ＋ 小書き 9 で、カタカナにはさらに
長音符「ー」があります。KanjiVG 全 6,702 字は 6.4 MB あり、使わない字を
抱える理由がないため絞っています。

## 作り直しかた

```sh
curl -LO https://github.com/KanjiVG/kanjivg/releases/download/r20250816/kanjivg-20250816.xml.gz
gunzip kanjivg-20250816.xml.gz
dart run tool/extract_kanjivg.dart kanjivg-20250816.xml
```

`CharSet` に文字種を足したら流し直してください。出力が追随します。

## 生成フォントとの関係

このデータは**お手本の表示にだけ**使います。生成されるフォントは子供が書いた字から
作られ、このデータそのものは入りません。

なぞって書いた字も素材に使えます。書体そのものは日本では原則として著作物にあたらず
（最判平成12年9月7日・ゴナU書体事件）、なぞった字形に KanjiVG の著作権は及ばないと
考えられるためです。

一方で、**未収集の文字を KanjiVG の字形で埋めることは決してしません**（SPEC 6.3）。
そちらは字形ではなくデータの複製にあたり、話が別です。
