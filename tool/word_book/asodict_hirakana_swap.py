#!/usr/bin/env python3
"""単語帳ファイルのことばを、ひらがな／カタカナで書き替える（SPEC 7.4）。

    python3 tool/word_book/asodict_hirakana_swap.py --swap swap <入力> <出力>
    python3 tool/word_book/asodict_hirakana_swap.py --swap hira <入力> <出力>
    python3 tool/word_book/asodict_hirakana_swap.py --swap kana <入力> <出力>

| `--swap` | |
|---|---|
| `swap` | 交互に切り替える（ひらがな→カタカナ、カタカナ→ひらがな） |
| `hira` | ひらがなに揃える |
| `kana` | カタカナに揃える |

同じ語を、ひらがなを集めている子とカタカナを集めている子の両方に出したいことが
ある（`train_names_hiragana.yaml` と `train_names_katakana.yaml` のような対）。
片方を手で打ち直すと、絵とタグまで打ち直すことになる。

`.asodict` は zip なので（SPEC 7.4.1）、開いて `words.yaml` だけを書き替え、
また閉じる。絵はそのまま入れ直す。**出力は別のファイル**（入力と同じ名前を
渡せば上書きになる）。

## 書き替えるのはことばだけ

**読みには手を入れない。** 読みは声で読み上げるためだけにあり、表記ではない
（SPEC 7.4.2）。ひらがなに揃える決まりなので、ことばの字づかいを変えても
読みは変わらない。「ドクターイエロー」を「どくたーいえろー」に直しても、
読みは元から「どくたーいえろー」のままでよい。

単語帳の名前・作った人・概要も通す。名前には「（ひらがな）」のように、
中身を言いあてた字が入っていることがあり、まとめて直すと意味がずれる。
`[かっこ]`（SPEC 7.4.0）の中は直す——出しておくだけの字も画面に出るので、
そこだけ字づかいが違うと 1 語のなかで見た目が揺れる。

## ひらがなで書けなくなる語は挙げる

ひらがなに「ー」は無い（SPEC 5 のひらがな 80 字。カタカナ 81 字にだけ入って
いる）。「ドクターイエロー」をひらがなに直すと「どくたーいえろー」になり、
ひらがなを集めている子には 1 字も書けない語になる。黙って通すと、単語帳に
入っているのに一度も出てこない語になるので、名前を挙げて知らせる。
"""

import argparse
import os
import re
import sys
import zipfile

from word_text import yaml_scalar, yaml_unscalar

# zip の中の単語帳本体（lib/word/word_book_export.dart の _manifest と同じ）。
MANIFEST = "words.yaml"

_TEXT = re.compile(r"^(\s*-\s*text:\s*)(.*)$")

# ひらがな（ぁ〜ゖ）とカタカナ（ァ〜ヶ）は同じ並びで、0x60 ずれている。
_HIRAGANA = (0x3041, 0x3096)
_KATAKANA = (0x30A1, 0x30F6)
_OFFSET = 0x60

# 繰り返しの印（ゝゞ / ヽヾ）はずれが違うので別に持つ。
_ITERATION = {"ゝ": "ヽ", "ゞ": "ヾ"}
_ITERATION_BACK = {value: key for key, value in _ITERATION.items()}

# カタカナにしか無い字。ひらがなに直すと、そこだけ直せずに残る。
_KATAKANA_ONLY = set("ーヷヸヹヺ")


def _is_hiragana(char):
    return _HIRAGANA[0] <= ord(char) <= _HIRAGANA[1] or char in _ITERATION


def _is_katakana(char):
    return _KATAKANA[0] <= ord(char) <= _KATAKANA[1] or char in _ITERATION_BACK


def _to_katakana(char):
    return _ITERATION.get(char) or chr(ord(char) + _OFFSET)


def _to_hiragana(char):
    return _ITERATION_BACK.get(char) or chr(ord(char) - _OFFSET)


def convert(text, mode):
    """ことばの字づかいを書き替える。

    ひらがな・カタカナ以外の字（漢字・ラテン・「ー」・かっこ・空白）はそのまま
    通す。「ー」はカタカナにしか無い字だが、落とすと「あーく」が「あく」になる。
    """
    out = []
    for char in text:
        if _is_hiragana(char) and mode in ("swap", "kana"):
            out.append(_to_katakana(char))
        elif _is_katakana(char) and mode in ("swap", "hira"):
            out.append(_to_hiragana(char))
        else:
            out.append(char)
    return "".join(out)


def unwritable(text):
    """ひらがなに直しきれずに残った字を挙げる。

    ひらがなが混じっていないうちは挙げない。カタカナのままの語（`kana` で
    揃えたもの）に「ー」があるのは、カタカナ 81 字に入っているので正しい。
    """
    if not any(_is_hiragana(char) for char in text):
        return []
    return sorted({char for char in text if char in _KATAKANA_ONLY})


def rewrite_manifest(manifest, mode):
    """`words.yaml` のことばを書き替える。

    行ごとに見て `text:` だけを差し替える。ほかの行（名前・作った人・読み・
    絵・タグ）と書いてあるコメントはそのまま通す。単語帳を組み直すと、
    こちらが知らない書き方が落ちる。
    """
    out = []
    changed = 0
    left = []
    for line in manifest.splitlines():
        match = _TEXT.match(line)
        if not match:
            out.append(line)
            continue
        before = yaml_unscalar(match.group(2))
        text = convert(before, mode)
        if text != before:
            changed += 1
        remains = unwritable(text)
        if remains:
            left.append((text, remains))
        out.append(match.group(1) + yaml_scalar(text))
    return "\n".join(out) + "\n", changed, left


def rewrite(source, destination, mode):
    """単語帳ファイルを開いて、書き替えて、別の名前で閉じる。"""
    try:
        archive = zipfile.ZipFile(source)
    except zipfile.BadZipFile:
        raise ValueError("単語帳ファイル（.asodict）ではありません") from None
    with archive:
        if MANIFEST not in archive.namelist():
            raise ValueError(f"{MANIFEST} が入っていません")
        entries = [(item, archive.read(item.filename)) for item in archive.infolist()]

    manifest, changed, left = None, 0, []
    for item, data in entries:
        if item.filename == MANIFEST:
            manifest, changed, left = rewrite_manifest(data.decode("utf-8"), mode)

    # 書き上がってから置く。途中で落ちたときに、開けない単語帳が出力の場所に
    # 残らないようにする（入力と同じ名前を渡せば上書きになる）。
    temporary = destination + ".tmp"
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
        for item, data in entries:
            archive.writestr(
                item, manifest.encode("utf-8") if item.filename == MANIFEST else data
            )
    os.replace(temporary, destination)
    return changed, left


def main(argv):
    parser = argparse.ArgumentParser(
        description="単語帳ファイルのことばを、ひらがな／カタカナで書き替える"
    )
    parser.add_argument(
        "--swap",
        required=True,
        choices=("swap", "hira", "kana"),
        help="swap: 交互に切り替え / hira: ひらがなに揃える / kana: カタカナに揃える",
    )
    parser.add_argument("input", help="入力の単語帳ファイル（.asodict）")
    parser.add_argument("output", help="出力の単語帳ファイル（.asodict）")
    options = parser.parse_args(argv)

    try:
        changed, left = rewrite(options.input, options.output, options.swap)
    except Exception as error:
        print(f"{options.input}: {error}", file=sys.stderr)
        return 1

    print(f"{options.output}: {changed} 語 直しました")
    for text, remains in left:
        print(f"  ひらがなに {''.join(remains)} はありません: {text}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
