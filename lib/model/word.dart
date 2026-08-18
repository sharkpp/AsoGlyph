/// 練習に出す語（SPEC 7.4）。
///
/// 単語帳は「練習用の文字列の供給源」であり、意味の学習が目的ではない。
class Word {
  const Word({
    required this.text,
    required this.reading,
    this.tags = const [],
    this.image,
  });

  /// 書かせる文字列。
  final String text;

  /// 読み。子供が読めない語を出さないために必須とする（SPEC 7.4）。
  final String reading;

  final List<String> tags;

  /// 絵（SPEC 7.4）。任意。
  ///
  /// 端末に入っている単語帳では画像の id、単語帳ファイルの中ではファイル名。
  /// どちらも `<名前>.png` の形で、拡張子がそのまま形式になる。
  ///
  /// 字が読めない子は、絵でしか語を選べない。読みを声で聞かせるだけでは、
  /// 一覧から選ぶという操作が成り立たない。
  final String? image;

  Word copyWith({String? text, String? reading, String? image}) => Word(
    text: text ?? this.text,
    reading: reading ?? this.reading,
    tags: tags,
    image: image ?? this.image,
  );

  /// 絵を外した語。[copyWith] では null を渡せない。
  Word withoutImage() => Word(text: text, reading: reading, tags: tags);

  /// 1 字ずつに分ける。書く順はこの並び。
  List<String> get chars => text.characters;

  /// この語を書くのに要る字が、どれも [collectable] に含まれるか。
  ///
  /// 集める文字種に無い字を含む語は出題候補から外す（SPEC 7.4）。
  /// 書けない字が 1 つでも混じると、その語は最後まで書けない。
  bool isWritable(Set<String> collectable) =>
      chars.every(collectable.contains);
}

/// 語のまとまり（SPEC 7.4）。
///
/// 「どうぶつ」「たべもの」のように、親がいくつでも作れる。誰にどれを出すかは
/// [User.wordBooks] が持つ。
class WordBook {
  const WordBook({
    required this.id,
    required this.name,
    required this.words,
    this.source,
  });

  final String id;
  final String name;
  final List<Word> words;

  /// どこから来たか。同梱の単語帳だけが持つ（資産のパス）。
  ///
  /// 消したものを入れ直せるようにするためだけに持つ。中身は直せるし、
  /// 直したあともここは変わらない。
  final String? source;

  WordBook copyWith({String? name, List<Word>? words}) => WordBook(
    id: id,
    name: name ?? this.name,
    words: words ?? this.words,
    source: source,
  );

  /// この単語帳に出てくる字。
  Set<String> get chars => {
    for (final word in words) ...word.chars,
  };
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
