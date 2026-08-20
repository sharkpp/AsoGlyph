import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../kanjivg/stroke_order.dart';
import '../model/sample.dart';
import '../model/word.dart';
import '../practice/question_picker.dart';
import '../store/session.dart';
import 'word_image_view.dart';
import 'writing_screen.dart';

/// ひとまとまりで出す字数。
///
/// 1 字はおよそ 30 秒。語の長さは まちまちなので、語数ではなく字数で区切る。
/// **区切りは終わりではなく、ほめる間隔**（SPEC 7.3）。書き終えたらまた
/// 抽選して続く。抽選をやり直すことで、いま書けた字の重みが下がる。
const _praiseChars = 5;

/// おまかせで書く（SPEC 7.3）。
///
/// 何を書くかを選ばせない。46 字の一覧から自分で選べる子ばかりではないし、
/// 選ばせると書ける字ばかりを選ぶ。まだ集めていない字と苦手な字を多く含む語が
/// 出やすいように重み付けして抽選する。
///
/// **出すのは語**。1 字ずつ出すより、書いた字がことばになるほうが手応えがある。
///
/// **戻るまで語が出続ける。** 何字かで打ち切ると、まだ書きたい子が
/// そのたびに入口を押し直すことになる。やめるのは書く人の側で決める
/// （書き取り画面から戻る）。何字か書けたところでほめて、区切りだけを見せる。
Future<void> practiceSession(
  BuildContext context, {
  required Session session,
  required PracticeMode mode,
  required Speaker speaker,
  required StrokeOrderLibrary strokeOrders,
}) async {
  while (true) {
    // 画面ごと閉じられていたら、そこで終わる。
    if (!context.mounted) return;

    final words = pickWords(
      session.current,
      session.samples,
      session.books.all,
      chars: _praiseChars,
    );
    // 出す語が無ければ、続けようがない。
    if (words.isEmpty) return;

    var written = 0;
    for (final word in words) {
      final outcome = await practiceWord(
        context,
        word: word,
        mode: mode,
        session: session,
        speaker: speaker,
        strokeOrders: strokeOrders,
        praise: false,
        // 出された語が書けない・知らないときに、そこで手が止まる。
        canSkip: true,
      );
      // 閉じた。続きは出さない。
      if (outcome == WordOutcome.quit) return;
      if (outcome == WordOutcome.done) written++;
    }

    // 1 つも書かずに飛ばし続けたときは、ほめない。
    if (written > 0) await speaker.speak('いっぱい かけたね！');
  }
}

/// 語を書き終えたときの結末。
enum WordOutcome {
  /// 最後まで書けた。
  done,

  /// この語はやめて、次の語へ行きたい（SPEC 7.3）。
  skipped,

  /// 画面を閉じた。続きも出さない。
  quit,
}

/// 語を 1 字ずつ書かせる（SPEC 7.4）。
///
/// 最後まで書けたら単語トライアルとして残す（SPEC 4.2）。途中でやめたときは
/// 残さない。書いた字そのものは 1 字ずつ記録に入っているので、何も失われない。
Future<WordOutcome> practiceWord(
  BuildContext context, {
  required Word word,
  required PracticeMode mode,
  required Session session,
  required Speaker speaker,
  required StrokeOrderLibrary strokeOrders,
  bool praise = true,
  bool canSkip = false,
}) async {
  // 続けて押されて画面ごと閉じられていたら、そこで終わる。
  if (!context.mounted) return WordOutcome.quit;

  // 語をまるごと渡す。字ごとに画面を積み替えると、切り替わるたびに画面が
  // 滑って見えるし、読み上げも積み替えのたびに途切れる。
  final result = await Navigator.of(context).push<WritingResult>(
    MaterialPageRoute(
      builder: (context) => WritingScreen(
        chars: word.displayChars,
        given: word.givenIndices,
        reading: word.reading,
        canSkip: canSkip,
        mode: mode,
        // 人ごとの設定（SPEC 7.1）。
        traceErases: session.current.traceErases,
        store: session.samples,
        speaker: speaker,
        strokeOrders: strokeOrders,
        picture: word.image == null
            ? null
            : WordImageView(
                image: word.image!,
                books: session.books,
                size: 96,
              ),
      ),
    ),
  );

  // 書かずに閉じた。
  if (result == null) return WordOutcome.quit;
  // この語はやめる。書いた字はそのまま残る（SPEC 4.1）。
  if (result.skipped) return WordOutcome.skipped;
  // 最後まで書かずに閉じた（途中の字で戻った）。
  if (result.sampleIds.length < word.chars.length) return WordOutcome.quit;

  final sampleIds = result.sampleIds;
  await session.attempts.finish(word: word.text, sampleIds: sampleIds);
  // おまかせは語をまたいで続くので、1 語ごとにほめると声が渋滞する。
  if (praise) await speaker.speak('${word.reading}、かけたね！');
  return WordOutcome.done;
}
