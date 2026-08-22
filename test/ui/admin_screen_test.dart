import 'package:asoglyph/ink/stroke.dart';
import 'package:asoglyph/model/char_set.dart';
import 'package:asoglyph/model/font_recipe.dart';
import 'package:asoglyph/model/sample.dart';
import 'package:asoglyph/model/user.dart';
import 'package:asoglyph/model/word.dart';
import 'package:asoglyph/store/passcode.dart';
import 'package:asoglyph/store/recipe_store.dart';
import 'package:asoglyph/store/sample_store.dart';
import 'package:asoglyph/store/session.dart';
import 'package:asoglyph/practice/question_picker.dart';
import 'package:asoglyph/ui/admin_screen.dart';
import 'package:asoglyph/ui/char_set_screen.dart';
import 'package:asoglyph/ui/word_book_section.dart';
import 'package:asoglyph/ui/word_history_section.dart';
import 'package:asoglyph/ui/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_store.dart';
import '../support/writing_actions.dart';

Sample _written(String char, {required DateTime at}) => Sample(
  id: '$char-${at.toIso8601String()}',
  char: char,
  mode: PracticeMode.copy,
  writtenAt: at,
  strokes: [
    Stroke(const [
      InkPoint(x: 300, y: 500, t: 0, pressure: 0),
      InkPoint(x: 700, y: 500, t: 20, pressure: 0),
    ]),
  ],
);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  final spring = DateTime(2026, 4, 1);
  final autumn = DateTime(2026, 10, 1);

  late Session session;
  late SampleStore store;
  late RecipeStore recipes;
  late Locks locks;

  setUp(() async {
    session = await openMemorySession();
    store = session.samples;
    recipes = session.recipes;
    locks = await openMemoryLocks();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminScreen(session: session, locks: locks),
      ),
    );
  }

  testWidgets('版がまだ無いことを伝える', (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('まだ版がありません'), findsOneWidget);
  });

  testWidgets('版を作ると一覧に出て、編集画面へ入る', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('作る'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'いちねんせい');
    await tester.runAsync(() async {
      await tester.tap(find.text('決める'));
    });
    await tester.pumpAndSettle();

    // 作ったらそのまま中身を決めさせる。
    expect(find.byType(RecipeEditor), findsOneWidget);
    expect(recipes.all.single.name, 'いちねんせい');
  });

  testWidgets('版は何字入るかを見せる', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await store.add(_written('い', at: autumn));
      await recipes.create('ぜんぶ');
    });
    await pumpScreen(tester);

    expect(
      find.textContaining('2 / ${totalOf(recipes.all.single)} 字'),
      findsOneWidget,
    );
  });

  testWidgets('版の中身を 1 行で言い表す', (tester) async {
    final recipe = await tester.runAsync(() => recipes.create('あの頃'));
    await tester.runAsync(
      () => recipes.save(
        recipe!.copyWith(
          charSets: {CharSet.hiragana},
          base: AtPolicy(spring),
        ),
      ),
    );
    await pumpScreen(tester);

    // 一覧の 1 行で、出す文字種といつの字かが分かる。
    expect(
      find.text('0 / ${CharSet.hiragana.chars.length} 字 ・ ひらがな ・ 2026年4月1日 までの字'),
      findsOneWidget,
    );
  });

  testWidgets('版を消しても集めた字は消えない', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await recipes.create('消す版');
    });
    await pumpScreen(tester);

    await tester.tap(find.byType(PopupMenuButton<void Function()>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('消す'));
    await tester.pumpAndSettle();

    // 版は導出ビューでしかない。誤解されないよう画面でも断っている。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('集めた字は消えません'),
      ),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '消す'));
    });
    await tester.pumpAndSettle();

    expect(recipes.all, isEmpty);
    expect(store.collectedChars(includeTraced: false), ['あ']);
  });

  testWidgets('集まり具合を文字種ごとに見せる', (tester) async {
    await pumpScreen(tester);

    for (final charSet in CharSet.values) {
      expect(
        find.descendant(
          of: find.byType(CharSetRing),
          matching: find.text(charSet.label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('集める文字種を外すと、集まり具合からも消える', (tester) async {
    await pumpScreen(tester);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(CheckboxListTile, 'カタカナ'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    // 子供の画面に出さない文字種は、集まり具合にも並べない。
    expect(
      find.descendant(
        of: find.byType(CharSetRing),
        matching: find.text('カタカナ'),
      ),
      findsNothing,
    );
    expect(session.current.collecting, isNot(contains(CharSet.katakana)));
  });

  testWidgets('集める文字種を全部は外せない', (tester) async {
    await pumpScreen(tester);

    for (final label in ['カタカナ', 'ひらがな', 'すうじ']) {
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(CheckboxListTile, label));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
    }

    // 全部外すと子供の画面が空になり、何をする画面か分からなくなる。
    expect(session.current.visibleCharSets, hasLength(1));
  });

  testWidgets('控えを書き出せなかったときは、そう言う', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('控えを書き出す'), 200);

    // 共有シートはテストでは出せない（プラグインが無い）。そこで黙ると、
    // 押しても何も起きない画面になる。何が起きたかを必ず出す。
    await tester.runAsync(() => tester.tap(find.text('控えを書き出す')));
    await waitFor(
      tester,
      () => find.textContaining('控えを書き出せませんでした').evaluate().isNotEmpty,
    );

    expect(find.textContaining('控えを書き出せませんでした'), findsOneWidget);
  });

  testWidgets('版を開かずにフォントを出力できる', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('あ', at: spring));
      await recipes.create('いまの字');
    });
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('いまの字'), 200);

    await tester.tap(find.byType(PopupMenuButton<void Function()>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('フォントを出力'));
    await tester.pumpAndSettle();

    // 中身を決め終えた版を、出すためだけに開かせない（SPEC 7.6）。
    expect(find.text('TTF'), findsOneWidget);
    expect(find.text('OTF'), findsOneWidget);
  });

  testWidgets('なぞり書きの下敷きを消すかを、人ごとに切れる', (tester) async {
    await pumpScreen(tester);

    // 既定は消す。残しておくと、自分の線とずれたときに はみ出した下敷きを
    // 塗りつぶそうとする（SPEC 7.1）。
    expect(session.current.traceErases, isTrue);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(SwitchListTile, 'なぞったところを消す'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(session.current.traceErases, isFalse);

    // 開き直しても残る。
    final reopened = await tester.runAsync(() => openMemorySession(session.db));
    expect(reopened!.current.traceErases, isFalse);
  });

  testWidgets('下敷きの設定は、その人のぶんだけ変わる', (tester) async {
    await pumpScreen(tester);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(SwitchListTile, 'なぞったところを消す'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    await tester.runAsync(
      () => session.addUser(name: 'あに', avatar: Avatar.bird),
    );
    await tester.pumpAndSettle();
    expect(session.current.traceErases, isTrue, reason: '別の人は既定');
  });

  testWidgets('単語帳を、この人に出すかどうかで選べる', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('カタカナのことば'), 200);

    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(
          of: find.byType(WordBookSection),
          matching: find.widgetWithText(CheckboxListTile, 'カタカナのことば'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    // 単語帳そのものは、みんなで使う 1 つ。分けるのは誰に出すかだけ。
    expect(session.current.uses(katakanaBookId(session)), isFalse);
    expect(
      session.books.all.map((book) => book.name),
      contains('カタカナのことば'),
      reason: '単語帳は消えていない',
    );
  });

  testWidgets('出す単語帳を全部は外せない', (tester) async {
    // 出すのを 1 冊だけにしてから、それを外そうとする。手元に置いた辞書の
    // 数や名前で結果が変わらないようにする。
    final only = session.books.all.first;
    await tester.runAsync(
      () => session.users.save(session.current.copyWith(wordBooks: {only.id})),
    );
    await pumpScreen(tester);

    final tile = find.descendant(
      of: find.byType(WordBookSection),
      matching: find.widgetWithText(CheckboxListTile, only.name),
    );
    await tester.scrollUntilVisible(tile, 200);
    await tester.runAsync(() => tester.tap(tile));
    await tester.pump();

    // 全部外すと、おまかせも ことばも子供の画面から消える。
    expect(session.current.wordBooks, {only.id});
  });

  testWidgets('単語帳の一覧に、作った人と概要を出す', (tester) async {
    await tester.runAsync(
      () => session.books.add(
        const WordBook(
          id: '',
          name: 'うちのことば',
          words: [Word(text: 'ぱぱ', reading: 'ぱぱ')],
          author: 'おかあさん',
          description: '3 歳の下の子向け',
        ),
      ),
    );
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('うちのことば'), 200);

    // 単語帳はいくつでも作れて人にも渡せる。名前だけでは見分けが付かない。
    expect(find.text('1 語 ・ おかあさん'), findsOneWidget);
    expect(find.text('3 歳の下の子向け'), findsOneWidget);
  });

  testWidgets('URL から取り込める。読めない URL はそう言って断る', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(
      find.text('URL から取り込む'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('URL から取り込む'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'URL'), findsOneWidget);

    // http:// も https:// も無い URL は、取りに行く前に断る。
    await tester.enterText(find.byType(TextField), 'example.com/どうぶつ.yaml');
    await tester.tap(find.widgetWithText(FilledButton, '取り込む'));
    await tester.pumpAndSettle();

    // 何が悪いのかを言う。直せない指摘は、直しようがないのと同じ。
    expect(find.textContaining('http:// か https:// で'), findsOneWidget);
    expect(session.books.all.where((book) => !book.isBundled), isEmpty);
  });

  testWidgets('語に出てこない字を数えて見せる', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('ことばに出てこない字'), 200);

    // おまかせは語で出すので、ここに挙がった字はその導線では出てこない。
    final missing = charsMissingFromWords(session.current, session.books.all);
    expect(missing, isNotEmpty, reason: 'はじめの単語帳では全部は埋まらない');
    expect(find.textContaining('${missing.length} 字'), findsOneWidget);
  });

  testWidgets('単語帳を作って、ことばを足せる', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('単語帳を作る'), 200);

    await tester.tap(find.text('単語帳を作る'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'どうぶつ');
    await tester.runAsync(() async {
      await tester.tap(find.text('決める'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    // 作ったらそのまま語を足せる。空の単語帳だけ残っても使えない。
    expect(find.textContaining('まだ ことばがありません'), findsOneWidget);

    await tester.tap(find.text('ことばを足す'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'ことば'), 'ぱんだ');
    await tester.enterText(find.widgetWithText(TextField, 'よみ'), 'パンダ');
    await tester.runAsync(() async {
      await tester.tap(find.text('決める'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    final book = session.books.all.last;
    expect(book.name, 'どうぶつ');
    expect(book.words.single.text, 'ぱんだ');
    // 読みはひらがなに揃える。打っている手元で直る（SPEC 7.4）。
    expect(book.words.single.reading, 'ぱんだ');
  });

  testWidgets('書いたことばの記録を、語ごとに消せる', (tester) async {
    await tester.runAsync(() async {
      await store.add(_written('ね', at: spring));
      await session.attempts.finish(word: 'ねこ', sampleIds: ['a']);
      await session.attempts.finish(word: 'いぬ', sampleIds: ['b']);
    });
    await pumpScreen(tester);
    // 消す行そのものを出す。新しい順に並ぶので「ねこ」は「いぬ」のうしろ。
    // 記録の一覧は中で送れる（高さを止めてある）ので、送るのは外側と言う。
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'ねこ'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.runAsync(
      () => tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'ねこ'),
          matching: find.byIcon(Icons.close),
        ),
      ),
    );
    await waitFor(tester, () => session.attempts.countOf('ねこ') == 0);

    // 消えるのは「書けた」という印だけ。書いた字は消えない（SPEC 4.1）。
    expect(session.attempts.countOf('ねこ'), 0);
    expect(session.attempts.countOf('いぬ'), 1);
    expect(store.collectedChars(includeTraced: false), {'ね'});
  });

  testWidgets('書いたことばの記録を、まとめて消せる', (tester) async {
    await tester.runAsync(
      () => session.attempts.finish(word: 'ねこ', sampleIds: ['a']),
    );
    await pumpScreen(tester);
    await tester.scrollUntilVisible(
      find.text('ぜんぶ消す'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('ぜんぶ消す'));
    await tester.pumpAndSettle();
    expect(find.textContaining('集めた字も版も消えません'), findsOneWidget);

    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, '消す')),
    );
    await waitFor(tester, () => session.attempts.all.isEmpty);

    expect(session.attempts.all, isEmpty);
    expect(find.textContaining('まだ、ことばを最後まで書いた記録はありません'),
        findsOneWidget);
  });

  testWidgets('書いたことばの記録は、高さが止まって中で送れる', (tester) async {
    // 書けた語は増え続ける。伸びるままだと、この 1 節だけで画面が埋まる。
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await session.attempts.finish(word: 'ねこ$i', sampleIds: ['s$i']);
      }
    });
    await pumpScreen(tester);
    await tester.scrollUntilVisible(
      find.text('ぜんぶ消す'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    // 記録の一覧が、おうちの人の画面とは別に送れる。
    final inner = find.descendant(
      of: find.byType(WordHistorySection),
      matching: find.byType(Scrollable),
    );
    expect(inner, findsOneWidget);
    expect(tester.getSize(inner).height, lessThanOrEqualTo(360));

    // 中を送ると、あとの語が出てくる。30 語ぜんぶは枠に入らない。
    expect(find.widgetWithText(ListTile, 'ねこ0'), findsNothing);
    await tester.drag(inner, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'ねこ0'), findsOneWidget);
  });

  testWidgets('ロックは 2 つ別々に掛けられる', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('書く人の切り替えのロック'), 200);

    // 掛け先が違うので、パスコードも別にする（SPEC 7.5 / 7.6）。
    await tester.tap(find.text('書く人の切り替えのロック'));
    await tester.pumpAndSettle();
    expect(find.textContaining('書く人を切り替えるときに聞きます'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4321');
    await tester.runAsync(() async {
      await tester.tap(find.text('決める'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(locks.switching.matches('4321'), isTrue);
    expect(locks.admin.isSet, isFalse, reason: '管理画面のほうは掛かっていない');
  });
}

/// 版の対象字数。テストの期待値を実装と揃えるために使う。
int totalOf(FontRecipe recipe) =>
    recipe.charSets.fold(0, (sum, set) => sum + set.chars.length);

/// カタカナの単語帳の id。同梱の単語帳も id は端末ごとに振り直される。
String katakanaBookId(Session session) =>
    session.books.all.firstWhere((book) => book.name == 'カタカナのことば').id;
