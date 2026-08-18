import 'package:flutter/material.dart';

import '../audio/speaker.dart';
import '../kanjivg/stroke_order.dart';
import '../model/sample.dart';
import '../practice/question_picker.dart';
import '../store/session.dart';
import 'writing_screen.dart';

/// ひとまとまりで書く字数。
///
/// 1 セッションは 3〜5 分（3〜4 歳）を目安に区切る（SPEC 7.1）。1 字はおよそ
/// 30 秒なので 5 字。終わりが見えていることのほうが、字数より効く。
const _sessionLength = 5;

/// おまかせで書く（SPEC 7.3）。
///
/// 何を書くかを選ばせない。46 字の一覧から自分で選べる子ばかりではないし、
/// 選ばせると書ける字ばかりを選ぶ。まだ集めていない字と苦手な字が
/// 出やすいように重み付けして抽選する。
Future<void> practiceSession(
  BuildContext context, {
  required Session session,
  required PracticeMode mode,
  required Speaker speaker,
  required StrokeOrderLibrary strokeOrders,
}) async {
  final chars = pickQuestions(
    session.current,
    session.samples,
    count: _sessionLength,
  );
  if (chars.isEmpty) return;

  for (final (index, char) in chars.indexed) {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => WritingScreen(
          char: char,
          mode: mode,
          store: session.samples,
          speaker: speaker,
          strokeOrder: strokeOrders[char],
          steps: WritingSteps(chars: chars, index: index),
        ),
      ),
    );
    // 書かずに閉じた。やめたところで打ち切る。
    if (id == null) return;
  }

  await speaker.speak('ぜんぶ かけたね！');
}
