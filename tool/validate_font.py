"""出力したフォントを fontTools で外部検証する。

Dart 側のテストは自前の実装で自前の出力を読むため、規格の解釈を誤っていても
気づけない。ここでは第三者の実装に読ませて、実際に使えるフォントかを確かめる。

    flutter test test/font/font_builder_test.dart   # build/font_samples/ に出力
    python3 -m venv .venv && .venv/bin/pip install fonttools
    .venv/bin/python tool/validate_font.py

fontTools はこのプロジェクトの依存ではない。検証時にだけ用意すればよい。
"""
import math
import sys
from io import BytesIO

from fontTools.ttLib import TTFont
from fontTools.pens.areaPen import AreaPen
from fontTools.pens.boundsPen import BoundsPen

# 期待値は test/font/font_builder_test.dart のサンプルグリフに対応する。
RECT_AREA = 400 * 700
CIRCLE_RADIUS = 350
RING_INNER_RADIUS = 180

# 円を 3 次ベジェ 4 本で近似する古典的な手法（k=0.5523）の固有誤差は面積比で
# 約 0.03%。CFF はこの曲線をそのまま書けるため、この程度しかずれない。
OTF_AREA_TOLERANCE = 0.001

# TrueType は 2 次ベジェへの近似（許容誤差 0.5 単位）と整数座標への丸めが加わる。
# 半径方向に d ずれると面積は 2*pi*r*d 変わるため、上界は 2*pi*350*0.5 / 面積。
TTF_AREA_TOLERANCE = 2 * math.pi * CIRCLE_RADIUS * 0.5 / (math.pi * CIRCLE_RADIUS ** 2)

FAILURES = []


def check(label, condition, detail=""):
    mark = "OK  " if condition else "FAIL"
    if not condition:
        FAILURES.append(label)
    print(f"  [{mark}] {label}" + (f"  {detail}" if detail else ""))


def validate(path, expect_cff):
    print(f"\n=== {path} ===")
    area_tolerance = OTF_AREA_TOLERANCE if expect_cff else TTF_AREA_TOLERANCE
    font = TTFont(path)

    check("sfnt が解析できる", True, f"sfntVersion={font.sfntVersion!r}")
    check(
        "CFF/glyf の別が正しい",
        ("CFF " in font) == expect_cff and ("glyf" in font) != expect_cff,
        f"tables={sorted(font.keys())}",
    )

    # XML への書き出し。テーブルの内部整合が取れていないとここで落ちる。
    buf = BytesIO()
    try:
        font.saveXML(buf)
        xml_ok = len(buf.getvalue()) > 0
    except Exception as exc:  # noqa: BLE001
        xml_ok = False
        print(f"        saveXML: {exc}")
    check("ttx への書き出しが通る", xml_ok)

    # バイナリ再保存。fontTools がテーブルを再構築できるかを見る。
    out = BytesIO()
    try:
        font.save(out)
        TTFont(BytesIO(out.getvalue()))
        resave_ok = True
    except Exception as exc:  # noqa: BLE001
        resave_ok = False
        print(f"        save: {exc}")
    check("fontTools が再保存できる", resave_ok)

    head = font["head"]
    check("unitsPerEm", head.unitsPerEm == 1000, f"={head.unitsPerEm}")
    check("magicNumber", head.magicNumber == 0x5F0F3CF5)

    cmap = font.getBestCmap()
    for cp in (0x41, 0x3042, 0x30A2, 0x20):
        check(f"cmap に U+{cp:04X}", cp in cmap)
    check("未収集の U+3044 は無い", 0x3044 not in cmap)

    order = font.getGlyphOrder()
    check(".notdef が 0 番", order[0] == ".notdef", f"order[:4]={order[:4]}")

    glyphset = font.getGlyphSet()
    hmtx = font["hmtx"]

    def area_of(cp):
        pen = AreaPen(glyphset)
        glyphset[cmap[cp]].draw(pen)
        return pen.value

    def bounds_of(cp):
        pen = BoundsPen(glyphset)
        glyphset[cmap[cp]].draw(pen)
        return pen.bounds

    def check_area(label, cp, expected, tolerance):
        got = abs(area_of(cp))
        check(
            label,
            abs(got - expected) / expected < tolerance,
            f"={got:.1f} 期待={expected:.1f} 差={abs(got - expected) / expected * 100:.3f}%"
            f" 許容={tolerance * 100:.3f}%",
        )

    # 直線のみの矩形 (50,0)-(450,700)。丸めも近似も入らないため厳密に一致する。
    check("A の送り幅", hmtx[cmap[0x41]][0] == 500, f"={hmtx[cmap[0x41]][0]}")
    check("A の境界", bounds_of(0x41) == (50, 0, 450, 700), f"={bounds_of(0x41)}")
    check("A の面積", abs(abs(area_of(0x41)) - RECT_AREA) < 1, f"={abs(area_of(0x41)):.1f}")

    check_area("あ の面積が円に一致", 0x3042, math.pi * CIRCLE_RADIUS ** 2, area_tolerance)
    check("あ の送り幅", hmtx[cmap[0x3042]][0] == 1000)

    # 穴あき。外周と内周の巻き方向が逆でなければ面積が合わない。
    check_area(
        "ア の面積が穴あきになる",
        0x30A2,
        math.pi * (CIRCLE_RADIUS ** 2 - RING_INNER_RADIUS ** 2),
        area_tolerance,
    )

    # TrueType は外周が時計回り（y 上向きで負の面積）、CFF は反時計回りが慣習。
    signed = area_of(0x3042)
    if expect_cff:
        check("CFF の外周は反時計回り", signed > 0, f"signedArea={signed:.1f}")
    else:
        check("TrueType の外周は時計回り", signed < 0, f"signedArea={signed:.1f}")

    name = font["name"]
    check("name の Family", name.getDebugName(1) == "AsoGlyph Sample",
          f"={name.getDebugName(1)!r}")
    check("name の PostScript 名", name.getDebugName(6) == "AsoGlyphSample-Regular",
          f"={name.getDebugName(6)!r}")
    check("name の URL", name.getDebugName(11) == "https://sharkpp.net",
          f"={name.getDebugName(11)!r}")

    os2 = font["OS/2"]
    check("OS/2 のかな範囲ビット", bool(os2.ulUnicodeRange2 & (1 << (49 - 32))),
          f"range2=0x{os2.ulUnicodeRange2:08X}")
    check("OS/2 の日本語コードページ", bool(os2.ulCodePageRange1 & (1 << 17)))


def validate_handwriting():
    """ラスタトレースを通したグリフ。L1 の縦断が実際のフォントになるかを見る。"""
    print("\n=== build/font_samples/handwriting.{ttf,otf} ===")
    areas = {}
    for kind, cff in (("ttf", False), ("otf", True)):
        path = f"build/font_samples/handwriting.{kind}"
        font = TTFont(path)
        check(f"{kind}: 解析できる", ("CFF " in font) == cff)

        out = BytesIO()
        try:
            font.save(out)
            TTFont(BytesIO(out.getvalue()))
            ok = True
        except Exception as exc:  # noqa: BLE001
            ok = False
            print(f"        save: {exc}")
        check(f"{kind}: 再保存できる", ok)

        cmap = font.getBestCmap()
        check(f"{kind}: U+3042 が引ける", 0x3042 in cmap)

        glyphset = font.getGlyphSet()
        pen = AreaPen(glyphset)
        glyphset[cmap[0x3042]].draw(pen)
        areas[kind] = abs(pen.value)

        bpen = BoundsPen(glyphset)
        glyphset[cmap[0x3042]].draw(bpen)
        check(f"{kind}: 境界が妥当", bpen.bounds is not None
              and 150 < bpen.bounds[0] < 200 and 800 < bpen.bounds[2] < 860,
              f"={bpen.bounds}")

    # 長さ 600・幅 56 の帯に半径 28 の半円が両端。
    expected = 600 * 56 + math.pi * 28 ** 2
    for kind, area in areas.items():
        check(f"{kind}: 面積が運筆と一致", abs(area - expected) / expected < 0.05,
              f"={area:.0f} 期待={expected:.0f}")
    check("TTF と OTF の字形が一致",
          abs(areas["ttf"] - areas["otf"]) / areas["otf"] < 0.005,
          f"ttf={areas['ttf']:.0f} otf={areas['otf']:.0f}")


validate("build/font_samples/sample.ttf", expect_cff=False)
validate("build/font_samples/sample.otf", expect_cff=True)
validate_handwriting()

print()
if FAILURES:
    print(f"失敗 {len(FAILURES)} 件: " + ", ".join(FAILURES))
    sys.exit(1)
print("すべて通過")
