import 'package:flutter/material.dart';

import '../export/font_export.dart';
import '../font/font_builder.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../trace/contour_tracer.dart';
import '../trace/stroke_rasterizer.dart';
import 'glyph_preview.dart';
import 'writing_guide.dart';

/// L1 の画面。1 文字書いて、その場でフォントにする。
///
/// 収集の対象はひらがな清音 46 字だが、まずは 1 文字で縦断を通す。
class WritingScreen extends StatefulWidget {
  const WritingScreen({super.key});

  @override
  State<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends State<WritingScreen> {
  /// ラスタトレースの解像度。em 1000 に対して 1 単位あたり 1 ピクセル。
  static const _rasterSize = 1024;
  static const _target = 'あ';
  static const _tracer = ContourTracer();

  final _ink = InkController();
  List<Contour>? _contours;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 書き直したら前のプレビューは無効になる。
    _ink.addListener(_onInkChanged);
  }

  @override
  void dispose() {
    _ink
      ..removeListener(_onInkChanged)
      ..dispose();
    super.dispose();
  }

  void _onInkChanged() {
    if (_contours != null) setState(() => _contours = null);
  }

  Future<void> _buildGlyph() async {
    setState(() => _busy = true);
    final alpha = await rasterizeStrokes(
      strokes: _ink.strokes,
      imageSize: _rasterSize,
    );
    final contours = _tracer.trace(alpha: alpha, imageSize: _rasterSize);
    if (!mounted) return;
    setState(() {
      _contours = contours;
      _busy = false;
    });
  }

  Future<void> _export(FontFormat format) async {
    final contours = _contours;
    if (contours == null || contours.isEmpty) return;

    final meta = FontMetadata(familyName: 'AsoGlyph', created: DateTime.now());
    final bytes = buildFont(
      meta: meta,
      glyphs: [
        Glyph(
          codePoint: _target.runes.first,
          contours: contours,
          advanceWidth: meta.unitsPerEm,
        ),
      ],
      format: format,
    );

    await shareFont(
      bytes: bytes,
      fileName: '${sanitizeFileName(meta.familyName)}.${format.name}',
      format: format,
      text: '「$_target」からつくったフォント',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfffaf7f0),
      appBar: AppBar(
        title: const Text('あそんでフォント'),
        backgroundColor: const Color(0xfffaf7f0),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // タブレットでは書き取り面と結果を横に並べ、スマホでは縦に積む。
            final wide = constraints.biggest.shortestSide >= 600;
            final canvas = _buildCanvasArea();
            final panel = _buildPanel();

            return Padding(
              padding: const EdgeInsets.all(16),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: canvas),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: panel),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: canvas),
                        const SizedBox(height: 16),
                        panel,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCanvasArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '「$_target」を かいてみよう',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        // 書き取り面は必ず正方形に保つ。縦横比が変わると字形が歪む。
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Colors.white),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const WritingGuide(),
                    InkCanvas(controller: _ink),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _ink,
          builder: (context, _) => Wrap(
            spacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _ink.isEmpty ? null : _ink.undo,
                icon: const Icon(Icons.undo),
                label: const Text('もどす'),
              ),
              OutlinedButton.icon(
                onPressed: _ink.isEmpty ? null : _ink.clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('けす'),
              ),
              FilledButton.icon(
                onPressed: _ink.isEmpty || _busy ? null : _buildGlyph,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('できた！'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    final contours = _contours;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'フォントの字',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xffe4dfd4)),
              ),
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : contours == null
                  ? const Center(
                      child: Text(
                        'かきおわったら\n「できた！」',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xff9c948a)),
                      ),
                    )
                  : GlyphPreview(contours: contours),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (contours != null && contours.isNotEmpty) ...[
          Text(
            '輪郭 ${contours.length} 本 / '
            'セグメント ${contours.fold(0, (n, c) => n + c.segs.length)} 個',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xff9c948a), fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final format in FontFormat.values)
                FilledButton.tonalIcon(
                  onPressed: () => _export(format),
                  icon: const Icon(Icons.ios_share),
                  label: Text(format.name.toUpperCase()),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
