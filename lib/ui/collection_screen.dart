import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../export/collected_font.dart';
import '../export/font_export.dart';
import '../font/font_builder.dart';
import '../kanjivg/stroke_order.dart';
import '../model/char_set.dart';
import '../model/font_recipe.dart';
import '../model/sample.dart';
import '../store/passcode.dart';
import '../store/recipe_store.dart';
import '../store/sample_store.dart';
import '../store/session.dart';
import 'about.dart';
import 'admin_screen.dart';
import 'char_set_screen.dart';
import 'export_sheet.dart';
import 'passcode_gate.dart';
import 'user_picker.dart';

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
  /// 3 つの練習モードのどれで書くか。書く前に選ばせる（SPEC 7.1）。
  ///
  /// 既定はお手本あり。いちばん多くの子が始められるところに置く。
  var _mode = PracticeMode.copy;

  Session get session => widget.session;
  SampleStore get store => session.samples;
  RecipeStore get recipes => session.recipes;
  Locks get locks => widget.locks;
  Speaker get speaker => widget.speaker;
  StrokeOrderLibrary get strokeOrders => widget.strokeOrders;

  @override
  Widget build(BuildContext context) {
    // 画面ぜんぶを包む。人が増えたときに出る切り替えボタンは AppBar にあり、
    // 本文だけを包むと、人を足しても現れないままになる。
    return AnimatedBuilder(
      animation: Listenable.merge([store, session]),
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
          IconButton(
            iconSize: 28,
            icon: const Icon(Icons.ios_share),
            tooltip: 'フォントをつくる',
            onPressed: () => _export(context),
          ),
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
            _ModeChoice(mode: _mode, onChanged: _chooseMode),
            const SizedBox(height: 24),
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

    // 今の字を全部入れる既定の版。文字種を選んだり時点を指定したりする
    // 版づくりは管理画面（SPEC 7.6）で、ここは子供向け画面の手早い出口。
    final now = DateTime.now();
    final recipe = FontRecipe.latest(
      id: 'quick',
      name: 'いまの字',
      createdAt: now,
      fontMeta: FontMetadata(familyName: 'AsoGlyph', created: now),
    );
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

    await shareFont(
      bytes: bytes,
      fileName:
          '${sanitizeFileName(recipe.fontMeta.familyName)}.${choice.format.name}',
      format: choice.format,
      text: 'あそんでフォントでつくったフォント',
    );
  }
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
