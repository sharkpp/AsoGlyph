import 'dart:convert';

import 'package:flutter/services.dart';

import '../compose/dakuten.dart';

/// 濁点・半濁点をどこへ置くかの表（SPEC 5.1）。
///
/// KanjiVG の濁音字から、濁点の画だけを囲む矩形を測ったもの。置き場所は
/// 清音ごとに違う（じ は真ん中寄り、ぽ は右下がり）ので、字ごとに持つ。
///
/// 入っているのは矩形だけで、KanjiVG の濁点そのものは持たない。フォントに
/// 載るのは子供が書いた濁点でなければならない（SPEC 6.3）。
class DakutenPlacements {
  const DakutenPlacements._(this._byChar);

  final Map<String, EmBox> _byChar;

  static const _asset = 'assets/kanjivg/dakuten.json';

  static Future<DakutenPlacements> load({AssetBundle? bundle}) async {
    final json = await (bundle ?? rootBundle).loadString(_asset);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return DakutenPlacements._({
      for (final entry in decoded.entries)
        entry.key: _boxOf((entry.value as List).cast<num>()),
    });
  }

  EmBox? operator [](String char) => _byChar[char];
}

EmBox _boxOf(List<num> values) => EmBox(
  left: values[0].toDouble(),
  bottom: values[1].toDouble(),
  right: values[2].toDouble(),
  top: values[3].toDouble(),
);
