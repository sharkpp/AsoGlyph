#!/usr/bin/env python3
"""単語帳ファイルの名前を、表にしたがってかなに開く（SPEC 7.4）。

    python3 tool/word_book/asodict_rename_words.py <表.toml> <単語帳ファイル>...

集める道具（m78_character.py）は、載っていた名前を漢字のまま持つ。書かせる形に
直すのはこちらの仕事で、直し方は表 1 つが決める。

    "深海怪獣" = "しんかいかいじゅう"

    [深海怪獣]ピーター  →  [しんかいかいじゅう]ピーター

`.asodict` は zip なので（SPEC 7.4.1）、開いて `words.yaml` だけを書き替え、
また閉じる。**元のファイルに上書きする。** 絵はそのまま入れ直す。

## 読みは書き替えたことばから起こし直す

読みは声で読み上げるためだけにある（SPEC 7.4）。ことばを直したのに読みが元の
ままだと、画面に出ている字と声が食い違う。表を当てたあとのことばから
`lib/word/reading.dart` と同じ規則で起こし直す。

## 値を空にすると消える

かっこや「・」は名前の区切りに使われていて、そのままでは子供が書けない
（SPEC 5 の書ける字に入っていない）。空の値を書けば落とせる。

    "(" = ""
    ")" = ""

## 直しきれなかったところは挙げる

表に無い漢字が残った語は、書ける字でできていないので出題から外れてしまう
（SPEC 7.4.2）。黙って通すと、単語帳に入っているのに一度も出てこない語に
なるので、名前を挙げて知らせる。
"""

import os
import re
import sys
import zipfile

from word_text import apply_table, load_table, reading_of, table_keys, yaml_scalar, yaml_unscalar

# zip の中の単語帳本体（lib/word/word_book_export.dart の _manifest と同じ）。
MANIFEST = "words.yaml"

_TEXT = re.compile(r"^(\s*-\s*text:\s*)(.*)$")
_READING = re.compile(r"^(\s*reading:\s*)(.*)$")


def rename(manifest, table):
    """`words.yaml` のことばと読みを書き替える。

    行ごとに見て、`text:` と `reading:` だけを差し替える。ほかの行（名前・
    作った人・絵・タグ）はそのまま通す。単語帳を組み直すと、こちらが知らない
    書き方が落ちる。
    """
    out = []
    changed = 0
    left = []
    text = None
    for line in manifest.splitlines():
        match = _TEXT.match(line)
        if match:
            before = yaml_unscalar(match.group(2))
            text = apply_table(before, table)
            if text != before:
                changed += 1
            if table_keys(text):
                left.append(text)
            out.append(match.group(1) + yaml_scalar(text))
            continue
        match = _READING.match(line)
        if match and text is not None:
            out.append(match.group(1) + yaml_scalar(reading_of(text)))
            continue
        out.append(line)
    return "\n".join(out) + "\n", changed, left


def rewrite(path, table):
    """単語帳ファイルを開いて、書き替えて、また閉じる。"""
    with zipfile.ZipFile(path) as archive:
        if MANIFEST not in archive.namelist():
            raise ValueError(f"{MANIFEST} が入っていません")
        entries = [(item, archive.read(item.filename)) for item in archive.infolist()]

    manifest, changed, left = None, 0, []
    for item, data in entries:
        if item.filename == MANIFEST:
            manifest, changed, left = rename(data.decode("utf-8"), table)

    # 書き上がってから置き換える。途中で落ちたときに、開けない単語帳が
    # 元のファイルの場所に残らないようにする。
    temporary = path + ".tmp"
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
        for item, data in entries:
            archive.writestr(
                item, manifest.encode("utf-8") if item.filename == MANIFEST else data
            )
    os.replace(temporary, path)
    return changed, left


def main(argv):
    if len(argv) < 2:
        print(
            "使い方: python3 tool/word_book/asodict_rename_words.py <表.toml> <単語帳ファイル>...",
            file=sys.stderr,
        )
        return 64

    table = load_table(argv[0])
    print(f"{argv[0]}: {len(table)} 語")

    failed = 0
    for path in argv[1:]:
        try:
            changed, left = rewrite(path, table)
        except Exception as error:  # 1 冊のために止めない
            print(f"{path}: {error}", file=sys.stderr)
            failed += 1
            continue
        print(f"{path}: {changed} 語 直しました")
        for text in left:
            print(f"  かなに開けていません: {text}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
