import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../font/glyph.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../kanjivg/stroke_order.dart';
import '../model/char_set.dart';
import '../model/sample.dart';
import '../store/sample_store.dart';
import '../trace/glyph_builder.dart';
import 'glyph_preview.dart';
import 'stroke_order_view.dart';
import 'writing_guide.dart';

/// 1 文字を書く画面。
///
/// 「できた！」を押した時点で必ず記録する。字の巧拙で採否を決めないのが
/// この製品の中核であり（SPEC 1）、子供に judge させる導線を作らない。
class WritingScreen extends StatefulWidget {
  const WritingScreen({
    super.key,
    required this.char,
    required this.mode,
    required this.store,
    required this.speaker,
    this.strokeOrder,
  });

  final String char;

  /// お手本を出すか、音だけで書かせるか（SPEC 7.1）。
  final PracticeMode mode;

  final SampleStore store;
  final Speaker speaker;

  /// この字の書き順。KanjiVG に無い字では null になる。
  final StrokeOrder? strokeOrder;

  @override
  State<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends State<WritingScreen>
    with SingleTickerProviderStateMixin {
  final _ink = InkController();
  late final AnimationController _playback;
  Glyph? _glyph;
  bool _busy = false;

  /// お手本を出すモードで、書き順のデータもある。
  bool get _showsStrokeOrder =>
      widget.mode != PracticeMode.free && widget.strokeOrder != null;

  @override
  void initState() {
    super.initState();
    // 書き直したら前の結果は無効になる。
    _ink.addListener(_onInkChanged);
    _playback = AnimationController(
      vsync: this,
      duration: widget.strokeOrder == null
          ? Duration.zero
          : StrokeOrderView.playbackOf(widget.strokeOrder!),
    );
    _prompt();
  }

  @override
  void dispose() {
    widget.speaker.stop();
    _playback.dispose();
    _ink
      ..removeListener(_onInkChanged)
      ..dispose();
    super.dispose();
  }

  void _onInkChanged() {
    if (_glyph != null) setState(() => _glyph = null);
  }

  /// 何を書けばいいかを伝える。字が読めなくても始められるように、
  /// 声で読みを言い、同時に書き順を頭から見せる（SPEC 2 / 7.1）。
  void _prompt() {
    widget.speaker.speak('${readingOf(widget.char)}、かいてね');
    if (_showsStrokeOrder) _playback.forward(from: 0);
  }

  Future<void> _finish() async {
    setState(() => _busy = true);

    final strokes = _ink.strokes;
    final glyph = await buildGlyph(char: widget.char, strokes: strokes);
    await widget.store.add(
      Sample.now(char: widget.char, mode: widget.mode, strokes: strokes),
    );

    if (!mounted) return;
    setState(() {
      _glyph = glyph;
      _busy = false;
    });
    widget.speaker.speak('できたね！');
  }

  void _again() {
    _ink.clear();
    setState(() => _glyph = null);
    _prompt();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        leading: IconButton(
          iconSize: 32,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // タブレットではお手本を横に置き、スマホでは上に置く。
            final wide = constraints.biggest.shortestSide >= 600;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: Center(child: _buildModel())),
                        Expanded(flex: 2, child: _buildCanvasArea()),
                      ],
                    )
                  : Column(
                      children: [
                        _buildModel(),
                        const SizedBox(height: 12),
                        Expanded(child: _buildCanvasArea()),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  /// お手本の枠。書けたあとは、そのままフォントの字形に入れ替わる。
  ///
  /// 書いているあいだは、押すと読みをもう一度言う。子供向け画面はタップだけで
  /// 完結させるため（SPEC 9）、読み上げボタンを別に置かず枠そのものを押させる。
  Widget _buildModel() {
    final glyph = _glyph;
    final canReplay = !_busy && glyph == null;

    return SizedBox(
      width: 180,
      height: 180,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffe4dfd4), width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canReplay ? _prompt : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else if (glyph == null)
                _buildPrompt()
              else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: GlyphPreview(contours: glyph.contours),
                ),
              // 何も見ずに書くモードでは、枠そのものが読み上げボタンになっている。
              if (canReplay && widget.mode != PracticeMode.free)
                const Positioned(
                  right: 8,
                  bottom: 8,
                  child: Icon(
                    Icons.volume_up,
                    size: 28,
                    color: Color(0xffbdb4a6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// まだ書き上げていないあいだ、枠に出すもの。
  ///
  /// 何も見ずに書くモードでは字を出さない。頼れるのは音だけになる（SPEC 7.1）。
  Widget _buildPrompt() {
    if (widget.mode == PracticeMode.free) {
      return const Center(
        child: Icon(Icons.volume_up, size: 96, color: Color(0xff9c948a)),
      );
    }
    final order = widget.strokeOrder;
    if (order == null) {
      // 書き順を持たない字は、システムのフォントで見せるほかない。
      return Center(
        child: Text(
          widget.char,
          style: const TextStyle(
            fontSize: 120,
            height: 1,
            color: Color(0xff6f665c),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: StrokeOrderView(
        order: order,
        progress: _playback,
        showNumbers: true,
      ),
    );
  }

  Widget _buildCanvasArea() {
    return Column(
      children: [
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
                    // なぞり書きは、字形を薄く敷いてその上をなぞらせる。
                    if (widget.mode == PracticeMode.trace &&
                        widget.strokeOrder != null)
                      StrokeOrderView(
                        order: widget.strokeOrder!,
                        progress: kAlwaysCompleteAnimation,
                        color: const Color(0xffddd6c9),
                      ),
                    InkCanvas(controller: _ink),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildActions(),
      ],
    );
  }

  Widget _buildActions() {
    // タップターゲットは 64dp 以上（SPEC 9）。
    const size = Size(96, 64);

    return AnimatedBuilder(
      animation: _ink,
      builder: (context, _) {
        if (_glyph != null) {
          return Wrap(
            spacing: 16,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: size),
                onPressed: _again,
                icon: const Icon(Icons.refresh, size: 32),
                label: const Text('もういちど'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: size),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check, size: 32),
                label: const Text('おわり'),
              ),
            ],
          );
        }

        return Wrap(
          spacing: 16,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 64)),
              onPressed: _ink.isEmpty ? null : _ink.undo,
              child: const Icon(Icons.undo, size: 32),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 64)),
              onPressed: _ink.isEmpty ? null : _ink.clear,
              child: const Icon(Icons.delete_outline, size: 32),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: size),
              onPressed: _ink.isEmpty || _busy ? null : _finish,
              icon: const Icon(Icons.auto_awesome, size: 32),
              label: const Text('できた！'),
            ),
          ],
        );
      },
    );
  }
}
