import 'package:flutter/material.dart';

import '../export/resolve_recipe.dart';
import '../model/font_recipe.dart';
import '../model/sample.dart';
import '../store/sample_store.dart';
import 'admin_screen.dart' show formatDate;
import 'stroke_preview.dart';

/// 日付をドラッグすると見本が変わるスライダー（SPEC 7.6）。
///
/// 「あの頃」がいつなのかは、日付を数字で見ても分からない。字そのものが
/// 変わるのを見て決められるようにする。
///
/// ここは保護者向け画面なので、ドラッグを使ってよい（SPEC 9 の制約は子供向け画面）。
class TimelineSlider extends StatelessWidget {
  const TimelineSlider({
    super.key,
    required this.recipe,
    required this.store,
    required this.time,
    required this.onChanged,
  });

  final FontRecipe recipe;
  final SampleStore store;

  /// いま選んでいる時点。
  final DateTime time;

  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final earliest = store.earliestWrittenAt;
    if (earliest == null) return const SizedBox.shrink();

    // 端を含めたいので、初日の 0 時から今日の終わりまでを動かす。
    final from = DateTime(earliest.year, earliest.month, earliest.day);
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day, 23, 59, 59);
    if (!to.isAfter(from)) return const SizedBox.shrink();

    final value = time.clamp(from, to);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Preview(recipe: recipe, store: store, time: value),
        Slider(
          min: from.millisecondsSinceEpoch.toDouble(),
          max: to.millisecondsSinceEpoch.toDouble(),
          value: value.millisecondsSinceEpoch.toDouble(),
          label: formatDate(value),
          divisions: to.difference(from).inDays.clamp(1, 3650),
          onChanged: (milliseconds) => onChanged(
            DateTime.fromMillisecondsSinceEpoch(milliseconds.round()),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatDate(from), style: _hint),
            Text(formatDate(to), style: _hint),
          ],
        ),
      ],
    );
  }

  static const _hint = TextStyle(fontSize: 12, color: Color(0xff9c948a));
}

/// その時点の字を数文字ぶん出す。
///
/// 全部は出さない。動かすたびに読み直すので、数が増えると付いてこない。
class _Preview extends StatelessWidget {
  const _Preview({
    required this.recipe,
    required this.store,
    required this.time,
  });

  static const _shown = 6;

  final FontRecipe recipe;
  final SampleStore store;
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveRecipe(
      recipe.copyWith(base: AtPolicy(time), charRules: const {}),
      store,
      includeTraced: false,
    );
    final chars = resolved.keys.toList()..sort();

    return SizedBox(
      height: 72,
      child: chars.isEmpty
          ? const Center(
              child: Text(
                'この日までに書いた字はまだありません',
                style: TextStyle(color: Color(0xff9c948a)),
              ),
            )
          : Row(
              children: [
                for (final char in chars.take(_shown))
                  Expanded(
                    child: _Glyph(
                      // 字が変わったら作り直す。前の字が残らないようにする。
                      key: ValueKey(resolved[char]),
                      store: store,
                      sampleId: resolved[char]!,
                    ),
                  ),
                if (chars.length > _shown)
                  Expanded(
                    child: Center(
                      child: Text(
                        'ほか\n${chars.length - _shown} 字',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff9c948a),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({super.key, required this.store, required this.sampleId});

  final SampleStore store;
  final String sampleId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Sample>(
      future: store.read(sampleId),
      builder: (context, snapshot) {
        final sample = snapshot.data;
        if (sample == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.all(4),
          child: StrokePreview(strokes: sample.strokes),
        );
      },
    );
  }
}

extension on DateTime {
  DateTime clamp(DateTime from, DateTime to) {
    if (isBefore(from)) return from;
    if (isAfter(to)) return to;
    return this;
  }
}
