import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../font/glyph.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../ink/stroke.dart';
import '../kanjivg/stroke_order.dart';
import '../model/char_set.dart';
import '../model/sample.dart';
import '../practice/scoring.dart';
import '../store/sample_store.dart';
import '../trace/glyph_builder.dart';
import 'glyph_preview.dart';
import 'stroke_order_view.dart';
import 'writing_guide.dart';

/// 書き取り画面から返るもの。
///
/// 書けた（記録の id の並び）・この語はやめた・何もせず閉じた、の 3 つを分ける。
/// 語を出す導線が、次の語へ行くか・やめるかを決める。
class WritingResult {
  const WritingResult.written(this.sampleIds) : skipped = false;
  const WritingResult.skipped() : sampleIds = const [], skipped = true;

  /// 書けた記録の id。書いた順に並ぶ（SPEC 4.2）。
  final List<String> sampleIds;

  /// この語はやめて、次の語へ行きたい。
  final bool skipped;
}

/// 字を書く画面。
///
/// **語をまるごと受け取り、1 字書けたらこの画面のまま次の字へ移る。**
/// 字ごとに画面を積み替えると、切り替わるたびに画面が滑って見え、
/// 読み上げも積み替えのたびに途切れる。1 字だけ練習するときは 1 字の並びを渡す。
///
/// 「できた！」を押した時点で必ず記録する。字の巧拙で採否を決めないのが
/// この製品の中核であり（SPEC 1）、子供に judge させる導線を作らない。
///
/// 閉じるときに [WritingResult] を返す。何もせず閉じたときは null。
class WritingScreen extends StatefulWidget {
  const WritingScreen({
    super.key,
    required this.chars,
    required this.mode,
    required this.store,
    required this.speaker,
    required this.strokeOrders,
    this.given = const {},
    this.reading,
    this.picture,
    this.canSkip = false,
    this.traceErases = true,
  });

  /// 出す並び。書かせない字（[given]）も入る。
  final List<String> chars;

  /// 書かせない字の位置（SPEC 7.4）。
  ///
  /// 「[ウルトラマン]オメガ」の ウルトラマン のように、出しておくだけの字。
  /// 書く順から外すが、並びからは外さない。何の語を書いているのかは、
  /// そこが見えていないと分からない。
  final Set<int> given;

  /// つながった語としての読み。1 字だけの練習では null。
  final String? reading;

  /// 語に添えた絵（SPEC 7.4）。
  ///
  /// 何を書いているのかを、字に頼らず示せる唯一のもの。何も見ずに書く
  /// モードでも出す。絵は字を教えないので、音だけで書くという前提は崩れない。
  final Widget? picture;

  /// この語をやめて、次の語へ行けるか。
  ///
  /// おまかせ（SPEC 7.3）でだけ立てる。出された語が書けない・知らないときに、
  /// そこで手が止まる。自分で選んだ語なら戻ればいいので、置かない。
  /// 同じことをする道を 2 つ置くと、子供向け画面では迷いになる（SPEC 9）。
  final bool canSkip;

  /// お手本を出すか、音だけで書かせるか（SPEC 7.1）。
  final PracticeMode mode;

  /// なぞり書きの下敷きを、ペン先が通ったところから消すか（SPEC 7.1）。
  ///
  /// 人ごとの設定（`User.traceErases`）。切ると、下敷きはその字を書き終える
  /// まで丸ごと残る。線を追うだけで手一杯の子は、消えると引く先を見失う。
  final bool traceErases;

  final SampleStore store;
  final Speaker speaker;
  final StrokeOrderLibrary strokeOrders;

  /// 1 字だけを書かせるか。書けたら止まって、書き直せる。
  bool get isSingle => chars.length - given.length <= 1;

  @override
  State<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends State<WritingScreen>
    with SingleTickerProviderStateMixin {
  final _ink = InkController();
  late final AnimationController _playback;
  Glyph? _glyph;
  bool _busy = false;

  /// いま書いている字の位置。書かせない字は飛ばす。
  late int _index = _firstWritable;

  /// 書けた記録の id。書いた順に並ぶ（SPEC 4.2）。
  final _savedIds = <String>[];

  /// いまの字を書き上げたか。書き直すと入れ替わる。
  String? _savedId;

  /// 「もういちど」を押した回数。苦手さの手がかりになる（SPEC 7.3）。
  var _retries = 0;

  String get _char => widget.chars[_index];

  StrokeOrder? get _strokeOrder => widget.strokeOrders[_char];

  /// 小書きの字。枠を小さくして、その中に書かせる（SPEC 5.3）。
  bool get _small => isSmallKana(_char);

  /// お手本を出すモードで、書き順のデータもある。
  bool get _showsStrokeOrder =>
      widget.mode != PracticeMode.free && _strokeOrder != null;

  int get _firstWritable {
    for (var i = 0; i < widget.chars.length; i++) {
      if (!widget.given.contains(i)) return i;
    }
    return 0;
  }

  /// [_index] のうしろで、次に書く字。もう無ければ null。
  int? get _nextWritable {
    for (var i = _index + 1; i < widget.chars.length; i++) {
      if (!widget.given.contains(i)) return i;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // 書き直したら前の結果は無効になる。
    _ink.addListener(_onInkChanged);
    _playback = AnimationController(vsync: this);
    _prompt();
  }

  @override
  void dispose() {
    // 書き上げたあとは、ほめる声と次の案内が続く。ここで止めると、
    // 画面が切り替わるたびに声がぶつ切りになる。
    // 書かずに閉じたときだけ、言いかけを止める。
    if (_savedIds.isEmpty && _savedId == null) widget.speaker.stop();
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
  /// **語の名前は最初の 1 字でだけ言う。** 字ごとに「ねこ の ね」「ねこ の こ」
  /// と繰り返すと、聞きたい 1 字が毎回うしろに回る。何の語かは 1 度言えば
  /// 足りるし、画面には出たままになっている。
  void _prompt() {
    final reading = widget.reading;
    final intro = reading != null && _index == _firstWritable
        ? '$reading を かこう。'
        : '';
    widget.speaker.speak('$intro${readingOf(_char)} を かいてね');

    final order = _strokeOrder;
    _playback.duration = order == null
        ? Duration.zero
        : StrokeOrderView.playbackOf(order);
    if (_showsStrokeOrder) {
      _playback.forward(from: 0);
    } else {
      _playback.value = 0;
    }
  }

  Future<void> _finish() async {
    // 指を置いたままでも押せるボタンなので、書きかけの画をここで確定させる。
    // 「できた！」が押せる状態と、記録に残る画がずれてはいけない。
    _ink.end();
    final strokes = _ink.strokes;
    if (strokes.isEmpty) return;

    setState(() => _busy = true);

    final glyph = await buildGlyph(char: _char, strokes: strokes);
    // 測るのは出題の重み付けのため。フォントに載せるかは決めない（SPEC 1）。
    // 例外は鏡文字と明らかな書き損じだけ。
    final sample = Sample.now(
      char: _char,
      mode: widget.mode,
      strokes: strokes,
      score: scoreStrokes(
        strokes: strokes,
        model: _strokeOrder,
        retries: _retries,
      ),
      rejected: detectRejected(strokes: strokes, model: _strokeOrder),
    );
    await widget.store.add(sample);

    if (!mounted) return;
    setState(() {
      _glyph = glyph;
      _savedId = sample.id;
      _busy = false;
    });

    // なぞりはフォントに入らない。ほめたうえで、次の段へ誘う（SPEC 7.1）。
    final praise = widget.speaker.speak(
      widget.mode == PracticeMode.trace
          ? 'なぞれたね！ こんどは じぶんで かいてみよう'
          : 'できたね！',
    );

    // 1 字だけの練習は、ここで止まる。書けた字を見ていられるようにする。
    if (widget.isSingle) return;

    // 語を書いているときは、押さずに次の字へ進む。字ごとに「つぎ」を
    // 押させると、書くより押す回数のほうが多くなる。
    //
    // ほめ言葉を言い終わるのを待つが、待ち続けはしない。読み上げの終わりを
    // 知らせない端末があり、そこで待つと音も出ないまま固まって見える。
    await Future.wait([
      Future.any([praise, Future<void>.delayed(_praiseCap)]),
      Future<void>.delayed(_glimpse),
    ]);
    if (!mounted) return;

    _savedIds.add(_savedId!);
    final next = _nextWritable;
    if (next == null) {
      Navigator.of(context).pop(WritingResult.written(List.of(_savedIds)));
      return;
    }

    // 画面はそのまま。字だけが入れ替わる。
    _ink.clear();
    setState(() {
      _index = next;
      _glyph = null;
      _savedId = null;
      _retries = 0;
    });
    _prompt();
  }

  /// この語はやめて、次の語へ（SPEC 7.3）。
  ///
  /// 何が起きたかを声でも言う。黙って別の字に変わると、自分が何かを
  /// 間違えたのかと思う子がいる。
  Future<void> _skip() async {
    await widget.speaker.speak('つぎの ことばに するね');
    if (mounted) Navigator.of(context).pop(const WritingResult.skipped());
  }

  /// いま引いている画の下敷きを、どこまで消すか（0..1）。
  ///
  /// 子供が引いた長さを、お手本のその画の長さと比べて決める。ペン先の
  /// いる場所を探して当てるのではなく、進んだ長さで測る。ずれて書いても
  /// 同じだけ進むので、下敷きは必ずペンについてくる。
  double get _erasedByPen {
    final order = _strokeOrder;
    final active = _ink.activeStroke;
    if (order == null || active == null) return 0;

    final index = _ink.strokes.length;
    if (index >= order.strokeCount) return 0;

    // お手本は viewBox 四方。書いた線は em 空間（0..1000）。
    final model =
        order.strokeLength(index) * 1000 / StrokeOrder.viewBox;
    if (model <= 0) return 1;
    return (_inkLength(active) / model).clamp(0.0, 1.0);
  }

  /// 引いた線の長さ（em 空間）。
  double _inkLength(Stroke stroke) {
    var total = 0.0;
    for (var i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1];
      final b = stroke.points[i];
      total += sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2));
    }
    return total;
  }

  /// 書けた字を見せておく最短の時間。
  ///
  /// 読み上げが無い端末では、ほめ言葉を待っても一瞬で返る。自分の書いた線が
  /// フォントの字形に変わるところは、この製品でいちばん見せたいものなので
  /// （SPEC 8.1）、声が出ないときでもここは見える。
  static const _glimpse = Duration(milliseconds: 700);

  /// ほめ言葉を待つ上限。
  ///
  /// 読み上げの終わりを知らせない端末がある。そこを待ち続けると、音も出ない
  /// まま固まって見える。待つのはここまでにして、先へ進む。
  static const _praiseCap = Duration(milliseconds: 1600);

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
        actions: [
          // 出された語が書けない・知らないときに、そこで手が止まる。
          if (widget.canSkip)
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.skip_next),
              tooltip: 'この ことばは やめる',
              onPressed: _busy ? null : _skip,
            ),
        ],
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
                  if (!widget.isSingle || widget.picture != null) ...[
                    _buildSteps(wide: wide),
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
  Widget _buildSteps({required bool wide}) {
    final scheme = Theme.of(context).colorScheme;
    final chars = widget.chars;
    final hides = widget.mode == PracticeMode.free;

    // 絵は大きいほど分かりやすいが、書き取り面を押しつぶしては本末転倒。
    // 広い画面でだけ大きくする。
    final picture = wide ? 132.0 : 76.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.picture != null) ...[
          SizedBox(
            width: picture,
            height: picture,
            child: FittedBox(child: widget.picture),
          ),
          const SizedBox(width: 12),
        ],
        if (!widget.isSingle)
          Flexible(child: _buildStepBoxes(chars, hides, scheme)),
      ],
    );
  }

  Widget _buildStepBoxes(List<String> chars, bool hides, ColorScheme scheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final (index, char) in chars.indexed)
          () {
            final here = index == _index;
            // 出しておく字は、書く字と同じ枠にしない。書くところが
            // どれなのかが、ひと目で分かるようにする。
            final given = widget.given.contains(index);
            // 何も見ずに書くモードでも、出しておく字は伏せない。
            // 書かせない字を隠しても、手がかりが減るだけ。
            final masked = hides && !given && index >= _index;

            return Container(
              width: 44,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: here
                    ? scheme.primaryContainer
                    : given
                    ? const Color(0xfff2efe8)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: here
                      ? scheme.primary
                      : given
                      ? const Color(0xffece7dc)
                      : const Color(0xffe4dfd4),
                  width: 2,
                ),
              ),
              child: Text(
                masked ? '？' : char,
                style: TextStyle(
                  fontSize: 28,
                  height: 1,
                  color: given
                      ? const Color(0xff9c948a)
                      : index <= _index
                      ? const Color(0xff6f665c)
                      : const Color(0xffbdb4a6),
                ),
              ),
            );
          }(),
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
    final order = _strokeOrder;
    if (order == null) {
      // 書き順を持たない字は、システムのフォントで見せるほかない。
      return Center(
        child: Text(
          _char,
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
                    //
                    // 1 画引くごとに、その画の下敷きを消す。残しておくと、
                    // 自分の線とずれたときに はみ出した下敷きを塗りつぶそう
                    // とする。次に引く画だけが残るようにする。
                    //
                    // 消さない設定の人には、書き終えるまで丸ごと残す
                    // （SPEC 7.1）。線を追うだけで手一杯の子は、消えると
                    // 引く先を見失う。
                    if (widget.mode == PracticeMode.trace &&
                        _strokeOrder != null)
                      AnimatedBuilder(
                        animation: _ink,
                        builder: (context, _) => StrokeOrderView(
                          order: _strokeOrder!,
                          progress: kAlwaysCompleteAnimation,
                          // 上から子供が書く。下敷きは自分の線より弱くする。
                          faded: true,
                          from: widget.traceErases ? _ink.strokes.length : 0,
                          erased: widget.traceErases ? _erasedByPen : 0,
                        ),
                      ),
                    // 「できた！」を押したあとは書けない。押したあとに
                    // 足した線は、記録に入らないまま画面にだけ残ってしまう。
                    IgnorePointer(
                      ignoring: _busy || _glyph != null,
                      child: InkCanvas(controller: _ink),
                    ),
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
        // 語を書いているときは、書けた字を見せたら自分で次へ進む。
        // 押すものが出ては消えると、押しに行った指が空振りする。
        if (_glyph != null && !widget.isSingle) {
          return const SizedBox(height: 64);
        }
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
                onPressed: () => Navigator.of(context).pop(
                  WritingResult.written([?_savedId]),
                ),
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
