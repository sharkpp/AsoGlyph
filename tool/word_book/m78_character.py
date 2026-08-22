#!/usr/bin/env python3
"""m-78.jp（ウルトラマン公式）のキャラクター一覧から単語帳を作る（SPEC 7.4）。

    python3 tool/word_book/m78_character.py <一覧のURL> [出力先フォルダ] [選択肢]

一覧のページをたどり（`rel="next"` を追う）、載っているキャラクターの
名前とサムネイルを集めて、**作品ごとに** 単語帳のフォルダ（YAML ＋ 絵）を書く。
書いたあとは tool/word_book/pack.dart を呼び、`.asodict` にまとめる。

    python3 tool/word_book/m78_character.py https://m-78.jp/character/category/626/ \
        --kanji tool/word_book/ultra_monster_kanji2hira.toml
      → work/ウルトラ怪獣/ウルトラ怪獣(ウルトラQ)/    （YAML ＋ 絵）
      → assets/words/_ウルトラ怪獣(ウルトラQ).asodict
      → …作品の数だけ

**URL は 1 つも書かない。** 出発点は引数で受け、次のページも絵の場所も、
そのページに書いてあるものだけをたどる。ページの作りが変われば読めなくなるが、
こちらで組み立てた URL が黙って別のものを指すよりよい。

## 作品ごとに分ける

一覧は作品の見出し（`<h2 class="character-archive__title">`）で区切られている。
ウルトラ怪獣は 364 体あり、1 冊にすると子供の一覧が延々と続く。作品ごとなら
「うちの子はウルトラマンだけ」という割り振り（`User.wordBooks`）ができる。
見出しはページをまたいで続くので、見出しの無いまま始まるページは前のページの
作品に続ける。

## 名前の落とし方

一覧のカードの見出しは 2 行に割れている（「深海怪獣」＋「ピーター」）。
これがそのまま SPEC 7.4.0 の `[かっこ]` になる。

    深海怪獣<br />ピーター  →  [深海怪獣]ピーター

**漢字はそのまま持つ。** かなに開くのは置き換えの表（`--kanji` の TOML）だけの
仕事で、ここでは何も直さない。名前をここで直すと、直したあとの字が
どこから来たのかが単語帳からは読めなくなる。表なら 1 か所を見れば分かる。

読み（`reading`）だけは、その場で表を当ててから起こす。読みは声で読み上げる
ためだけにあり（SPEC 7.4）、かなでなければ単語帳として読み込めない。
表に無い漢字ばかりの名前（「異次元列車」）は読みが空になるので**入れずに、
名前を挙げて知らせる**。表に読みを書いて、もう一度掛ければ入る。

## 置き換えの表

集めた名前に出てくる漢字は、`--kanji` に指した TOML へ書き出す。すでにある
ファイルは**読みを残したまま**書き直すので、掛け直しても書いた読みは消えない。

    "深海怪獣" = "しんかいかいじゅう"  # 深海怪獣 ピーター

Pillow が要る（`pip install Pillow`）。落とした PNG・JPEG を WebP に焼き直す。
元のままだと 364 枚で 90 MB を超え、資産に入れるには大きすぎる。
"""

import argparse
import io
import os
import re
import subprocess
import sys
import urllib.request
from html.parser import HTMLParser
from urllib.parse import quote, unquote, urljoin, urlsplit, urlunsplit

from PIL import Image

from word_text import apply_table, load_table, reading_of, table_keys, write_table, yaml_scalar

# 絵は WebP にそろえる。元は 100〜300 KB の PNG・JPEG で、364 枚も入れると
# 資産が 90 MB を超える。同じ絵が WebP なら 20 KB 前後で収まる（SPEC 7.4.2）。
# 大きさは変えない。ページが出している大きさのまま焼き直すだけ。
IMAGE_QUALITY = 85

# 1 枚の上限（lib/word/word_image.dart の maxImageBytes と同じ）。
MAX_IMAGE_BYTES = 512 * 1024

USER_AGENT = "AsoGlyph word-book builder (+https://sharkpp.net)"


# ---------------------------------------------------------------- ページを読む


class _ListingParser(HTMLParser):
    """一覧ページから、カテゴリ名・作品の見出し・カード・次のページを拾う。

    カードは `<main>` の中だけを見る。同じ作りのカードがヘッダのメニューにも
    並んでいて、そちらまで拾うと一覧に無いものが混ざる。
    """

    def __init__(self, page_url):
        super().__init__(convert_charrefs=True)
        self._page_url = page_url
        self.name = None
        self.cards = []
        self.next_url = None
        self._main = 0
        self._h1 = 0
        self._in_name = False
        self._in_work = False
        self._work = None
        self._card = None
        self._in_title = False

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_starttag(self, tag, attrs):
        attr = dict(attrs)
        classes = (attr.get("class") or "").split()

        if tag == "main":
            self._main += 1
        elif tag == "h1":
            self._h1 += 1
        elif tag == "span" and self._h1 and "c-title-main__ja" in classes:
            # カテゴリ名。単語帳の名前の頭になる。
            self._in_name = self.name is None

        if not self._main:
            return

        if tag == "h2" and "character-archive__title" in classes:
            # 作品の見出し。ここから下のカードはこの作品のもの。
            self._in_work = True
        elif tag == "a":
            href = attr.get("href")
            if not href:
                return
            if attr.get("rel") == "next":
                self.next_url = urljoin(self._page_url, href)
            elif "c-card" in classes:
                self._card = {
                    "url": urljoin(self._page_url, href),
                    "title": [""],
                    "work": self._work,
                }
        elif tag == "img" and self._card is not None:
            # 遅らせて読む作りなので、素の src は placeholder が入っている。
            src = attr.get("data-src") or attr.get("src")
            if src:
                self._card["image"] = urljoin(self._page_url, src)
        elif tag == "p" and self._card is not None and "c-card__title" in classes:
            self._in_title = True
        elif tag == "br" and self._in_title:
            self._card["title"].append("")

    def handle_endtag(self, tag):
        if tag == "main":
            self._main = max(0, self._main - 1)
        elif tag == "h1":
            self._h1 = max(0, self._h1 - 1)
            self._in_name = False
        elif tag == "h2":
            self._in_work = False
        elif tag == "span":
            self._in_name = False
        elif tag == "p":
            self._in_title = False
        elif tag == "a" and self._card is not None:
            self.cards.append(self._card)
            self._card = None

    def handle_data(self, data):
        if self._in_name and self.name is None:
            self.name = data.strip() or None
            self._in_name = False
        elif self._in_work:
            self._work = data.strip() or self._work
        elif self._in_title:
            self._card["title"][-1] += data


def fetch(url):
    # ページには「アーク_サムネイルアイコン.jpg」のように、日本語のままの
    # 場所も書いてある。取りに行く前に符号化する（すでに %XX になっている
    # ところは触らない）。
    parts = urlsplit(url)
    encoded = urlunsplit(
        parts._replace(path=quote(parts.path, safe="/%"), query=quote(parts.query, safe="=&%"))
    )
    request = urllib.request.Request(encoded, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request) as response:
        return response.read()


def crawl(start_url, until=None):
    """一覧をたどって、カテゴリ名とカードの並びを返す。

    並びはページに出ている順のまま。新しい作品が先に来て、最後がいちばん古い
    作品になる。[until] を渡すと、その名前のカードまでで打ち切る。
    """
    name = None
    cards = []
    seen = set()
    work = None
    url = start_url
    while url and url not in seen:
        seen.add(url)
        print(f"  {url}")
        parser = _ListingParser(url)
        parser.feed(fetch(url).decode("utf-8", "replace"))
        name = name or parser.name
        for card in parser.cards:
            # 見出しはページをまたいで続く。見出しの無いまま始まったページは、
            # 前のページの作品に続ける。
            work = card["work"] or work
            card["work"] = work
            cards.append(card)
            if until and until in "".join(line.strip() for line in card["title"]):
                print(f"  {until} まで来たので打ち切ります")
                return name, cards
        url = parser.next_url
    return name, cards


# -------------------------------------------------------------------- 語にする


def to_text(title_lines):
    """カードの見出し（`<br>` で割れた行）から、ことばを作る。

    2 行あれば 1 行目を `[かっこ]` に入れて、出しておくだけにする（SPEC 7.4.0）。
    漢字はそのまま。かなに開くのは置き換えの表の仕事。

    1 行しかないときは、全角の空白も同じ区切りとして見る。ページは肩書きと
    名前を `<br>` で割っているが、たまに空白で済ませている（「冥府闇将軍獣　
    ヘルナラク」）。同じものなので同じに扱う。

    **書かせるほうの空白は落とす。** 空白はどの文字種にも入っていないので
    （SPEC 5）、混じっているとその語は出題から丸ごと外れる（SPEC 7.4.2）。
    """
    lines = list(title_lines)
    if len(lines) == 1:
        lines = lines[0].split("　", 1)
    lines = [re.sub(r"\s+", " ", line).strip() for line in lines]
    lines = [line for line in lines if line]
    if not lines:
        return None
    if len(lines) == 1:
        return lines[0].replace(" ", "")
    written = "".join(lines[1:]).replace(" ", "")
    if not written:
        return None  # 書かせる字が 1 つも無い語は受けない（SPEC 7.4.0）
    return f"[{lines[0]}]{written}"


# ---------------------------------------------------------------------- 絵と出力


def to_webp(data):
    """落とした絵を WebP にする。大きさは変えない。"""
    image = Image.open(io.BytesIO(data))
    if image.mode not in ("RGB", "RGBA"):
        image = image.convert("RGBA" if "A" in image.getbands() else "RGB")
    out = io.BytesIO()
    image.save(out, "WEBP", quality=IMAGE_QUALITY, method=6)
    return out.getvalue()


def image_name(url):
    """絵のファイル名を、キャラクターのページの名前から作る。"""
    slug = unquote(urlsplit(url).path).strip("/").split("/")[-1]
    return re.sub(r"[^0-9A-Za-z_-]+", "-", slug) or "image"


def write_word_book(directory, name, words):
    os.makedirs(directory, exist_ok=True)
    out = ["version: 1", f"name: {yaml_scalar(name)}", "words:"]
    for word in words:
        out.append(f"  - text: {yaml_scalar(word['text'])}")
        out.append(f"    reading: {yaml_scalar(word['reading'])}")
        if word.get("image"):
            out.append(f"    image: {yaml_scalar(word['image'])}")
    path = os.path.join(directory, f"{name}.yaml")
    with open(path, "w", encoding="utf-8") as file:
        file.write("\n".join(out) + "\n")
    return path


def book_name(category, work):
    """単語帳の名前。「ウルトラ怪獣(ウルトラQ)」。

    作品の見出しが 1 つも無い一覧（ウルトラヒーロー）は、割りようがないので
    1 冊にまとめ、カテゴリ名でそのまま呼ぶ。

    ファイル名にもなるので、置き場の区切りに使われる字だけ落とす。
    """
    return re.sub(r'[/\\:*?"<>|]+', "-", f"{category}({work})")


# ------------------------------------------------------------------------ 本体


def main(argv):
    parser = argparse.ArgumentParser(description="m-78.jp の一覧から単語帳を作る")
    parser.add_argument("url", help="一覧のURL")
    parser.add_argument("directory", nargs="?", help="出力先フォルダ（既定 work/<カテゴリ名>）")
    parser.add_argument("--until", help="この名前のカードまでで打ち切る")
    parser.add_argument("--kanji", help="漢字をかなに開く表（既定 <出力先>/kanji2hira.toml）")
    args = parser.parse_args(argv)

    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    print(f"{args.url} をたどります")
    category, cards = crawl(args.url, args.until)
    if not category:
        print("カテゴリ名が読めませんでした", file=sys.stderr)
        return 65

    # 作品ごとに束ねる。並びはページに出ていた順のまま。
    works = {}
    for card in cards:
        card["text"] = to_text(card["title"])
        works.setdefault(card["work"], []).append(card)
    print(f"{category}: {len(cards)} 件 / {len(works)} 作品")

    directory = args.directory or os.path.join(root, "work", category)
    table_path = args.kanji or os.path.join(directory, "kanji2hira.toml")

    # 表を書き直す。読みを書いたぶんはそのまま残る。
    entries = {}
    for work, group in works.items():
        for card in group:
            for key in table_keys(card["text"] or ""):
                entries.setdefault(key, (key, card["text"], work))
    table = load_table(table_path) if os.path.exists(table_path) else {}
    os.makedirs(os.path.dirname(os.path.abspath(table_path)), exist_ok=True)
    blank = write_table(table_path, list(entries.values()), table)
    print(f"{table_path}: {len(entries)} 語（読みがまだ {blank} 語）")

    packed = 0
    skipped = []
    for work, group in works.items():
        name = category if work is None else book_name(category, work)
        folder = os.path.join(directory, name)
        words = []
        used = {}

        for card in group:
            text = card["text"]
            reading = reading_of(apply_table(text or "", table))
            if not text or not reading:
                skipped.append((text or "".join(card["title"]), work))
                continue

            word = {"text": text, "reading": reading}
            source = card.get("image")
            if source:
                stem = image_name(card["url"])
                used[stem] = used.get(stem, 0) + 1
                file_name = f"{stem}.webp" if used[stem] == 1 else f"{stem}-{used[stem]}.webp"
                path = os.path.join(folder, file_name)
                # すでに落としてある絵は取り直さない。表に読みを足して
                # 掛け直すのがふつうの使い方で、そのたびに 364 枚は重い。
                if not os.path.exists(path):
                    data = _load_image(source, text)
                    if data:
                        os.makedirs(folder, exist_ok=True)
                        with open(path, "wb") as file:
                            file.write(data)
                if os.path.exists(path):
                    word["image"] = file_name
            words.append(word)

        if not words:
            continue
        yaml_path = write_word_book(folder, name, words)
        print(f"{yaml_path}（{len(words)} 語）")
        output = os.path.join("assets", "words", f"_{name}.asodict")
        if _pack(root, os.path.relpath(folder, root), output) == 0:
            packed += 1

    print(f"\n{packed} 冊 書きました")
    if skipped:
        print(f"\n読みが起こせないので入れなかった語（{len(skipped)} 件）:")
        for text, work in skipped:
            print(f"  {work}: {text}")
        print(f"  {table_path} に読みを書いて、もう一度掛けてください")
    return 0


def _load_image(source, text):
    try:
        data = to_webp(fetch(source))
    except Exception as error:  # 絵 1 枚のために止めない
        print(f"  絵が入りませんでした: {text}（{error}）")
        return None
    if len(data) > MAX_IMAGE_BYTES:
        print(f"  絵が大きすぎます: {text}（{len(data) // 1024} KB）")
        return None
    return data


def _pack(root, folder, output):
    packer = os.path.join("tool", "word_book", "pack.dart")
    try:
        return subprocess.call(["dart", "run", packer, folder, output], cwd=root)
    except FileNotFoundError:
        print(f"dart が見つかりません: dart run {packer} {folder} {output}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
