import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../kanjivg/stroke_order.dart';
import '../model/sample.dart';
import '../model/word.dart';
import '../practice/question_picker.dart';
import '../store/session.dart';
import 'word_image_view.dart';
import 'writing_screen.dart';

/// ひとまとまりで書く字数の目安。
///
/// 1 セッションは 3〜5 分（3〜4 歳）を目安に区切る（SPEC 7.1）。1 字はおよそ
/// 30 秒。語の長さは まちまちなので、語数ではなく字数で区切る。
const _sessionChars = 5;

/// おまかせで書く（SPEC 7.3）。
///
/// 何を書くかを選ばせない。46 字の一覧から自分で選べる子ばかりではないし、
/// 選ばせると書ける字ばかりを選ぶ。まだ集めていない字と苦手な字を多く含む語が
/// 出やすいように重み付けして抽選する。
///
/// **出すのは語**。1 字ずつ出すより、書いた字がことばになるほうが手応えがある。
Future<void> practiceSession(
  BuildContext context, {
  required Session session,
  required PracticeMode mode,
  required Speaker speaker,
  required StrokeOrderLibrary strokeOrders,
}) async {
  final words = pickWords(
    session.current,
    session.samples,
    session.books.all,
    chars: _sessionChars,
  );
  if (words.isEmpty) return;

  for (final word in words) {
    final done = await practiceWord(
      context,
      word: word,
      mode: mode,
      session: session,
      speaker: speaker,
      strokeOrders: strokeOrders,
      praise: false,
    );
    // 途中でやめた。続きは出さない。
    if (!done) return;
  }

  await speaker.speak('ぜんぶ かけたね！');
}

/// 語を 1 字ずつ書かせる（SPEC 7.4）。
///
/// 最後まで書けたら単語トライアルとして残す（SPEC 4.2）。途中でやめたときは
/// 残さない。書いた字そのものは 1 字ずつ記録に入っているので、何も失われない。
///
/// 最後まで書けたかを返す。おまかせが、続きを出すかの判断に使う。
Future<bool> practiceWord(
  BuildContext context, {
  required Word word,
  required PracticeMode mode,
  required Session session,
  required Speaker speaker,
  required StrokeOrderLibrary strokeOrders,
  bool praise = true,
}) async {
  final sampleIds = <String>[];

  for (final (index, char) in word.chars.indexed) {
    // 続けて押されて画面ごと閉じられていたら、そこで終わる。
    if (!context.mounted) return false;
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => WritingScreen(
          char: char,
          mode: mode,
          store: session.samples,
          speaker: speaker,
          strokeOrder: strokeOrders[char],
          steps: WritingSteps(
            chars: word.chars,
            index: index,
            reading: word.reading,
            picture: word.image == null
                ? null
                : WordImageView(
                    image: word.image!,
                    books: session.books,
                    size: 56,
                  ),
          ),
        ),
      ),
    );
    // 書かずに閉じた。やめたところで打ち切る。
    if (id == null) return false;
    sampleIds.add(id);
  }

  await session.attempts.finish(word: word.text, sampleIds: sampleIds);
  // おまかせは語をまたいで続くので、1 語ごとにほめると声が渋滞する。
  if (praise) await speaker.speak('${word.reading}、かけたね！');
  return true;
}
