import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../kanjivg/stroke_order.dart';
import '../model/char_set.dart';
import '../model/sample.dart';
import '../model/word.dart';
import '../practice/question_picker.dart';
import '../store/passcode.dart';
import '../store/recipe_store.dart';
import '../store/sample_store.dart';
import '../store/session.dart';
import '../store/word_book_store.dart';
import 'about.dart';
import 'admin_screen.dart';
import 'char_set_screen.dart';
import 'passcode_gate.dart';
import 'practice_session.dart';
import 'user_picker.dart';
import 'word_screen.dart';

/// 文字種の一覧。アプリの入口。
///
/// 子供にとっては「どこまで集めたか」の画面、親にとってはフォントの出口になる。
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.session,
    required this.locks,
    required this.speaker,
    required this.strokeOrders,
  });

  final Session session;
  final Locks locks;
  final Speaker speaker;
  final StrokeOrderLibrary strokeOrders;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  Session get session => widget.session;

  /// 3 つの練習モードのどれで書くか。書く前に選ばせる（SPEC 7.1）。
  ///
  /// 人ごとに覚えている（SPEC 4.4）。なぞりから始めた子と、もう何も見ずに
  /// 書ける子とでは始める場所が違う。
  PracticeMode get _mode => session.current.practiceMode;
  SampleStore get store => session.samples;
  RecipeStore get recipes => session.recipes;
  Locks get locks => widget.locks;
  WordBookStore get books => session.books;
  Speaker get speaker => widget.speaker;
  StrokeOrderLibrary get strokeOrders => widget.strokeOrders;

  @override
  Widget build(BuildContext context) {
    // 画面ぜんぶを包む。人が増えたときに出る切り替えボタンは AppBar にあり、
    // 本文だけを包むと、人を足しても現れないままになる。
    return AnimatedBuilder(
      animation: Listenable.merge([store, session, books, session.attempts]),
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xfffaf7f0),
        title: const Text('あそんでフォント'),
        actions: [
          CurrentUserButton(session: session, lock: locks.switching),
          // 練習モードはヘッダの印から選ぶ。本文の場所は書く入口に譲る。
          _ModeMenu(mode: _mode, onChanged: _chooseMode),
          IconButton(
            iconSize: 28,
            icon: const Icon(Icons.tune),
            tooltip: 'おうちの人へ',
            onPressed: () => _openAdmin(context),
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 語が 1 つも無ければ、おまかせも出しようがない（SPEC 7.3）。
            if (_wordCount > 0) ...[
              _PracticeCard(onTap: () => _practice(context)),
              _WordCard(
                total: _wordCount,
                done: _wordsDone,
                onTap: () => _openWords(context),
              ),
            ],
            for (final charSet in session.current.visibleCharSets)
              _CharSetCard(
                charSet: charSet,
                store: store,
                onTap: () => _openCharSet(context, charSet),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAdmin(BuildContext context) async {
    // パスコードが掛かっていなければ、そのまま通る（既定は無効）。
    if (!await unlock(context, locks.admin)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            AdminScreen(session: session, locks: locks),
      ),
    );
  }

  /// おまかせで書く。まだ集めていない字と苦手な字が出やすい（SPEC 7.3）。
  Future<void> _practice(BuildContext context) => practiceSession(
    context,
    session: session,
    mode: _mode,
    speaker: speaker,
    strokeOrders: strokeOrders,
  );

  /// いま書ける語の数。集める文字種に無い字を含む語は数えない（SPEC 7.4）。
  int get _wordCount => _writableWords.length;

  /// そのうち、最後まで書けたことのある語の数。
  int get _wordsDone => _writableWords
      .where((word) => session.attempts.countOf(word.text) > 0)
      .length;

  List<Word> get _writableWords =>
      writableWords(session.current, books.all);

  void _openWords(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WordScreen(
          session: session,
          speaker: speaker,
          strokeOrders: strokeOrders,
          mode: _mode,
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
          traceErases: session.current.traceErases,
        ),
      ),
    );
  }

  Future<void> _chooseMode(PracticeMode mode) async {
    // 覚えておく。開くたびに選び直させると、字を書くまでの手数が増える。
    await session.users.save(session.current.copyWith(practiceMode: mode));
    // 字が読めなくても、どちらを選んだか分かるようにする（SPEC 2）。
    await speaker.speak(switch (mode) {
      PracticeMode.copy => 'おてほんを みて かこう',
      PracticeMode.free => 'じぶんで かいてみよう',
      PracticeMode.trace => 'なぞって かこう',
    });
  }

  Future<void> _clearAll(BuildContext context) async {
    if (!await confirmClearAll(context)) return;
    await store.clear();
    // 字が無いのに「書けた」印だけ残ると、一覧が食い違う。
    await session.attempts.clear();
    if (context.mounted) Navigator.of(context).pop();
  }

}

/// 練習モードの切り替え（SPEC 7.1）。ヘッダの印から選ぶ。
///
/// なぞる → お手本を見る → 何も見ない、と難しくなる並びにしてある。
/// 「お手本なしで書けた」は子供にとって手応えのある目標で、親にとっては
/// より素の字が集まる手段になる。
///
/// なぞり書きだけは、字形をなぞっただけなのでフォントの素材に採らない（SPEC 7.1）。
///
/// **いま選んでいるモードの印を出す。** 開かなくても、どれで書くことになって
/// いるかが分かる。選んだものは声でも言うので（[_CollectionScreenState._chooseMode]）、
/// 読めない子にも伝わる（SPEC 2）。
class _ModeMenu extends StatelessWidget {
  const _ModeMenu({required this.mode, required this.onChanged});

  final PracticeMode mode;
  final ValueChanged<PracticeMode> onChanged;

  /// 難しくなる順に並べる。印は 7.1 の 3 段階にそのまま対応する。
  static const _modes = {
    PracticeMode.trace: (Icons.gesture, 'なぞる'),
    PracticeMode.copy: (Icons.visibility, 'おてほん'),
    PracticeMode.free: (Icons.volume_up, 'じぶんで'),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<PracticeMode>(
      iconSize: 28,
      tooltip: 'かきかた',
      icon: Icon(_modes[mode]!.$1),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final MapEntry(key: value, value: (icon, label)) in _modes.entries)
          PopupMenuItem(
            value: value,
            // タップターゲットは 64dp 以上（SPEC 9）。
            height: 64,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: value == mode ? scheme.primary : null,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: value == mode
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: value == mode ? scheme.primary : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// おまかせで書く入口（SPEC 7.3）。
///
/// いちばん上に大きく置く。何を書くか決められない子が、迷わず始められる
/// ところがこの画面には要る。
class _PracticeCard extends StatelessWidget {
  const _PracticeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.primary, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 40, color: scheme.primary),
                const SizedBox(width: 16),
                // 説明は置かない。読める子だけに向けた文になるし、
                // 何が出るかは押せば分かる（SPEC 2）。
                Expanded(
                  child: Text(
                    'おまかせで かく',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 単語で練習する入口（SPEC 7.4）。
///
/// 文字種の束と並べて置く。字を 1 つずつ埋めるのと、語をまるごと書くのとは
/// どちらも「書く」入口で、子供にとっては同じ高さにある。
class _WordCard extends StatelessWidget {
  const _WordCard({
    required this.total,
    required this.done,
    required this.onTap,
  });

  final int total;
  final int done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: done / total,
                        strokeWidth: 6,
                        backgroundColor: const Color(0xffe4dfd4),
                      ),
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 24,
                        color: done == 0
                            ? const Color(0xff9c948a)
                            : scheme.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'ことば',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Text(
                  '$done / $total',
                  style: const TextStyle(color: Color(0xff9c948a)),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 32),
              ],
            ),
          ),
        ),
      ),
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
