"""語の字づかい（SPEC 7.4）。集める道具と置き換えの道具で分け合う。

ここに置いてあるのは 3 つ。

- **読み** … `lib/word/reading.dart` の `toReading` と同じ規則。ずれると、
  取り込んだ単語帳とここで作った単語帳とで読み上げが変わる
- **置き換えの表** … 漢字を、かなに開くための表（`深海怪獣 = しんかいかいじゅう`）。
  集めた名前は漢字のまま持ち、書かせる形に直すのはこの表だけが決める
- **YAML のスカラ** … `lib/word/word_book_export.dart` の `_scalar` と同じ規則
"""

import re
import unicodedata

# 読みにそのまま使える字。ひらがな・カタカナ・長音符・空白。
# 「、。！？「」」は子供が書ける字（SPEC 5）なので、置き換えの表には載せない。
_KEEP = set("、。！？「」 　ー")

# 出しておく字の印（SPEC 7.4.0）。名前の一部ではないので、表には載せない。
_BRACKETS = set("[]")


def to_reading(text):
    """読みに使える字だけを残し、カタカナはひらがなに直す。

    `lib/word/reading.dart` の `toReading` と同じ。長音符「ー」と空白は残す
    （落とすと「あーく」が「あく」になり、読み上げが別の語になる）。
    """
    out = []
    for char in text:
        code = ord(char)
        if 0x30A1 <= code <= 0x30F6:  # カタカナ → ひらがな。並びが 0x60 ずれている
            out.append(chr(code - 0x60))
        elif 0x3041 <= code <= 0x3096:
            out.append(char)
        elif code in (0x30FC, 0x20, 0x3000):
            out.append(char)
    return "".join(out)


def reading_of(text):
    """ことばから読みを起こす。

    かっこ（SPEC 7.4.0）は外す。閉じかっこは空白に替える。「[ねこ]ぱんち」を
    「ねこぱんち」と続けて読むと、出しておく字とこれから書く字の切れ目が
    声から消える。
    """
    plain = text.replace("[", "").replace("]", " ")
    return re.sub(r"[\s　]+", " ", to_reading(plain)).strip()


def yaml_scalar(value):
    """YAML のスカラにする。`lib/word/word_book_export.dart` の `_scalar` と同じ。

    「100」を引用符無しで書くと数として読み戻る。素の語として通らないものは
    必ず引用符でくくる。
    """
    plain = (
        value != ""
        and not re.match(r"^[-+.0-9]", value)
        and not re.search(r"""[:#\[\]{},&*!|>'"%@`\n]""", value)
        and value.strip() == value
        and value.lower() not in {"true", "false", "null", "yes", "no", "on", "off"}
    )
    if plain:
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def yaml_unscalar(value):
    """[yaml_scalar] を戻す。"""
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        body = value[1:-1]
        if value[0] == "'":
            return body.replace("''", "'")
        return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), body)
    return value


# ------------------------------------------------------- 置き換えの表（TOML）


def table_keys(text):
    """ことばのうち、かなに開かないと書けないところを挙げる。

    - 漢字・ラテン・数字は、続いているぶんをひとまとまりにする
      （「深海怪獣」で 1 つ。字ごとに分けると読みが決められない）
    - 出しておく字の印（`[かっこ]`、SPEC 7.4.0）は区切りにする。またいで
      ひとまとまりにすると、「[楽園夢想遺構]柱」が 1 語になる
    - 記号は 1 字ずつ。かっこや「・」は名前の区切りに使われていて、
      前後の語とまとめると同じ語が何度も表に並ぶ（「星人」と「星人・」）
    """
    keys = []
    run = ""
    for char in text.replace("[", " ").replace("]", " ") + "\0":
        if char != "\0" and char not in _KEEP and not _is_kana(char) and not _is_mark(char):
            run += char
            continue
        if run:
            keys.append(run)
            run = ""
        if char != "\0" and _is_mark(char):
            keys.append(char)
    return keys


def _is_kana(char):
    code = ord(char)
    return 0x3041 <= code <= 0x3096 or 0x30A1 <= code <= 0x30F6


def _is_mark(char):
    return (
        char not in _KEEP
        and char not in _BRACKETS
        and unicodedata.category(char)[0] in "PSZC"
    )


def apply_table(text, table):
    """表にある字を、かなに置き換える。

    長いものから当てる。「星人」と「星人二代目」が両方あるとき、短いほうから
    当てると残りの「二代目」が漢字のまま残る。
    """
    if not table:
        return text
    pattern = "|".join(re.escape(key) for key in sorted(table, key=len, reverse=True))
    return re.sub(pattern, lambda m: table[m.group(0)], text)


def load_table(path):
    """置き換えの表を読む。

    TOML の一部だけを読む（`鍵 = 値` の 1 行だけ）。鍵に漢字を書けるよう、
    引用符は省いてよいことにしている。TOML の素の鍵は英数字しか許して
    いないので、`tomllib` では `深海怪獣 = しんかいかいじゅう` が読めない。
    """
    table = {}
    with open(path, encoding="utf-8") as file:
        for number, line in enumerate(file, 1):
            line = _strip_comment(line).strip()
            if not line:
                continue
            if "=" not in line:
                raise ValueError(f"{path}:{number}: 「鍵 = 値」の形で書いてください")
            key, value = line.split("=", 1)
            key = _unquote(key.strip())
            if not key:
                raise ValueError(f"{path}:{number}: 鍵がありません")
            table[key] = _unquote(value.strip())
    return table


def write_table(path, entries, table):
    """置き換えの表を書く。

    [entries] は `(鍵, 見かけた語, 出どころ)` の並び。読みがまだ書かれて
    いないものは**行ごとコメントにする**。空の値は「消す」という指図なので
    （かっこや「・」を落とすのに使う）、書かれていない行と見分けが付かないと、
    書き忘れた語が黙って消える。
    """
    out = [
        "# 名前に出てくる漢字を、かなに開く表（SPEC 7.4）。",
        "#",
        "#   tool/word_book/asodict_rename_words.py <この表> <単語帳ファイル>...",
        "#",
        "# 値を空にすると、その字は消える（かっこや区切りの記号を落とすのに使う）。",
        "# 頭に # の付いている行は、まだ読みが書かれていないもの。読みを書いて # を外す。",
        "",
    ]
    source = None
    for key, example, origin in entries:
        if origin != source:
            out.append(f"# --- {origin} ---" if source is None else f"\n# --- {origin} ---")
            source = origin
        value = table.get(key)
        line = f'"{key}" = "{value if value is not None else ""}"  # {example}'
        out.append(line if value is not None else f"# {line}")

    unused = [key for key in table if key not in {entry[0] for entry in entries}]
    if unused:
        out.append("\n# --- いまの一覧には出てこない ---")
        out += [f'"{key}" = "{table[key]}"' for key in unused]

    with open(path, "w", encoding="utf-8") as file:
        file.write("\n".join(out) + "\n")
    return sum(1 for key, _, _ in entries if key not in table)


def _strip_comment(line):
    quote = None
    for index, char in enumerate(line):
        if quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "#":
            return line[:index]
    return line


def _unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value
