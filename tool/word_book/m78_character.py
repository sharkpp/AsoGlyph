#!/usr/bin/env python3
"""m-78.jp（ウルトラマン公式）のキャラクター一覧から単語帳を作る（SPEC 7.4）。

    python3 tool/word_book/m78_character.py <一覧のURL> [出力先フォルダ]

一覧のページをたどり（`rel="next"` を追う）、載っているキャラクターの
名前とサムネイルを集めて、単語帳のフォルダ（YAML ＋ 絵）を書く。
書いたあとは tool/word_book/pack.dart を呼び、`.asodict` にまとめる。

    python3 tool/word_book/m78_character.py https://m-78.jp/character/category/261/
      → work/ウルトラヒーロー/         （YAML ＋ 絵）
      → assets/words/_ウルトラヒーロー.asodict

**URL は 1 つも書かない。** 出発点は引数で受け、次のページも絵の場所も、
そのページに書いてあるものだけをたどる。ページの作りが変われば読めなくなるが、
こちらで組み立てた URL が黙って別のものを指すよりよい。

単語帳の名前も、集める語も、絵の大きさも、ページから引く。だから
一覧の URL を変えれば、そのカテゴリの単語帳がそのまま作れる。

## 名前の落とし方

一覧のカードの見出しは 2 行に割れている（「ウルトラマン」＋「オメガ」）。
これがそのまま SPEC 7.4.0 の `[かっこ]` になる。

    ウルトラマン<br />オメガ  →  [ウルトラマン]オメガ   よみ: うるとらまん おめが

「ウルトラマン」を毎回 6 字書かせると 1 セッション（3〜5分）で終わらないし、
オメガ だけを出したのでは何の語か分からない。前半を出しておくだけにする。

読みが添えてある名前（「A(エース)」「80(エイティ)」）は、かっこの中を読みにする。
書けない字（漢字・ラテン）が添えられているときは、見た目のほうも読みで置き換える
（「A(エース)」→ エース）。数字やカタカナは書けるのでそのまま残す（「80」）。

読みに落とせない字（漢字など）が残った語は**入れずに、名前を挙げて知らせる**。
読みは声で読み上げるためだけにあり（SPEC 7.4）、欠けた読みで読み上げると
別の語になる。「ウルトラの母」のような語は、書き出した YAML に手で足して
tool/word_book/pack.dart を掛け直す。
"""

import io
import os
import re
import subprocess
import sys
import urllib.request
from html.parser import HTMLParser
from urllib.parse import quote, unquote, urljoin, urlsplit, urlunsplit

from PIL import Image

# 絵は WebP にそろえる。元は 100〜300 KB の PNG・JPEG で、58 枚も入れると
# 資産が 14 MB を超える。同じ絵が WebP なら 20 KB 前後で収まる（SPEC 7.4.2）。
# 大きさは変えない。ページが出している大きさのまま焼き直すだけ。
IMAGE_QUALITY = 85

# 1 枚の上限（lib/word/word_image.dart の maxImageBytes と同じ）。
MAX_IMAGE_BYTES = 512 * 1024

USER_AGENT = "AsoGlyph word-book builder (+https://sharkpp.net)"


# ---------------------------------------------------------------- ページを読む


class _ListingParser(HTMLParser):
    """一覧ページから、カテゴリ名・カード・次のページを拾う。

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
            # カテゴリ名。単語帳の名前になる。
            self._in_name = self.name is None

        if not self._main:
            return

        if tag == "a":
            href = attr.get("href")
            if not href:
                return
            if attr.get("rel") == "next":
                self.next_url = urljoin(self._page_url, href)
            elif "c-card" in classes:
                self._card = {"url": urljoin(self._page_url, href), "title": [""]}
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


def crawl(start_url):
    """一覧をたどって、カテゴリ名とカードの並びを返す。

    並びはページに出ている順のまま。新しいヒーローが先に来て、最後が
    いちばん古い「ウルトラマン」になる。
    """
    name = None
    cards = []
    seen = set()
    url = start_url
    while url and url not in seen:
        seen.add(url)
        print(f"  {url}")
        parser = _ListingParser(url)
        parser.feed(fetch(url).decode("utf-8", "replace"))
        name = name or parser.name
        cards += parser.cards
        url = parser.next_url
    return name, cards


# -------------------------------------------------------------------- 語にする

# 「A(エース)」「80(エイティ)」のように読みが添えてある形。
_RUBY = re.compile(r"([^()（）\s]+)[（(]([^)）]+)[)）]")


def to_reading(text):
    """読みに使える字だけを残し、カタカナはひらがなに直す。

    lib/word/reading.dart の toReading と同じ規則。長音符「ー」と空白は残す
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


def _writable(text):
    """かな・長音符・数字だけでできているか。子供が書ける字かどうか。"""
    return bool(text) and all(
        0x3041 <= ord(c) <= 0x3096
        or 0x30A1 <= ord(c) <= 0x30F6
        or ord(c) == 0x30FC
        or c.isdecimal()
        for c in text
    )


def _unreadable(text):
    """読みに落とせない字（漢字・ラテン・数字など）を挙げる。"""
    return [c for c in text if not c.isspace() and not to_reading(c)]


def _convert(part):
    """見出しの 1 行を、書く字・読み・読めなかった字に分ける。"""
    text, reading, unreadable = "", "", []
    pos = 0
    for match in _RUBY.finditer(part):
        head = part[pos : match.start()]
        text += head
        reading += to_reading(head)
        unreadable += _unreadable(head)

        base, ruby = match.group(1), match.group(2)
        # 読みが添えてある。書ける字なら見た目を残し、書けない字は読みで置き換える。
        text += base if _writable(base) else ruby
        reading += to_reading(ruby)
        pos = match.end()

    tail = part[pos:]
    text += tail
    reading += to_reading(tail)
    unreadable += _unreadable(tail)
    return text, reading, unreadable


def to_word(title_lines):
    """カードの見出し（`<br>` で割れた行）から語と読みを作る。

    2 行あれば 1 行目を `[かっこ]` に入れて、出しておくだけにする。
    読めない字が残ったら (None, None, 挙げた字) を返す。
    """
    lines = [line.strip() for line in title_lines]
    lines = [line for line in lines if line]
    if not lines:
        return None, None, []

    if len(lines) == 1:
        text, reading, unreadable = _convert(lines[0])
    else:
        given, given_reading, a = _convert(lines[0])
        written, written_reading, b = _convert("".join(lines[1:]))
        if not written:
            return None, None, []  # 書かせる字が 1 つも無い語は受けない（SPEC 7.4.0）
        text = f"[{given}]{written}"
        reading = f"{given_reading} {written_reading}".strip()
        unreadable = a + b

    if unreadable:
        return None, None, unreadable
    return text, reading, []


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


def yaml_scalar(value):
    """必ず引用符でくくる。「80」のような語が数として読み戻るのを避ける。"""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


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


# ------------------------------------------------------------------------ 本体


def main(argv):
    if not argv:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 64

    start_url = argv[0]
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    print(f"{start_url} をたどります")
    name, cards = crawl(start_url)
    if not name:
        print("カテゴリ名が読めませんでした", file=sys.stderr)
        return 65
    print(f"{name}: {len(cards)} 件")

    directory = argv[1] if len(argv) > 1 else os.path.join(root, "work", name)
    words = []
    skipped = []
    used = {}

    for card in cards:
        text, reading, unreadable = to_word(card["title"])
        title = " ".join(line.strip() for line in card["title"] if line.strip())
        if text is None:
            skipped.append((title, unreadable))
            continue

        word = {"text": text, "reading": reading}
        source = card.get("image")
        if source:
            try:
                data = to_webp(fetch(source))
            except Exception as error:  # 絵 1 枚のために止めない
                print(f"  絵が入りませんでした: {title}（{error}）")
                data = None
            if data and len(data) > MAX_IMAGE_BYTES:
                print(f"  絵が大きすぎます: {title}（{len(data) // 1024} KB）")
                data = None
            if data:
                stem = image_name(card["url"])
                used[stem] = used.get(stem, 0) + 1
                file_name = f"{stem}.webp" if used[stem] == 1 else f"{stem}-{used[stem]}.webp"
                os.makedirs(directory, exist_ok=True)
                with open(os.path.join(directory, file_name), "wb") as file:
                    file.write(data)
                word["image"] = file_name
        words.append(word)

    if not words:
        print("語が 1 つも取れませんでした", file=sys.stderr)
        return 65

    path = write_word_book(directory, name, words)
    print(f"{path} を書きました（{len(words)} 語）")

    if skipped:
        print(f"\n読みに落とせない字があるので入れなかった語（{len(skipped)} 件）:")
        for title, unreadable in skipped:
            print(f"  {title} … {''.join(unreadable)}")
        print(f"  入れるなら {path} に手で足して、下の 1 行を掛け直してください")

    packer = os.path.join("tool", "word_book", "pack.dart")
    print(f"\ndart run {packer} {os.path.relpath(directory, root)}")
    try:
        return subprocess.call(
            ["dart", "run", packer, os.path.relpath(directory, root)], cwd=root
        )
    except FileNotFoundError:
        print("dart が見つかりません。上の 1 行を手で叩いてください", file=sys.stderr)
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
