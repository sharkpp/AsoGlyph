#!/usr/bin/env python3
"""単語帳を紙に敷き詰めて PDF にする（SPEC 7.4）。

    python3 tool/word_book/asodict2pdf.py [選択肢] <単語帳>...

単語帳は子供が語を選ぶためのもので（SPEC 7.4.2 の「字が読めない子は、絵でしか
語を選べない」）、その一覧を紙で見たいことがある。絵と名前を並べて刷れば、
書く前に「どれを書くか」を紙の上で選べる。かるたにも切れる。

受けるのは 3 つ。**どれも同じ中身**（絵つきの単語帳）を指す。

| 渡すもの | 絵の在り処 |
|---|---|
| `<名前>.asodict` | zip の `images/`（SPEC 7.4.1） |
| `<名前>.yaml` | 隣の `images/` |
| フォルダ | 中の `words.yaml` と `images/` |

集める道具（`m78_character.py`）が書くのはフォルダなので、`pack.dart` を
通す前でも刷れる。**出す先は入力ごとに 1 つ**（`<名前>.pdf`）。

## まとめて 1 つにする

`--merge` を付けると、渡した単語帳ぜんぶが 1 つの PDF になる（出す先は
`--output` で決める）。作品ごとに 1 冊にしてある単語帳（`m78_character.py` は
10 冊書く）を、刷るときだけ束ねるためのもの。

- **名前を刷るなら（`--title yes`）単語帳ごとに紙を変える。** 見出しの下から
  始めないと、どこから別の冊になったのかが紙の上で分からない
- **名前を刷らないなら（`--title no`）紙を変えずに詰める。** 名前の出ない
  切れ目で紙を変えても、変わったことが紙に何も残らないので、ただ空きが増える
  （ウルトラ怪獣 10 冊 364 語で 12 ページ → 8 ページ）
- 丁付けは**PDF ぜんぶを通して**数える。刷って重ねる順そのままになる
- **作った人は、渡された冊ぜんぶで同じときだけ残す。** 混ざったものを 1 人の
  名前で出すと、出どころを取り違えたまま渡ることになる（SPEC 7.4）
- 語が 1 つも残らなかった冊（`--tag` で全部落ちた）には**紙を割り当てない**。
  白紙が挟まるだけで、何も伝えない

## 1 マスが 1 語

紙をマスに割って、1 マスに 1 語を置く。マスの大きさは指定（`--word-size`）で、
入るだけ並べる。余りは次の紙へ。

**紙の余白は既定で 0。** 一覧は詰まっているほうが見やすく、刷る枚数も減る。
端が切れるプリンタで刷るときは `--margin` を足す。1 つなら上下左右、2 つなら
上下と左右、4 つなら上・下・左・右。並びは「縦から横へ」で、`--word-align` の
垂直,水平 と同じ（CSS の 上,右,下,左 とは違う）。

マスが入りきらなかったぶんの空きは左右で半分ずつにする（片側に寄せると、
切って使うときに向きで狂う）。

- 絵は**マスいっぱいが `--image-zoom 1.0`**。そこから割合で縮める。
  **引き伸ばさない。** 縦横の比を変えると、親が入れた絵と違うものが出る
  （SPEC 7.4.2 の「縮小はしない」と同じ理由）
- 縮めたぶんの空きは**名前の反対側**に出す（名前が下なら絵は上へ寄る）。
  1.0 のままなら空きが無いので、名前は絵の上に重なる。重ねたくなければ
  `--image-zoom` を下げて、名前の側を空ける
- 名前がマスに入らなければ**字を小さくする**。`--word-wrap <字数>` を渡すと、
  その字数で**折り返す**
- マスは敷き詰める（`--gap` の既定は 0）ので、マスの内側に余白を取る
  （`--padding`）。取らないと隣の語と字がくっついて、どこまでが 1 語か読めない

## マスの上端に小見出しを置ける

`--word-title` を書くと、マスの上端に 1 行を添える。`{book}` はその語が入って
いた単語帳の名前に替わる。

    --word-title "{book}"      → ウルトラ怪獣(ウルトラマンテオ)
    --word-title ウルトラ怪獣   → 書いたとおり

まとめて 1 つにして詰めたとき（`--merge --title no`）、**どの冊から来た語なのかが
紙の上から消える**。切ってかるたにするなら、その 1 枚がどの作品のものかは
札の側に要る。塗りと縁取りはことばと同じものを使う（同じ紙の上で見出しだけ
別の色になる理由がない）。

ことばを上に寄せているとき（`--word-align top,...`）は、**ことばを小見出しの
下に置く**。同じ上端に重ねると読めなくなる。

## 長い名前は、縮めるか折り返すか

既定は**縮める**（1 行のまま小さくする）。同じ紙の上で行数が揃っているほうが
一覧として読みやすく、長い名前だけが 2 行になると札の見た目が揃わない。
字が小さくなりすぎるときは `--word-wrap yes` で**折り返す**に替える。

折り返すときは、

- **空白があれば空白で折る**（「ウルトラマントリガー NEW GENERATION TIGA」で
  語の途中から折れないように）。無ければ字と字のあいだで折る
- **行頭に置かない字**（小書き・長音符・句読点・閉じかっこ）は前の行に連れていく。
  行の頭に「ー」や「っ」が来ると、そこで別の語のように読める
- 行が増えて縦にはみ出したら、はみ出したぶんだけ字を小さくして折り直す

## 名前は縁を取ってから塗る

名前は絵の上に重なることがある（`--image-zoom 1.0`）ので、**縁取りが無いと
絵の濃いところで読めなくなる**。既定は白い縁（`--word-outline-color`）を
**描く大きさ**の 0.08 倍で取る。`--word-outline-width` で幅を書けばそのまま使い、
`0` を渡せば取らない。

幅を書かないときに描く大きさから決めるのは、**縮んだ字に太いままの縁が付くと、
細い画が縁で埋まって字が縁の色の塊になる**ため。頼んだ大きさは、幅に入らなければ
縮む（マスに 14 字の名前など）。

縁を先に、中をあとに描く。逆にすると縁の内側半分が字を細らせる。線の幅を倍に
しているのも同じ理由で、内側の半分はあとから塗る中に隠れる。

## 字の大きさは 1 冊につき 1 つ

`--word-font-size` を省いたときの大きさは、**その 1 冊を見て決める**。絵が出る
なら名前は添え書きなので小さく、絵が無ければマスは名前のものなので大きく出す。
マスごとに決めると、絵のある語と無い語で見出しの大きさが変わり、同じ紙の上で
字の大きさが揃わなくなる。

## かっこは外して出す

`[かっこ]` は「出しておくだけで書かせない」という印（SPEC 7.4.0）で、名前の
一部ではない。紙の上では書く／書かないの区別が要らないので、かっこだけを
外して続けて出す。

## 字は埋め込まない

既定は Adobe-Japan1 の標準フォント（`HeiseiKakuGo-W5`）を**名前で指す**だけで、
ファイルは埋め込まない。単語帳 1 冊の PDF は 364 語ぶんの絵で数 MB になるので、
そこへフォントまで足したくない。刷る先の環境に日本語フォントが無いときは
`--font <ttf>` で埋め込む。

reportlab が要る（`pip install reportlab`）。SVG の絵を描くには svglib も
（無ければ SVG の絵だけが抜ける。PNG・JPEG・WebP はそのまま描ける）。
"""

import argparse
import io
import os
import re
import sys
import zipfile
from collections import namedtuple

from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas as pdfcanvas

from word_text import yaml_unscalar

# zip の中の単語帳本体（lib/word/word_book_export.dart の _manifest と同じ）。
MANIFEST = "words.yaml"
IMAGES = "images"

MM = 72.0 / 25.4  # PDF の長さは 1/72 インチ
UNITS = {"mm": MM, "cm": MM * 10, "pt": 1.0, "in": 72.0}

# 用紙。JIS の B（182×257mm）を採る。日本で「B5」と言えばこちらで、ISO の B5
# （176×250mm）を出すと刷ったときに縁がずれる。
PAGE_SIZES = {
    "a3": (297, 420),
    "a4": (210, 297),
    "a5": (148, 210),
    "a6": (105, 148),
    "b4": (257, 364),
    "b5": (182, 257),
    "b6": (128, 182),
    "letter": (215.9, 279.4),
    "legal": (215.9, 355.6),
}

VERTICAL = ("top", "middle", "bottom")
HORIZONTAL = ("left", "center", "right")

# 絵の形（SPEC 7.4.2）。SVG だけは描き方が違う。
SVG_SUFFIXES = (".svg",)

# 紙の余白。並びは「縦から横へ」（`--word-align` と同じ）。
Margins = namedtuple("Margins", "top bottom left right")

# 行と行の間（字の大きさに対する割合）。
LEADING = 1.15

# 縁取りの幅（字の大きさに対する割合）。幅を書かなかったときに使う。
OUTLINE_RATIO = 0.08

# 折り返しの決めごと。`count` が 0 なら折らない。`minimum` は最後の行の下限。
Wrap = namedtuple("Wrap", "count minimum")

# 行頭に置かない字（行頭禁則）。小書き・長音符・句読点・閉じかっこ。
NOT_LINE_START = set("、。，．・：；？！ー〜ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ")
NOT_LINE_START |= set("」』）］｝〉》】〕”’!?),.:;")


# --------------------------------------------------------------- 引数の読み取り


def length(value):
    """`10mm` `1cm` `12pt` `0.5in` を PDF の長さにする。単位を省くと mm。"""
    text = value.strip().lower()
    for unit, scale in UNITS.items():
        if text.endswith(unit):
            text = text[: -len(unit)]
            break
    else:
        scale = MM
    try:
        return float(text) * scale
    except ValueError:
        raise argparse.ArgumentTypeError(f"長さになりません: {value}")


def page_size(value):
    """用紙のサイズ。名前（`a4`）か `幅,高さ`。"""
    name = value.strip().lower()
    if name in PAGE_SIZES:
        width, height = PAGE_SIZES[name]
        return width * MM, height * MM
    if "," not in value:
        raise argparse.ArgumentTypeError(
            f"用紙の名前がありません: {value}（{'/'.join(PAGE_SIZES)} か「210mm,297mm」）"
        )
    return rect_size(value)


def rect_size(value):
    """`40mm,30mm` か `40mm`（正方形）。"""
    parts = [part for part in value.split(",") if part.strip()]
    if len(parts) == 1:
        side = length(parts[0])
        return side, side
    if len(parts) == 2:
        return length(parts[0]), length(parts[1])
    raise argparse.ArgumentTypeError(f"「幅,高さ」の形で書いてください: {value}")


def margins(value):
    """紙の余白。`10mm` / `10mm,5mm`（上下,左右）/ `10mm,5mm,8mm,8mm`（上,下,左,右）。

    2 つのときの並び（上下,左右）をそのまま開くと 上,下,左,右 になる。CSS の
    4 つ組（上,右,下,左）とは並びが違うが、この道具のほかの指定（`--word-align`
    の 垂直,水平）と同じ「縦から横へ」の並びに揃える。
    """
    parts = [part for part in value.split(",") if part.strip()]
    sizes = [length(part) for part in parts]
    if len(sizes) == 1:
        top = bottom = left = right = sizes[0]
    elif len(sizes) == 2:
        top = bottom = sizes[0]
        left = right = sizes[1]
    elif len(sizes) == 4:
        top, bottom, left, right = sizes
    else:
        raise argparse.ArgumentTypeError(
            f"余白は 1 つ（上下左右）・2 つ（上下,左右）・4 つ（上,下,左,右）で書いてください: {value}"
        )
    return Margins(top, bottom, left, right)


def flag(value):
    """`yes` / `no`。"""
    text = value.strip().lower()
    if text in ("yes", "y", "true", "1", "on"):
        return True
    if text in ("no", "n", "false", "0", "off"):
        return False
    raise argparse.ArgumentTypeError(f"yes か no で書いてください: {value}")


def color(value):
    """`0,0,0`（各 0–255）か `#rrggbb`。"""
    text = value.strip()
    if text.startswith("#"):
        digits = text[1:]
        if len(digits) == 3:
            digits = "".join(char * 2 for char in digits)
        if len(digits) != 6:
            raise argparse.ArgumentTypeError(f"色になりません: {value}")
        try:
            return tuple(int(digits[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
        except ValueError:
            raise argparse.ArgumentTypeError(f"色になりません: {value}")
    parts = value.split(",")
    if len(parts) != 3:
        raise argparse.ArgumentTypeError(f"「r,g,b」（各 0–255）で書いてください: {value}")
    try:
        numbers = [float(part) for part in parts]
    except ValueError:
        raise argparse.ArgumentTypeError(f"色になりません: {value}")
    if any(number < 0 or number > 255 for number in numbers):
        raise argparse.ArgumentTypeError(f"色は 0–255 で書いてください: {value}")
    return tuple(number / 255.0 for number in numbers)


def alignment(value):
    """`bottom,center`（垂直,水平）。1 つだけなら、その向きだけを決める。"""
    parts = [part.strip().lower() for part in value.split(",") if part.strip()]
    vertical, horizontal = "bottom", "center"
    if len(parts) == 2:
        # 順は 垂直,水平。`center` はどちらにも書けるので、位置で決める。
        first, second = parts
        vertical = "middle" if first == "center" else first
        horizontal = "center" if second == "middle" else second
    elif len(parts) == 1:
        # 1 つだけなら、その語で向きが決まる（`middle` は垂直、`center` は水平）。
        word = parts[0]
        if word in VERTICAL:
            vertical = word
        elif word in HORIZONTAL:
            horizontal = word
        else:
            raise argparse.ArgumentTypeError(f"位置になりません: {value}")
    else:
        raise argparse.ArgumentTypeError(f"「垂直,水平」の形で書いてください: {value}")
    if vertical not in VERTICAL or horizontal not in HORIZONTAL:
        raise argparse.ArgumentTypeError(
            f"垂直は {'/'.join(VERTICAL)}、水平は {'/'.join(HORIZONTAL)}: {value}"
        )
    return vertical, horizontal


def font_size(value):
    """字の大きさ。`auto` ならマスの高さから決める。"""
    return optional_length(value)


def optional_length(value):
    """長さ。`auto` なら「決めない」（既定の決め方に任せる）。"""
    if value.strip().lower() == "auto":
        return None
    return length(value)


# ----------------------------------------------------------------- 単語帳を読む


class Book:
    """単語帳 1 冊。`words` は `(ことば, 読み, 絵の名前, タグ)`。"""

    def __init__(self, name, author, description, words, images):
        self.name = name
        self.author = author
        self.description = description
        self.words = words
        self.images = images  # 絵の名前 -> bytes

    def image_of(self, name):
        return self.images.get(name) if name else None


def read_book(path):
    """`.asodict` / `.yaml` / フォルダ を読む。絵は名前で引けるようにして持つ。"""
    if os.path.isdir(path):
        manifest_path = os.path.join(path, MANIFEST)
        if not os.path.exists(manifest_path):
            raise ValueError(f"{MANIFEST} がありません")
        with open(manifest_path, encoding="utf-8") as file:
            manifest = file.read()
        return _book(manifest, _read_image_dir(os.path.join(path, IMAGES)))

    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            if MANIFEST not in archive.namelist():
                raise ValueError(f"{MANIFEST} が入っていません")
            manifest = archive.read(MANIFEST).decode("utf-8")
            images = {}
            for name in archive.namelist():
                if name.startswith(IMAGES + "/") and not name.endswith("/"):
                    images[name[len(IMAGES) + 1 :]] = archive.read(name)
        return _book(manifest, images)

    with open(path, encoding="utf-8") as file:
        manifest = file.read()
    return _book(manifest, _read_image_dir(os.path.join(os.path.dirname(path), IMAGES)))


def _read_image_dir(directory):
    if not os.path.isdir(directory):
        return {}
    images = {}
    for name in os.listdir(directory):
        full = os.path.join(directory, name)
        if os.path.isfile(full):
            with open(full, "rb") as file:
                images[name] = file.read()
    return images


_KEY = re.compile(r"^(\s*)(?:-\s*)?([A-Za-z_]+):\s*(.*)$")


def _book(manifest, images):
    """`words.yaml` を読む。書いているのは `lib/word/word_book_export.dart` の
    `_scalar` と同じ形（素の語か、二重引用符でくくったもの）なので、行ごとに
    `鍵: 値` を見れば足りる。**知らない鍵は黙って通す**——単語帳に鍵が増えても、
    紙に刷れなくなる理由はない。
    """
    meta = {}
    words = []
    current = None
    for raw in manifest.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = _KEY.match(line)
        if not match:
            continue
        indent, key, value = match.group(1), match.group(2), _value(match.group(3))
        item = line.lstrip().startswith("-")
        if item and key == "text":
            current = {"text": value, "reading": "", "image": "", "tags": []}
            words.append(current)
        elif indent and current is not None:
            if key == "tags":
                current["tags"] = _tags(value)
            elif key in current:
                current[key] = value
        elif not indent:
            meta[key] = value
            current = None
    return Book(
        meta.get("name", ""),
        meta.get("author", ""),
        meta.get("description", ""),
        [(word["text"], word["reading"], word["image"], word["tags"]) for word in words],
        images,
    )


def _value(text):
    """値を取り出す。素の語のうしろに付いた注記（` # …`）は落とす。"""
    text = text.strip()
    if text.startswith('"') or text.startswith("'"):
        quote = text[0]
        closing = text.rfind(quote)
        if closing > 0:
            return yaml_unscalar(text[: closing + 1])
        return yaml_unscalar(text)
    return re.split(r"\s+#", text, maxsplit=1)[0].strip()


def _tags(value):
    return [tag.strip() for tag in value.strip("[]").split(",") if tag.strip()]


# ------------------------------------------------------------------------- 描く


def content_inset(options):
    """マスの縁から中身までの幅。枠は線の真ん中を通るので、その太さも入れる。"""
    return (options.border_width if options.border else 0.0) + options.padding


def band_height(size):
    """ことばの帯の高さ。字の大きさから決める（上下に少し空ける）。"""
    return size * 1.6


def display_text(text):
    """紙に出す形。かっこ（SPEC 7.4.0）は外して続ける。"""
    return text.replace("[", "").replace("]", "")


def draw_image(canvas, data, name, box, anchor="middle"):
    """絵を `box`（x, y, 幅, 高さ）に収めて描く。`anchor` は縦の寄せ先。

    引き伸ばさない。縦横の比を変えると、親が入れた絵と違うものになる。
    余ったところは `anchor` の反対側に出す。
    """
    x, y, width, height = box
    if width <= 0 or height <= 0:
        return
    if name.lower().endswith(SVG_SUFFIXES):
        _draw_svg(canvas, data, box, anchor)
        return

    reader = ImageReader(io.BytesIO(data))
    source_width, source_height = reader.getSize()
    if not source_width or not source_height:
        raise ValueError("絵の大きさが取れません")
    scale = min(width / source_width, height / source_height)
    drawn_width, drawn_height = source_width * scale, source_height * scale
    canvas.drawImage(
        reader,
        x + (width - drawn_width) / 2,
        _anchored(y, height, drawn_height, anchor),
        drawn_width,
        drawn_height,
        mask="auto",  # PNG・WebP の透過をそのまま抜く
    )


def _anchored(y, height, drawn_height, anchor):
    """縦の置き場所。`top` は上端、`bottom` は下端、`middle` は真ん中に合わせる。"""
    if anchor == "top":
        return y + height - drawn_height
    if anchor == "bottom":
        return y
    return y + (height - drawn_height) / 2


def _draw_svg(canvas, data, box, anchor):
    """SVG を描く。svglib が無ければ、その絵だけを抜く。"""
    try:
        from reportlab.graphics import renderPDF
        from svglib.svglib import svg2rlg
    except ImportError:
        raise ValueError("SVG を描くには svglib が要ります（pip install svglib）")

    drawing = svg2rlg(io.BytesIO(data))
    if drawing is None or not drawing.width or not drawing.height:
        raise ValueError("SVG が読めません")
    x, y, width, height = box
    scale = min(width / drawing.width, height / drawing.height)
    drawing.scale(scale, scale)
    drawing.width *= scale
    drawing.height *= scale
    renderPDF.draw(
        drawing,
        canvas,
        x + (width - drawing.width) / 2,
        _anchored(y, height, drawing.height, anchor),
    )


def fit_size(text, font, size, width):
    """マスに入る字の大きさ。入らなければ小さくする（折り返さない）。"""
    if not text:
        return size
    drawn = pdfmetrics.stringWidth(text, font, size)
    if drawn <= width or drawn <= 0:
        return size
    return size * width / drawn


def wrap_text(text, wrap):
    """`wrap.count` 字までで折る。**字の大きさは見ない。**

    どこで折るかを字数で決めると、折り返しと大きさが混ざらない。行が決まって
    から大きさを決められるので（[fit_lines]）、「入るいちばん大きい字」を
    探し回らずに済み、頼んだ大きさより大きくもならない。

    - 空白があれば**その手前で折る**（空白は落とす）。「ウルトラマントリガー
      NEW GENERATION TIGA」のような名前で、語の途中から折れないようにする。
      そのぶん行は `count` 字より短くなる
    - **行頭に置かない字**（小書き・長音符・句読点・閉じかっこ）は、折る前の行に
      連れていく。行の頭に「ー」や「っ」が来ると、そこで別の語のように読める
    - **最後の行が `wrap.minimum` 字以下になるなら、折るのをやめる**（1 行に戻す）。
      2 字だけの行がぶら下がると、そこで語が終わっているように見える。1 行のまま
      小さくしたほうが読める
    """
    if not wrap.count:
        return [text]

    lines, line = [], ""
    for char in text:
        if len(line) >= wrap.count and char not in NOT_LINE_START:
            if char in " 　":
                lines.append(line)
                line = ""
                continue
            cut = line.rfind(" ")
            if cut > 0:
                lines.append(line[:cut])
                line = line[cut + 1 :] + char
            else:
                lines.append(line)
                line = char
            continue
        line += char
    if line:
        lines.append(line)
    if not lines:
        return [""]
    if len(lines) > 1 and len(lines[-1]) <= wrap.minimum:
        return [text]
    return lines


def block_height(count, font, size):
    """`count` 行ぶんの高さ。"""
    ascent, descent = (value * size / 1000.0 for value in pdfmetrics.getAscentDescent(font, 1000))
    return (count - 1) * size * LEADING + (ascent - descent)


def fit_lines(lines, font, size, width, height):
    """行が幅と高さに収まる大きさ。**頼んだ大きさより大きくはしない。**

    行は字数で決まっていて（[wrap_text]）大きさによらないので、はみ出した割合で
    1 度縮めればそれで収まる。
    """
    widest = max(pdfmetrics.stringWidth(line, font, size) for line in lines)
    if widest > width > 0:
        size *= width / widest
    needed = block_height(len(lines), font, size)
    if needed > height > 0:
        size *= height / needed
    return size


def draw_word(canvas, text, font, size, box, align, color, outline, outline_width, wrap):
    """名前を `box` の中の指定の位置に描く。縁取りをしてから中を塗る。

    絵の上に重なる（`--image-zoom 1.0`）ので、縁取りが無いと絵の濃いところで
    名前が読めなくなる。**縁を先に、中をあとに描く。** 逆にすると、縁の内側
    半分が字を細らせる。線の幅を倍にしているのはそのためで、内側の半分は
    あとから塗る中に隠れ、外へ出た半分だけが縁として残る。

    **縁は行ぜんぶを先に引く。** 行ごとに縁と中を交互に描くと、次の行の縁が
    前の行の字を削る。

    幅を書かなかったとき（`outline_width` が `None`）は、**縮めたあとの大きさから
    決める**。頼んだ大きさから決めると、幅に入らなくて縮んだ字に太いままの縁が
    付き、細い画が縁で埋まって字が縁の色の塊になる。
    """
    x, y, width, height = box
    vertical, horizontal = align
    lines = wrap_text(text, wrap)
    size = fit_lines(lines, font, size, width, height)
    if outline_width is None:
        outline_width = size * OUTLINE_RATIO
    ascent, descent = (value * size / 1000.0 for value in pdfmetrics.getAscentDescent(font, 1000))

    block = block_height(len(lines), font, size)
    if vertical == "top":
        top_baseline = y + height - ascent
    elif vertical == "bottom":
        top_baseline = y - descent + block - (ascent - descent)
    else:
        top_baseline = y + (height + block) / 2 - ascent

    places = []
    for index, line in enumerate(lines):
        drawn = pdfmetrics.stringWidth(line, font, size)
        if horizontal == "left":
            left = x
        elif horizontal == "right":
            left = x + width - drawn
        else:
            left = x + (width - drawn) / 2
        places.append((line, left, top_baseline - index * size * LEADING))

    if outline_width > 0:
        canvas.setLineWidth(outline_width * 2)
        canvas.setLineJoin(1)  # 角を丸める。尖ったままだと縁が角から飛び出す
        canvas.setStrokeColorRGB(*outline)
        for line, left, baseline in places:
            _write(canvas, line, font, size, left, baseline, mode=1)  # 縁だけ
    canvas.setFillColorRGB(*color)
    for line, left, baseline in places:
        _write(canvas, line, font, size, left, baseline, mode=0)  # 中だけ


def _write(canvas, text, font, size, left, baseline, mode):
    """1 行を、塗り方（縁だけ・中だけ）を決めて書く。

    塗り方は文字の並びの側にしかない指定で、Canvas からは触れない。そのため
    どちらの回も `beginText` を通す。

    **書いたら 0（中を塗る）に戻す。** 塗り方は文字の並びを閉じても PDF に
    残るのに、新しい並びは自分が 0 のつもりで始まる。戻さないと 2 回めの
    「中を塗る」が指図を出さないまま縁取りのまま描かれ、字が縁の色で
    塗り潰される。
    """
    line = canvas.beginText(left, baseline)
    line.setFont(font, size)
    if mode:
        line.setTextRenderMode(mode)
    line.textOut(text)
    if mode:
        line.setTextRenderMode(0)
    canvas.drawText(line)


class Layout:
    """紙の割り方。マスは入るだけ並べ、左右は中央に寄せる。"""

    def __init__(self, page, cell, margin, gap, title_height):
        self.page_width, self.page_height = page
        self.cell_width, self.cell_height = cell
        self.gap = gap
        self.margin = margin
        self.title_height = title_height

        usable_width = self.page_width - margin.left - margin.right
        usable_height = self.page_height - margin.top - margin.bottom - title_height
        self.columns = int((usable_width + gap) // (self.cell_width + gap))
        self.rows = int((usable_height + gap) // (self.cell_height + gap))
        if self.columns < 1 or self.rows < 1:
            raise ValueError(
                "マスが紙に入りません（"
                f"紙 {self.page_width / MM:.0f}×{self.page_height / MM:.0f}mm、"
                f"余白 縦 {(margin.top + margin.bottom) / MM:.0f}mm・"
                f"横 {(margin.left + margin.right) / MM:.0f}mm、"
                f"マス {self.cell_width / MM:.0f}×{self.cell_height / MM:.0f}mm）"
            )
        self.per_page = self.columns * self.rows
        grid_width = self.columns * self.cell_width + (self.columns - 1) * gap
        self.left = margin.left + (usable_width - grid_width) / 2
        self.top = self.page_height - margin.top - title_height

    def cell(self, index):
        """ページの中の何番目か → マスの (x, y, 幅, 高さ)。"""
        row, column = divmod(index, self.columns)
        return (
            self.left + column * (self.cell_width + self.gap),
            self.top - (row + 1) * self.cell_height - row * self.gap,
            self.cell_width,
            self.cell_height,
        )


class Section:
    """紙の上のひとまとまり。見出しと、その中の語。

    まとめて 1 つの PDF にするとき（`--merge`）、単語帳ごとに 1 つ作る。
    語は単語帳をぶら下げて持つ——絵は単語帳の中から引くので、どの冊から来た
    語なのかが分からなくなると絵が出せない。
    """

    def __init__(self, name, items):
        self.name = name
        self.items = items  # (単語帳, ことば, 読み, 絵の名前)


def selected_words(book, options):
    """刷る語。`--tag` があればそれで絞る。"""
    if not options.tag:
        return book.words
    wanted = set(options.tag)
    return [word for word in book.words if wanted & set(word[3])]


def sections_of(books, options):
    """刷る単位に割る。

    **名前を刷るなら単語帳ごと**（見出しの下から始める）、**刷らないなら 1 つに
    続ける**。名前の出ない切れ目で紙を変えても、変わったことが紙の上に何も
    残らないので、ただ空きが増える。
    """
    if options.merge and not options.title:
        return [
            Section("", [(book, *word[:3]) for book in books for word in selected_words(book, options)])
        ]
    return [
        Section(book.name, [(book, *word[:3]) for word in selected_words(book, options)])
        for book in books
    ]


def render(path, sections, options, meta):
    """PDF を 1 つ書く。`(刷った語の数, ページ数, 描けなかった絵)` を返す。

    `meta` は `(表題, 作った人, 概要)`。渡した単語帳が空になった節（`--tag` で
    全部落ちた冊）は**紙を割り当てない**。白紙が挟まるだけで、何も伝えない。
    """
    font, title_size = options.font_name, options.title_size
    title_height = band_height(title_size) if options.title else 0.0
    layout = Layout(options.page_size, options.word_size, options.margin, options.gap, title_height)

    sections = [section for section in sections if section.items]
    if not sections:
        raise ValueError("刷る語がありません")
    counts = [max(1, -(-len(section.items) // layout.per_page)) for section in sections]
    pages = sum(counts)
    words = sum(len(section.items) for section in sections)

    # ことばの大きさは **1 つの PDF につき 1 つ**決める。マスごとに決めると、絵の
    # ある語と無い語で字の大きさが変わり、同じ紙の上で見出しの大きさが揃わない。
    # 絵が出るなら添え書き、絵が無ければマスはことばのものなので大きく出す。
    inner_height = max(0.0, options.word_size[1] - content_inset(options) * 2)
    with_image = options.image and any(
        book.image_of(image) for section in sections for book, _, _, image in section.items
    )
    text_size = options.word_font_size or inner_height * (0.14 if with_image else 0.5)

    title, author, description = meta
    canvas = pdfcanvas.Canvas(path, pagesize=options.page_size)
    canvas.setTitle(title or os.path.basename(path))
    if author:
        canvas.setAuthor(author)  # 単語帳の作った人（＝著作権者）を残す（SPEC 7.4）
    if description:
        canvas.setSubject(description)

    failed = []
    number = 0  # 丁付けは PDF ぜんぶを通して数える。刷って重ねる順そのままになる
    for section, section_pages in zip(sections, counts):
        for page in range(section_pages):
            number += 1
            if options.title and section.name:
                canvas.setFillColorRGB(0, 0, 0)
                canvas.setFont(font, title_size)
                baseline = layout.page_height - options.margin.top - title_size
                canvas.drawString(layout.left, baseline, section.name)
                if pages > 1:
                    canvas.drawRightString(
                        layout.page_width - options.margin.right, baseline, f"{number} / {pages}"
                    )

            for index in range(layout.per_page):
                position = page * layout.per_page + index
                if position >= len(section.items):
                    break
                book, text, reading, image = section.items[position]
                box = layout.cell(index)
                _draw_cell(canvas, book, options, box, text_size, text, reading, image, failed)
            canvas.showPage()

    canvas.save()
    return words, pages, failed


def _draw_cell(canvas, book, options, box, size, text, reading, image, failed):
    x, y, width, height = box
    label = display_text(reading if options.word_source == "reading" else text)
    show_word = options.word and bool(label)
    vertical, horizontal = options.word_align

    # 絵の大きさは**マスいっぱいを 1.0 とする**。名前の帯を差し引いた残りを
    # 1.0 にすると、同じ 1.0 でも名前を出すかどうかで絵の大きさが変わり、
    # 「いっぱい」がどこを指すのか指定から読めなくなる。
    #
    # 縮めたぶんの空きは**名前の反対側**に出す（名前が下なら絵は上へ寄る）。
    # 真ん中に置くと空きが上下に割れて、どちらも名前 1 行ぶんに足りない。
    # 1.0 のままなら空きが無いので、名前は絵の上に重なる。
    if options.image and image:
        data = book.image_of(image)
        if data is None:
            failed.append((book.name, image, "絵が入っていません"))
        else:
            zoom = options.image_zoom
            anchor = {"bottom": "top", "top": "bottom"}.get(vertical, "middle") if show_word else "middle"
            zoomed = (
                x + width * (1 - zoom) / 2,
                _anchored(y, height, height * zoom, anchor),
                width * zoom,
                height * zoom,
            )
            try:
                draw_image(canvas, data, image, zoomed, anchor)
            except Exception as error:  # 1 枚のために止めない
                failed.append((book.name, image, str(error)))

    # 枠は絵のあとに描く。先に描くと、いっぱいに広げた絵が線の内側半分を覆う。
    if options.border:
        canvas.setStrokeColorRGB(*options.border_color)
        canvas.setLineWidth(options.border_width)
        canvas.rect(x, y, width, height)

    # 字はマスの縁から内へ入れる。マスは敷き詰めるので（--gap の既定は 0）、
    # 余白を取らないと隣のマスの字と自分の字がくっついて、どこまでが 1 語か
    # 読めなくなる。
    inset = content_inset(options)
    inner = (x + inset, y + inset, max(0.0, width - inset * 2), max(0.0, height - inset * 2))

    # 小見出し（`--word-title`）はマスの上端に置く。`{book}` は単語帳の名前に替える。
    #
    # **帯の高さは、縮めたあとの字から決める。** 頼んだ大きさから決めると、
    # 幅に入らなくて縮んだぶんだけ帯が余る。絵の無い単語帳ではことばの大きさが
    # マスの高さの半分から始まるので、余りがマスの半分に届く。
    heading = options.word_title.replace("{book}", book.name) if options.word_title else ""
    heading_size = fit_size(heading, options.font_name, options.word_title_size or size * 0.7, inner[2])
    heading_band = min(band_height(heading_size), inner[3]) if heading else 0.0
    if heading:
        _put(
            canvas,
            options,
            heading,
            heading_size,
            (inner[0], inner[1] + inner[3] - heading_band, inner[2], heading_band),
            ("top", horizontal),
        )

    if show_word:
        # 折り返すなら、残っているところぜんぶを渡す。行が増えたぶんはその中で
        # 伸びる（`--word-align` の側に寄せて積む）。
        available = max(0.0, inner[3] - heading_band)
        band = available if options.wrap.count else min(
            band_height(fit_size(label, options.font_name, size, inner[2])), available
        )
        if vertical == "top":
            # ことばは**小見出しの下**に置く。同じ上端に重ねると読めなくなる。
            band_box = (inner[0], inner[1] + inner[3] - heading_band - band, inner[2], band)
        elif vertical == "bottom":
            band_box = (inner[0], inner[1], inner[2], band)
        else:
            band_box = (inner[0], inner[1], inner[2], max(0.0, inner[3] - heading_band))
        _put(canvas, options, label, size, band_box, (vertical, horizontal), options.wrap)


def _put(canvas, options, text, size, box, align, wrap=None):
    """1 つのことばを、ことばと同じ塗り・縁取りで置く。

    縁取りの幅を省いてあるときは描く大きさから決まるので、小見出しにも同じ
    割合で付く（字が小さいほど縁も細くなる）。
    """
    draw_word(
        canvas,
        text,
        options.font_name,
        size,
        box,
        align,
        options.word_color,
        options.word_outline_color,
        options.word_outline_width,
        wrap or Wrap(0, 0),
    )


# ----------------------------------------------------------------------- 入り口


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="単語帳を紙に敷き詰めて PDF にする（SPEC 7.4）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("books", nargs="+", metavar="単語帳", help=".asodict / .yaml / フォルダ")
    parser.add_argument("-o", "--output", help="出す先。入力が 1 つのとき、または --merge のとき")
    parser.add_argument(
        "--merge", action="store_true",
        help="渡した単語帳ぜんぶを 1 つの PDF にまとめる（--output で出す先を決める）",
    )
    parser.add_argument(
        "--page-size", type=page_size, default=page_size("a4"),
        help="紙のサイズ。名前（%s）か「210mm,297mm」。既定 a4" % "/".join(PAGE_SIZES),
    )
    parser.add_argument("--landscape", action="store_true", help="紙を横にする")
    parser.add_argument(
        "--word-size", type=rect_size, default=rect_size("40mm"),
        help="マスのサイズ。「40mm,30mm」か「40mm」（正方形）。既定 40mm",
    )
    parser.add_argument(
        "--margin", type=margins, default=margins("0"),
        help="紙の余白。1 つ（上下左右）・2 つ（上下,左右）・4 つ（上,下,左,右）。"
        "既定 0（詰められるだけ詰める）。端の切れるプリンタでは足す",
    )
    parser.add_argument("--gap", type=length, default=0.0, help="マスの間。既定 0（敷き詰める）")
    parser.add_argument(
        "--padding", type=length, default=length("1mm"),
        help="マスの内側の余白。既定 1mm（敷き詰めると隣の語と字がくっつく）",
    )
    parser.add_argument("--title", type=flag, default=True, help="単語帳の名前を刷るか。既定 yes")
    parser.add_argument("--title-size", type=length, default=length("5mm"), help="名前の字の大きさ。既定 5mm")
    parser.add_argument("--image", type=flag, default=True, help="絵を描くか。既定 yes")
    parser.add_argument("--image-zoom", type=float, default=1.0, help="絵の大きさ。マスいっぱいを 1.0 とした割合。既定 1.0")
    parser.add_argument("--word", type=flag, default=True, help="ことばを描くか。既定 yes")
    parser.add_argument(
        "--word-source", choices=("text", "reading"), default="text",
        help="描くのはことばか読みか。既定 text",
    )
    parser.add_argument(
        "--word-align", type=alignment, default=alignment("bottom,center"),
        help="ことばの位置。「垂直,水平」（top/middle/bottom, left/center/right）。既定 bottom,center",
    )
    parser.add_argument(
        "--word-font-size", type=font_size, default=None,
        help="ことばの字の大きさ。既定 auto（絵があればマスの高さの 0.14 倍、無ければ 0.5 倍。"
        "入らなければ縮める）",
    )
    parser.add_argument("--word-color", type=color, default=color("0,0,0"), help="ことばの色。既定 0,0,0")
    parser.add_argument(
        "--word-wrap", type=int, default=0,
        help="ことばを何字で折り返すか。既定 0（折らずに 1 行のまま字を小さくする）",
    )
    parser.add_argument(
        "--word-wrap-min", type=int, default=0,
        help="折ったあと、最後の行がこの字数以下なら折るのをやめる。既定 0（やめない）",
    )
    parser.add_argument(
        "--word-title", default="",
        help="マスの上端に置く小見出し。`{book}` は単語帳の名前に替わる。既定は出さない",
    )
    parser.add_argument(
        "--word-title-size", type=optional_length, default=None,
        help="小見出しの字の大きさ。既定 auto（ことばの 0.7 倍）",
    )
    parser.add_argument(
        "--word-outline-width", type=optional_length, default=None,
        help="ことばの縁取りの幅。既定 auto（字の大きさの 0.08 倍）。0 で縁を取らない",
    )
    parser.add_argument(
        "--word-outline-color", type=color, default=color("255,255,255"),
        help="ことばの縁取りの色。既定 255,255,255",
    )
    parser.add_argument("--border", type=flag, default=False, help="マスに枠を描くか。既定 no")
    parser.add_argument("--border-color", type=color, default=color("0,0,0"), help="枠の色。既定 0,0,0")
    parser.add_argument("--border-width", type=length, default=length("0.1mm"), help="枠の太さ。既定 0.1mm")
    parser.add_argument("--tag", help="このタグの語だけを刷る（「,」で複数）")
    parser.add_argument(
        "--font", help="埋め込む TTF。省くと Adobe-Japan1 の HeiseiKakuGo-W5（埋め込まない）",
    )
    options = parser.parse_args(argv)

    if options.merge and not options.output:
        parser.error("--merge のときは --output で出す先を決めてください")
    if options.output and len(options.books) > 1 and not options.merge:
        parser.error("出す先が 1 つに重なります。1 つにまとめるなら --merge を付けてください")
    if options.landscape:
        width, height = options.page_size
        options.page_size = (max(width, height), min(width, height))
    if options.word_wrap < 0 or options.word_wrap_min < 0:
        parser.error("--word-wrap と --word-wrap-min は 0 以上で書いてください")
    options.wrap = Wrap(options.word_wrap, options.word_wrap_min)
    if not 0 < options.image_zoom <= 1:
        parser.error("--image-zoom は 0 より大きく 1 までで書いてください")
    options.tag = [tag.strip() for tag in options.tag.split(",") if tag.strip()] if options.tag else []
    return options


def register_font(path):
    """字を用意する。埋め込むなら TTF、省くなら Adobe-Japan1 の標準フォント。"""
    if path:
        name = os.path.splitext(os.path.basename(path))[0]
        try:
            pdfmetrics.registerFont(TTFont(name, path))
        except Exception as error:
            # OTF・一部の TTC は輪郭が CFF で、埋め込めない。どこが駄目かを言う。
            raise ValueError(f"{path}: 埋め込めません（{error}）。輪郭が TrueType の TTF が要ります")
        return name
    name = "HeiseiKakuGo-W5"
    pdfmetrics.registerFont(UnicodeCIDFont(name))
    return name


def main(argv):
    options = parse_args(argv)
    try:
        options.font_name = register_font(options.font)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    books = []
    failures = 0
    for path in options.books:
        try:
            book = read_book(path)
            if not book.words:
                raise ValueError("語が入っていません")
        except Exception as error:  # 1 冊のために止めない
            print(f"{path}: {error}", file=sys.stderr)
            failures += 1
            continue
        books.append(book)

    if not books:
        return 1

    if options.merge:
        # 作った人は、渡された冊ぜんぶで同じときだけ残す。混ざったものを 1 人の
        # 名前で出すと、出どころを取り違えたまま渡ることになる（SPEC 7.4）。
        authors = {book.author for book in books if book.author}
        meta = (
            os.path.splitext(os.path.basename(options.output))[0],
            authors.pop() if len(authors) == 1 else "",
            "",
        )
        jobs = [(options.output, books, meta)]
    else:
        jobs = [
            (
                options.output or os.path.splitext(path.rstrip(os.sep))[0] + ".pdf",
                [book],
                (book.name, book.author, book.description),
            )
            for path, book in zip(options.books, books)
        ]

    for output, group, meta in jobs:
        try:
            words, pages, failed = render(output, sections_of(group, options), options, meta)
        except Exception as error:
            print(f"{output}: {error}", file=sys.stderr)
            failures += 1
            continue

        if len(group) > 1:
            for book in group:
                print(f"  {book.name}: {len(selected_words(book, options))} 語")
        print(f"{output}: {words} 語 / {pages} ページ")
        for name, image, reason in failed:
            where = f"{name} の {image}" if len(group) > 1 else image
            print(f"  絵が描けません: {where}（{reason}）", file=sys.stderr)

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
