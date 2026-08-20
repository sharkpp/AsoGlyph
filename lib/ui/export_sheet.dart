import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../export/collected_font.dart';
import '../export/font_export.dart';
import '../export/resolve_recipe.dart';
import '../font/font_builder.dart';
import '../model/font_recipe.dart';
import '../store/sample_store.dart';

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

/// 版のフォントを出力する（SPEC 7.7）。
///
/// 形式となぞりの扱いを選ばせ、作って、共有に渡すまで。版の一覧からも
/// 版の画面からも同じ道を通る。出力は管理画面だけの入口にしてあり、
/// 子供向け画面には置かない。
Future<void> exportRecipeFont(
  BuildContext context, {
  required FontRecipe recipe,
  required SampleStore store,
}) async {
  final written = resolvedCount(recipe, store, includeTraced: false);
  final withTraced = resolvedCount(recipe, store, includeTraced: true);
  if (withTraced == 0) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('この版に入る字がありません')));
    return;
  }

  final choice = await showExportSheet(
    context,
    written: written,
    withTraced: withTraced,
  );
  if (choice == null || !context.mounted) return;

  final progress = ValueNotifier<(int, int)>((
    0,
    choice.includeTraced ? withTraced : written,
  ));
  final dialog = showExportProgress(context, progress);

  final bytes = await buildRecipeFont(
    recipe: recipe,
    store: store,
    format: choice.format,
    includeTraced: choice.includeTraced,
    onProgress: (done, total) => progress.value = (done, total),
  );

  if (context.mounted) Navigator.of(context).pop();
  await dialog;
  progress.dispose();

  try {
    await shareFont(
      bytes: bytes,
      fileName:
          '${sanitizeFileName(recipe.fontMeta.familyName)}.${choice.format.name}',
      format: choice.format,
      subject: '「${recipe.name}」のフォント',
    );
  } catch (error) {
    // 黙って何も起きないと、作れたのか出せなかったのかが分からない。
    debugPrint('フォントの書き出しに失敗: $error');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('フォントを出せませんでした（$error）')),
      );
    }
  }
}
