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

### `dakuten.json` — 濁点・半濁点の置き場所

```json
{ "が": [739.4, 755.1, 877.3, 878.0], ... }
```

濁音字 → `[left, bottom, right, top]`。em 空間（0..1000、左下原点・y 上向き）。

KanjiVG は濁音字を「清音の画 ＋ 濁点の画」として持っています（が = か 3 画 ＋ 2 画）。
清音の画数から先を濁点とみなし、その範囲を囲む矩形を出しています。

**矩形だけを出し、KanjiVG の濁点そのものは同梱していません。** フォントに載る
濁点は、子供が書いたものでなければならないためです。

## 作り直しかた

```sh
curl -LO https://github.com/KanjiVG/kanjivg/releases/download/r20250816/kanjivg-20250816.xml.gz
gunzip kanjivg-20250816.xml.gz
dart run tool/extract_kanjivg.dart kanjivg-20250816.xml
```

`CharSet` に文字種を足したら流し直してください。出力が追随します。

## 生成フォントとの関係

このデータは**お手本の表示にだけ**使います。生成されるフォントは子供の筆跡だけ
から作られ、KanjiVG の二次的著作物にはなりません。そのため、未収集の文字を
KanjiVG の字形で埋めることは決してしません（SPEC 6.3）。
