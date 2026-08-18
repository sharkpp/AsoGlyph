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

  /// かっこで囲んだところは書かせない（SPEC 7.4）。
  ///
  /// 「[ウルトラマン]オメガ」は、ウルトラマン を出しておいて オメガ だけ
  /// 書かせる。長い名前ぜんぶを書かせると、1 セッションで終わらないし、
  /// 4 歳には長すぎて何を書いているのか分からなくなる。
  ///
  /// かっこが閉じていなければ、そこから先ぜんぶを書かせない扱いにする。
  /// 取り込んだ単語帳で 1 か所書き損じただけで、読み込みそのものを
  /// 断るほどのことではない。
  List<WordSegment> get segments {
    final out = <WordSegment>[];
    final buffer = StringBuffer();
    var given = false;

    void flush() {
      if (buffer.isEmpty) return;
      out.add(WordSegment(buffer.toString(), given: given));
      buffer.clear();
    }

    for (final char in text.characters) {
      if (char == '[' && !given) {
        flush();
        given = true;
      } else if (char == ']' && given) {
        flush();
        given = false;
      } else {
        buffer.write(char);
      }
    }
    flush();
    return out;
  }

  /// 人に見せる形。かっこは外す。
  String get display => [for (final part in segments) part.text].join();

  /// 出す並び。書かせない字も入る。
  List<String> get displayChars => display.characters;

  /// [displayChars] のうち、書かせない字の位置。
  Set<int> get givenIndices {
    final out = <int>{};
    var at = 0;
    for (final part in segments) {
      final length = part.text.characters.length;
      if (part.given) {
        for (var i = 0; i < length; i++) {
          out.add(at + i);
        }
      }
      at += length;
    }
    return out;
  }

  /// 書かせる字だけ。書く順はこの並び。
  ///
  /// 充足率も出題の重みも、この字だけで決まる。出しておく字は書かないので、
  /// 集まった字にも数えない。
  List<String> get chars => [
    for (final part in segments)
      if (!part.given) ...part.text.characters,
  ];

  /// この語を書くのに要る字が、どれも [collectable] に含まれるか。
  ///
  /// 集める文字種に無い字を含む語は出題候補から外す（SPEC 7.4）。
  /// 書けない字が 1 つでも混じると、その語は最後まで書けない。
  ///
  /// かっこの中は見ない。「[ウルトラマン]オメガ」はカタカナを集めていれば
  /// 書けるし、「[東京]スカイツリー」は漢字を集めていなくても書ける。
  bool isWritable(Set<String> collectable) =>
      chars.isNotEmpty && chars.every(collectable.contains);
}

/// 語の一部分。書かせるところと、出しておくところに分かれる。
class WordSegment {
  const WordSegment(this.text, {required this.given});

  final String text;

  /// 出しておくだけで、書かせないところ。
  final bool given;
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
