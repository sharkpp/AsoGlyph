/// 練習に出す語（SPEC 7.4）。
///
/// 単語帳は「練習用の文字列の供給源」であり、意味の学習が目的ではない。
class Word {
  const Word({required this.text, required this.reading, this.tags = const []});

  /// 書かせる文字列。
  final String text;

  /// 読み。子供が読めない語を出さないために必須とする（SPEC 7.4）。
  final String reading;

  final List<String> tags;

  /// 1 字ずつに分ける。書く順はこの並び。
  List<String> get chars => text.characters;

  /// この語を書くのに要る字が、どれも [collectable] に含まれるか。
  ///
  /// 集める文字種に無い字を含む語は出題候補から外す（SPEC 7.4）。
  /// 書けない字が 1 つでも混じると、その語は最後まで書けない。
  bool isWritable(Set<String> collectable) =>
      chars.every(collectable.contains);
}

/// 語のまとまり。同梱のものと、親が取り込んだものがある（SPEC 7.4）。
class WordBook {
  const WordBook({required this.id, required this.name, required this.words});

  final String id;
  final String name;
  final List<Word> words;
}

/// 1 回の単語トライアル（SPEC 4.2）。
///
/// 「単語単位で履歴を持つ」という要求の実体。書いた記録そのものは [Sample] に
/// 残るので、ここは「どの語を、どの記録の並びで書き終えたか」だけを持つ。
class WordAttempt {
  const WordAttempt({
    required this.id,
    required this.word,
    required this.sampleIds,
    required this.finishedAt,
  });

  final String id;

  /// 書いた語。単語帳は入れ替わるので、id ではなく文字列で持つ。
  /// 取り込んだ単語帳を親が消しても、書いた履歴は残る（SPEC 4.1）。
  final String word;

  /// 書いた順の記録 id。
  final List<String> sampleIds;

  final DateTime finishedAt;
}

extension on String {
  /// 書記素ではなく符号位置で割る。対象は かな・数字・漢字で、
  /// 結合文字は出てこない（SPEC 5）。
  List<String> get characters => runes.map(String.fromCharCode).toList();
}
