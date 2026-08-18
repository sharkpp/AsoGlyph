import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../font/glyph.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../kanjivg/stroke_order.dart';
import '../model/char_set.dart';
import '../model/sample.dart';
import '../practice/scoring.dart';
import '../store/sample_store.dart';
import '../trace/glyph_builder.dart';
import 'glyph_preview.dart';
import 'stroke_order_view.dart';
import 'writing_guide.dart';

/// ひとまとまりの中で、いま何字めを書いているか。
///
/// 語を書く導線（SPEC 7.4）と、おまかせの導線（SPEC 7.3）が使う。
/// 1 字だけ練習するときは null。
class WritingSteps {
  const WritingSteps({
    required this.chars,
    required this.index,
    this.reading,
  });

  /// 書く順に並んだ字。
  final List<String> chars;

  /// 0 始まり。
  final int index;

  /// つながった語としての読み。おまかせのときは null（語ではない）。
  final String? reading;

  bool get isLast => index == chars.length - 1;
}

/// 1 文字を書く画面。
///
/// 「できた！」を押した時点で必ず記録する。字の巧拙で採否を決めないのが
/// この製品の中核であり（SPEC 1）、子供に judge させる導線を作らない。
///
/// 書けたら記録の id を返して閉じる。語を書く導線が、書いた順に集める
/// ため（SPEC 4.2）。書かずに閉じたときは null。
class WritingScreen extends StatefulWidget {
  const WritingScreen({
    super.key,
    required this.char,
    required this.mode,
    required this.store,
    required this.speaker,
    this.strokeOrder,
    this.steps,
  });

  final String char;

  /// ひとまとまりの中の何字めか。1 字だけ練習するときは null。
  final WritingSteps? steps;

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

  /// 書けた記録の id。書き直すたびに新しいものに入れ替わる。
  String? _savedId;

  /// 「もういちど」を押した回数。苦手さの手がかりになる（SPEC 7.3）。
  var _retries = 0;

  /// 小書きの字。枠を小さくして、その中に書かせる（SPEC 5.3）。
  bool get _small => isSmallKana(widget.char);

  /// ひとまとまりの途中で、まだ続きの字があるか。
  bool get _continues => widget.steps != null && !widget.steps!.isLast;

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
  ///
  /// 語を書いているときは語の読みから言う。「ねこ の ね」と言われて
  /// はじめて、いま書いている字がどこの字なのか分かる。
  void _prompt() {
    final reading = widget.steps?.reading;
    final char = readingOf(widget.char);
    widget.speaker.speak(
      reading == null ? '$char、かいてね' : '$reading の $char、かいてね',
    );
    if (_showsStrokeOrder) _playback.forward(from: 0);
  }

  Future<void> _finish() async {
    // 指を置いたままでも押せるボタンなので、書きかけの画をここで確定させる。
    // 「できた！」が押せる状態と、記録に残る画がずれてはいけない。
    _ink.end();
    final strokes = _ink.strokes;
    if (strokes.isEmpty) return;

    setState(() => _busy = true);

    final glyph = await buildGlyph(char: widget.char, strokes: strokes);
    // 測るのは出題の重み付けのため。フォントに載せるかは決めない（SPEC 1）。
    // 例外は鏡文字と明らかな書き損じだけ。
    final sample = Sample.now(
      char: widget.char,
      mode: widget.mode,
      strokes: strokes,
      score: scoreStrokes(
        strokes: strokes,
        model: widget.strokeOrder,
        retries: _retries,
      ),
      rejected: detectRejected(strokes: strokes, model: widget.strokeOrder),
    );
    await widget.store.add(sample);

    if (!mounted) return;
    setState(() {
      _glyph = glyph;
      _savedId = sample.id;
      _busy = false;
    });
    // なぞりはフォントに入らない。ほめたうえで、次の段へ誘う（SPEC 7.1）。
    widget.speaker.speak(
      widget.mode == PracticeMode.trace
          ? 'なぞれたね！ こんどは じぶんで かいてみよう'
          : 'できたね！',
    );
  }

  void _again() {
    _ink.clear();
    setState(() {
      _glyph = null;
      _retries++;
    });
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
              child: Column(
                children: [
                  if (widget.steps != null) ...[
                    _buildSteps(widget.steps!),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
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
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// ひとまとまりのどこを書いているか。
  ///
  /// 語なら、3 字めまで書いたのに何の語か分からない、という状態を作らない
  /// （SPEC 7.4）。おまかせなら、あと何字で終わるかが見える（SPEC 7.1 の
  /// 「1 セッションを区切る」）。
  ///
  /// 何も見ずに書くモードでは、まだ書いていない字を伏せる。字が出ていると
  /// 音を頼りに書くという前提が崩れる（SPEC 7.1）。
  Widget _buildSteps(WritingSteps progress) {
    final scheme = Theme.of(context).colorScheme;
    final chars = progress.chars;
    final hides = widget.mode == PracticeMode.free;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final (index, char) in chars.indexed)
          Container(
            width: 44,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: index == progress.index
                  ? scheme.primaryContainer
                  : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: index == progress.index
                    ? scheme.primary
                    : const Color(0xffe4dfd4),
                width: 2,
              ),
            ),
            child: Text(
              hides && index >= progress.index ? '？' : char,
              style: TextStyle(
                fontSize: 28,
                height: 1,
                color: index <= progress.index
                    ? const Color(0xff6f665c)
                    : const Color(0xffbdb4a6),
              ),
            ),
          ),
      ],
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
              Padding(
                padding: const EdgeInsets.all(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 書き取り枠と同じ十字を敷く。お手本と自分の字を、
                    // 同じ物差しで見比べられるようにする（SPEC 7.1）。
                    WritingGuide(border: false, small: _small),
                    if (_busy)
                      const Center(child: CircularProgressIndicator())
                    else if (glyph == null)
                      _buildPrompt()
                    else
                      GlyphPreview(contours: glyph.contours),
                  ],
                ),
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
    return StrokeOrderView(
      order: order,
      progress: _playback,
      showNumbers: true,
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
                    WritingGuide(small: _small),
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
                onPressed: () => Navigator.of(context).pop(_savedId),
                icon: Icon(_continues ? Icons.arrow_forward : Icons.check, size: 32),
                label: Text(_continues ? 'つぎ' : 'おわり'),
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
