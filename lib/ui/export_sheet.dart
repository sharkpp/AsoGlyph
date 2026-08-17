import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../font/font_builder.dart';

/// 出力の選択。形式と、なぞった字を混ぜるかどうか。
class ExportChoice {
  const ExportChoice(this.format, this.includeTraced);

  final FontFormat format;
  final bool includeTraced;
}

/// フォントを出す前に、形式となぞりの扱いを選ばせる（SPEC 7.7）。
///
/// なぞった字とそれ以外は別の履歴として持っている。混ぜれば字数は増えるが、
/// 混ぜた字はお手本の形をなぞったもので、その子の字とは言いにくい。
/// どちらを取るかは親が決める。既定は混ぜない。
Future<ExportChoice?> showExportSheet(
  BuildContext context, {
  required int written,
  required int withTraced,
}) {
  return showModalBottomSheet<ExportChoice>(
    context: context,
    builder: (context) => _ExportSheet(written: written, withTraced: withTraced),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.written, required this.withTraced});

  /// なぞり以外で集まった字数。
  final int written;

  /// なぞりも混ぜたときの字数。
  final int withTraced;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  var _includeTraced = false;

  @override
  Widget build(BuildContext context) {
    final extra = widget.withTraced - widget.written;
    final count = _includeTraced ? widget.withTraced : widget.written;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            value: _includeTraced,
            // 足せる字が無いときに選ばせても意味がない。
            onChanged: extra == 0
                ? null
                : (on) => setState(() => _includeTraced = on),
            secondary: const Icon(Icons.gesture),
            title: const Text('なぞった字も入れる'),
            subtitle: Text(extra == 0 ? 'なぞっただけの字はありません' : 'ほかに $extra 字'),
          ),
          const Divider(height: 1),
          for (final format in FontFormat.values)
            ListTile(
              leading: const Icon(Icons.font_download_outlined),
              title: Text(format.name.toUpperCase()),
              trailing: Text('$count 字'),
              // 字が 1 つも無い組み合わせでは出しても仕方がない。
              enabled: count > 0,
              onTap: () =>
                  Navigator.of(context).pop(ExportChoice(format, _includeTraced)),
            ),
        ],
      ),
    );
  }
}

/// フォント生成のあいだ、進み具合だけを見せる。
Future<void> showExportProgress(
  BuildContext context,
  ValueListenable<(int, int)> progress,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      content: ValueListenableBuilder(
        valueListenable: progress,
        builder: (context, value, _) {
          final (done, total) = value;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(value: total == 0 ? null : done / total),
              const SizedBox(width: 24),
              Text('$done / $total'),
            ],
          );
        },
      ),
    ),
  );
}
