import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../export/collected_font.dart';
import '../export/font_export.dart';
import '../font/font_builder.dart';
import '../model/char_set.dart';
import '../store/sample_store.dart';
import 'writing_screen.dart';

/// 集めた字の一覧。アプリの入口。
///
/// 子供にとっては「どこまで集めたか」の画面、親にとってはフォントの出口になる。
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({
    super.key,
    required this.store,
    required this.speaker,
  });

  final SampleStore store;
  final Speaker speaker;

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
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final charSet in CharSet.values)
                _CharSetSection(
                  charSet: charSet,
                  store: store,
                  speaker: speaker,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    if (store.collectedChars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('まだ字がありません')),
      );
      return;
    }

    final format = await showModalBottomSheet<FontFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final format in FontFormat.values)
              ListTile(
                leading: const Icon(Icons.font_download_outlined),
                title: Text(format.name.toUpperCase()),
                onTap: () => Navigator.of(context).pop(format),
              ),
          ],
        ),
      ),
    );
    if (format == null || !context.mounted) return;

    final progress = ValueNotifier<(int, int)>((0, store.collectedChars.length));
    final dialog = _showProgress(context, progress);

    final meta = FontMetadata(familyName: 'AsoGlyph', created: DateTime.now());
    final bytes = await buildCollectedFont(
      store: store,
      meta: meta,
      format: format,
      onProgress: (done, total) => progress.value = (done, total),
    );

    if (context.mounted) Navigator.of(context).pop();
    await dialog;
    progress.dispose();

    await shareFont(
      bytes: bytes,
      fileName: '${sanitizeFileName(meta.familyName)}.${format.name}',
      format: format,
      text: 'あそんでフォントでつくったフォント',
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

class _CharSetSection extends StatelessWidget {
  const _CharSetSection({
    required this.charSet,
    required this.store,
    required this.speaker,
  });

  final CharSet charSet;
  final SampleStore store;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) {
    final collected = charSet.chars
        .where((char) => store.latestMaterialId(char) != null)
        .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: collected / charSet.chars.length,
                  strokeWidth: 5,
                  backgroundColor: const Color(0xffe4dfd4),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                charSet.label,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Text(
                '$collected / ${charSet.chars.length}',
                style: const TextStyle(color: Color(0xff9c948a)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final char in charSet.chars)
                _CharTile(char: char, store: store, speaker: speaker),
            ],
          ),
        ],
      ),
    );
  }
}

class _CharTile extends StatelessWidget {
  const _CharTile({
    required this.char,
    required this.store,
    required this.speaker,
  });

  final String char;
  final SampleStore store;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) {
    final collected = store.latestMaterialId(char) != null;
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
            color: collected ? scheme.primary : const Color(0xffe4dfd4),
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) =>
                  WritingScreen(char: char, store: store, speaker: speaker),
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
                    color: collected ? scheme.onPrimaryContainer : const Color(0xff9c948a),
                  ),
                ),
              ),
              if (collected)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Icon(Icons.star, size: 14, color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
