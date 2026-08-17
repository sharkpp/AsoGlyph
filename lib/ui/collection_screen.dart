import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../export/collected_font.dart';
import '../export/font_export.dart';
import '../font/font_builder.dart';
import '../kanjivg/stroke_order.dart';
import '../model/char_set.dart';
import '../model/sample.dart';
import '../store/sample_store.dart';
import 'about.dart';
import 'char_set_screen.dart';

/// 文字種の一覧。アプリの入口。
///
/// 子供にとっては「どこまで集めたか」の画面、親にとってはフォントの出口になる。
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.store,
    required this.speaker,
    required this.strokeOrders,
  });

  final SampleStore store;
  final Speaker speaker;
  final StrokeOrderLibrary strokeOrders;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  /// 3 つの練習モードのどれで書くか。書く前に選ばせる（SPEC 7.1）。
  ///
  /// 既定はお手本あり。いちばん多くの子が始められるところに置く。
  var _mode = PracticeMode.copy;

  SampleStore get store => widget.store;
  Speaker get speaker => widget.speaker;
  StrokeOrderLibrary get strokeOrders => widget.strokeOrders;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        title: const Text('あそんでフォント'),
        actions: [
          IconButton(
            iconSize: 28,
            icon: const Icon(Icons.ios_share),
            tooltip: 'フォントをつくる',
            onPressed: () => _export(context),
          ),
          IconButton(
            iconSize: 28,
            icon: const Icon(Icons.info_outline),
            tooltip: 'このアプリについて',
            onPressed: () =>
                showAboutAsoGlyph(context, onClear: () => _clearAll(context)),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ModeChoice(mode: _mode, onChanged: _chooseMode),
              const SizedBox(height: 24),
              for (final charSet in CharSet.values)
                _CharSetCard(
                  charSet: charSet,
                  store: store,
                  onTap: () => _openCharSet(context, charSet),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCharSet(BuildContext context, CharSet charSet) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CharSetScreen(
          charSet: charSet,
          store: store,
          speaker: speaker,
          strokeOrders: strokeOrders,
          mode: _mode,
        ),
      ),
    );
  }

  void _chooseMode(PracticeMode mode) {
    setState(() => _mode = mode);
    // 字が読めなくても、どちらを選んだか分かるようにする（SPEC 2）。
    speaker.speak(switch (mode) {
      PracticeMode.copy => 'おてほんを みて かこう',
      PracticeMode.free => 'じぶんで かいてみよう',
      PracticeMode.trace => 'なぞって かこう',
    });
  }

  Future<void> _clearAll(BuildContext context) async {
    if (!await confirmClearAll(context)) return;
    await store.clear();
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _export(BuildContext context) async {
    final written = store.collectedChars(includeTraced: false).length;
    final withTraced = store.collectedChars(includeTraced: true).length;
    if (withTraced == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('まだ字がありません')));
      return;
    }

    final choice = await showModalBottomSheet<_ExportChoice>(
      context: context,
      builder: (context) =>
          _ExportSheet(written: written, withTraced: withTraced),
    );
    if (choice == null || !context.mounted) return;

    final progress = ValueNotifier<(int, int)>((
      0,
      choice.includeTraced ? withTraced : written,
    ));
    final dialog = _showProgress(context, progress);

    final meta = FontMetadata(familyName: 'AsoGlyph', created: DateTime.now());
    final bytes = await buildCollectedFont(
      store: store,
      meta: meta,
      format: choice.format,
      includeTraced: choice.includeTraced,
      onProgress: (done, total) => progress.value = (done, total),
    );

    if (context.mounted) Navigator.of(context).pop();
    await dialog;
    progress.dispose();

    await shareFont(
      bytes: bytes,
      fileName: '${sanitizeFileName(meta.familyName)}.${choice.format.name}',
      format: choice.format,
      text: 'あそんでフォントでつくったフォント',
    );
  }
}

/// 出力の選択。形式と、なぞった字を混ぜるかどうか。
class _ExportChoice {
  const _ExportChoice(this.format, this.includeTraced);

  final FontFormat format;
  final bool includeTraced;
}

/// フォントを出す前に、形式となぞりの扱いを選ばせる。
///
/// なぞった字とそれ以外は別の履歴として持っている。混ぜれば字数は増えるが、
/// 混ぜた字はお手本の形をなぞったもので、その子の字とは言いにくい。
/// どちらを取るかは親が決める。
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
            subtitle: Text(
              extra == 0 ? 'なぞっただけの字はありません' : 'ほかに $extra 字',
            ),
          ),
          const Divider(height: 1),
          for (final format in FontFormat.values)
            ListTile(
              leading: const Icon(Icons.font_download_outlined),
              title: Text(format.name.toUpperCase()),
              trailing: Text('$count 字'),
              // 字が 1 つも無い組み合わせでは出しても仕方がない。
              enabled: count > 0,
              onTap: () => Navigator.of(
                context,
              ).pop(_ExportChoice(format, _includeTraced)),
            ),
        ],
      ),
    );
  }
}

/// フォント生成のあいだ、進み具合だけを見せる。
Future<void> _showProgress(
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
              CircularProgressIndicator(
                value: total == 0 ? null : done / total,
              ),
              const SizedBox(width: 24),
              Text('$done / $total'),
            ],
          );
        },
      ),
    ),
  );
}

/// 書く前に、どこまで見せてもらうかを選ばせる。
///
/// なぞる → お手本を見る → 何も見ない、と難しくなる並びにしてある。
/// 「お手本なしで書けた」は子供にとって手応えのある目標で、親にとっては
/// より素の字が集まる手段になる。
///
/// なぞり書きだけは、字形をなぞっただけなのでフォントの素材に採らない（SPEC 7.1）。
class _ModeChoice extends StatelessWidget {
  const _ModeChoice({required this.mode, required this.onChanged});

  final PracticeMode mode;
  final ValueChanged<PracticeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PracticeMode>(
      // タップターゲットは 64dp 以上（SPEC 9）。
      style: SegmentedButton.styleFrom(minimumSize: const Size(0, 64)),
      // 選んだ印にチェックを足さない。色が変わればじゅうぶんで、
      // チェックが入るとアイコンの位置がずれて何を選んだか分かりにくい。
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: PracticeMode.trace,
          label: _ModeLabel(icon: Icons.gesture, text: 'なぞる'),
        ),
        ButtonSegment(
          value: PracticeMode.copy,
          label: _ModeLabel(icon: Icons.visibility, text: 'おてほん'),
        ),
        ButtonSegment(
          value: PracticeMode.free,
          label: _ModeLabel(icon: Icons.volume_up, text: 'じぶんで'),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selected) => onChanged(selected.single),
    );
  }
}

/// アイコンの下に文字。
///
/// `ButtonSegment.icon` は文字の横に並ぶため、スマホ幅では 3 つ入らず
/// 文字が折り返して見切れる。字が読めない子には上のアイコンだけで足りる。
class _ModeLabel extends StatelessWidget {
  const _ModeLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 28),
        const SizedBox(height: 2),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

/// 文字種ひとまとまりの入口。輪で充足率を、中の字でどの束かを見せる。
class _CharSetCard extends StatelessWidget {
  const _CharSetCard({
    required this.charSet,
    required this.store,
    required this.onTap,
  });

  final CharSet charSet;
  final SampleStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffe4dfd4), width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: CharSetRing(charSet: charSet, store: store)),
                const Icon(Icons.chevron_right, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
