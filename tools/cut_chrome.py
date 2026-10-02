#!/usr/bin/env python3
# =============================================================
#  CUT THE PIXELLAB CHROME INTO GAME FILES  (round X)
#
#      python3 tools/cut_chrome.py
#
#  PixelLab's UI tool hands back a whole SHEET of panels, not one 96x96
#  nine-slice. This turns those sheets into the eight files in assets/ui/,
#  following three columns of data/ArtOrders.csv:
#
#      Sheet    the PNG in art_source/pixellab/ to cut from
#      Cut      which piece of it:  x y width height corner
#               "16 190 151 45 22" = the piece at 16,190 that is 151x45,
#               keeping its 22px corners
#      Finish   what to do to it afterwards (the list is below)
#
#  So the day you regenerate the panel in PixelLab, the loop is:
#      1. save the new sheet over art_source/pixellab/01_panel_sheet.png
#      2. if the piece moved, change its Cut cell
#      3. run this
#
#  ============ THE FINISHES ============
#
#      plain        cut it and rebuild it as a 96x96 nine-slice, nothing else
#      light        ...and LIFT it for tinting. The panel is tinted by every
#                   screen with its own colour and tinting MULTIPLIES, so
#                   dark walnut came out nearly black. Black ink stays black;
#                   wood and brass are lifted so each screen's colour lands.
#      dark-centre  ...and paint the opening dark. The window came back cream.
#      lit:<ID>     the same file as order <ID>, under a lamp (button hover)
#      pressed:<ID> the same file as order <ID>, pushed in a pixel and darker
#      reduce       a PAINTED sheet (not pixel art) shrunk to 96x96 and snapped
#                   to the palette. The beer mat.
#      bar-back /   the two 32x32 bar tiles, built from PixelLab's own colours
#      bar-fill     (the rack and the stein), because the sheet's rounded rack
#                   turned into a blob when cut to 32 pixels.
#
#  THE ONE RULE: detail stays inside the corner. The middle is made flat on
#  purpose - anything there is stretched into a smear on a wide panel.
# =============================================================

import csv
import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
import colorsys
import os
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:
    print("This needs Pillow.  pip install pillow")
    sys.exit(1)

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORDERS = os.path.join(HERE, "data", "ArtOrders.csv")
SHEETS = os.path.join(HERE, "art_source", "pixellab")
OUT = os.path.join(HERE, "assets", "ui")
SIZE = 96


# -------------------------------------------------------------
#  nine-slice rebuild
# -------------------------------------------------------------

def rebuild(src, corner, out=SIZE, flat=None, flat_from=None):
    """Keep the corners, run the middle row/column along the edges."""
    w, h = src.size
    p = src.load()

    def m(v, n):
        if v < corner:
            return v
        if v >= out - corner:
            return n - (out - v)
        return n // 2

    img = Image.new("RGBA", (out, out))
    o = img.load()
    for y in range(out):
        for x in range(out):
            o[x, y] = p[m(x, w), m(y, h)]
    if flat is not None:
        f = corner if flat_from is None else flat_from
        for y in range(f, out - f):
            for x in range(f, out - f):
                o[x, y] = flat
    return img


def most_common(img, box):
    return Counter(img.crop(box).getdata()).most_common(1)[0][0]


def field_of(piece, corner):
    """The commonest colour on the plaque's face, clear of the corners."""
    return most_common(piece, (corner * 2 + 8, corner - 6, corner * 2 + 38, corner + 4))


# -------------------------------------------------------------
#  finishes
# -------------------------------------------------------------

def lift_for_tint(img):
    out = img.copy()
    p = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = p[x, y]
            if a == 0:
                continue
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum < 22:
                continue                      # ink stays ink
            t = min(1.0, (lum - 22) / 170.0)
            v = 150 + 105 * (t ** 0.55)
            s = 0.18                          # keep a little of the hue
            p[x, y] = (min(255, int(v * (1 - s) + r * s * 1.6)),
                       min(255, int(v * (1 - s) + g * s * 1.6)),
                       min(255, int(v * (1 - s) + b * s * 1.6)), a)
    return out


def recolour(img, fn):
    out = img.copy()
    p = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = p[x, y]
            if a == 0 or (r + g + b) < 40:
                continue
            p[x, y] = fn(r, g, b) + (a,)
    return out


def lit(r, g, b):
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if s > 0.6 and l > 0.45:
        l = min(0.85, l + 0.10)               # brass gets hotter
        h = max(0, h + 0.01)
    else:
        l = min(0.9, l * 1.28)                # wood under a lamp
    return tuple(int(v * 255) for v in colorsys.hls_to_rgb(h, l, s))


def pressed(img):
    out = recolour(img, lambda r, g, b: (int(r * 0.78), int(g * 0.76), int(b * 0.76)))
    inner = out.crop((6, 6, 90, 89))
    out.paste(inner, (6, 7))                  # the face sits a pixel lower
    return out


def reduce_painted(sheet):
    import numpy as np
    a = np.array(sheet)[:, :, 3]
    rows = np.where(a.max(1) > 0)[0]
    cols = np.where(a.max(0) > 0)[0]
    mat = sheet.crop((cols.min(), rows.min(), cols.max() + 1, rows.max() + 1))
    small = mat.resize((SIZE, SIZE), Image.BOX)
    pal = [(25, 17, 10), (243, 232, 212), (230, 221, 200), (90, 147, 204), (150, 116, 47), (255, 255, 255)]
    cream = (243, 232, 212, 255)
    ink = (25, 17, 10, 255)
    p = small.load()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, al = p[x, y]
            if al < 128:
                p[x, y] = (0, 0, 0, 0)
                continue
            best = min(pal, key=lambda c: (c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2)
            p[x, y] = cream if best == (255, 255, 255) else best + (255,)
    for y in range(27, 69):                   # tidy specks in the plain middle
        for x in range(10, 86):
            if p[x, y] == ink:
                n = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if p[x + dx, y + dy] == ink)
                if n <= 1:
                    p[x, y] = cream
    return small


INK = (6, 2, 1, 255)
WOOD = (84, 48, 29, 255)
WOOD_D = (59, 33, 22, 255)
WOOD_L = (110, 64, 38, 255)
BRASS = (237, 169, 52, 255)
BRASS_L = (246, 214, 140, 255)
FOAM = (242, 228, 201, 255)
FOAM_E = (221, 163, 80, 255)
AMBER = (237, 169, 52, 255)
AMBER_H = (246, 196, 104, 255)
AMBER_D = (201, 128, 38, 255)


def bar_back():
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    p = img.load()
    for y in range(32):
        for x in range(32):
            if x in (0, 31) and y in (0, 31):
                continue
            edge = min(x, y, 31 - x, 31 - y)
            if edge == 0:
                p[x, y] = INK
            elif edge == 1:
                p[x, y] = WOOD_L if y < 16 else WOOD
            elif edge <= 3:
                p[x, y] = WOOD
            elif edge == 4:
                p[x, y] = INK
            else:
                p[x, y] = WOOD_D
    for x, y in [(2, 2), (29, 2), (2, 29), (29, 29)]:
        p[x, y] = BRASS
    for x, y in [(2, 2), (29, 2)]:
        p[x, y] = BRASS_L
    return img


def bar_fill():
    img = Image.new("RGBA", (32, 32))
    p = img.load()
    for y in range(32):
        if y in (0, 31):
            c = INK
        elif y <= 7:
            c = FOAM
        elif y == 8:
            c = FOAM_E
        elif y == 11:
            c = AMBER_H
        elif y >= 27:
            c = AMBER_D
        else:
            c = AMBER
        for x in range(32):
            p[x, y] = c
    for x, y in [(5, 16), (13, 21), (22, 14), (27, 23), (9, 25), (18, 18)]:
        p[x, y] = AMBER_H
    return img


# -------------------------------------------------------------
#  the orders
# -------------------------------------------------------------

def cut_piece(sheet_name, cut_text):
    sheet = Image.open(os.path.join(SHEETS, sheet_name)).convert("RGBA")
    bits = [int(b) for b in cut_text.replace(",", " ").split()]
    if len(bits) < 5:
        raise ValueError("Cut needs five numbers: x y width height corner")
    x, y, w, h, corner = bits[:5]
    return sheet, sheet.crop((x, y, x + w, y + h)), corner


def main():
    if not os.path.exists(ORDERS):
        print("No data/ArtOrders.csv beside this script. Run it from the project folder.")
        return 1
    with open(ORDERS, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    made = {}
    waiting = []
    for row in rows:
        finish = (row.get("Finish") or "").strip()
        if not finish:
            continue
        waiting.append(row)

    # Plain cuts first, so lit:/pressed: have something to start from.
    waiting.sort(key=lambda r: 1 if (r.get("Finish") or "").startswith(("lit:", "pressed:")) else 0)
    for row in waiting:
        oid = row["ID"].strip()
        finish = row["Finish"].strip()
        goes = row["Goes To"].split("+")[0].strip()
        try:
            if finish == "bar-back":
                img = bar_back()
            elif finish == "bar-fill":
                img = bar_fill()
            elif finish == "reduce":
                img = reduce_painted(Image.open(os.path.join(SHEETS, row["Sheet"].strip())).convert("RGBA"))
            elif finish.startswith(("lit:", "pressed:")):
                base = made.get(finish.split(":", 1)[1].strip())
                if base is None:
                    print("   %-16s SKIPPED - order %s was not cut" % (oid, finish.split(":", 1)[1]))
                    continue
                img = recolour(base, lit) if finish.startswith("lit:") else pressed(base)
            else:
                sheet, piece, corner = cut_piece(row["Sheet"].strip(), row["Cut"])
                if finish == "dark-centre":
                    img = rebuild(piece, corner)
                    p = img.load()
                    dark = (26, 18, 11, 255)
                    for y in range(SIZE):
                        for x in range(SIZE):
                            r, g, b, a = p[x, y]
                            if 18 < x < 78 and 18 < y < 78 and r > 200 and g > 180:
                                p[x, y] = dark
                    img = rebuild(img, corner, flat=dark, flat_from=28)
                elif finish == "plain-button":
                    img = rebuild(piece, corner, flat=field_of(piece, corner), flat_from=corner)
                else:
                    flat = most_common(piece, (corner + 8, corner // 2 + 4, piece.width - corner - 8,
                                               piece.height - corner // 2 - 4)) \
                        if piece.width > 2 * corner + 16 and piece.height > corner + 8 else None
                    img = rebuild(piece, corner, flat=flat, flat_from=28)
                    if finish == "light":
                        img = lift_for_tint(img)
        except (OSError, ValueError, KeyError) as problem:
            print("   %-16s FAILED - %s" % (oid, problem))
            continue
        made[oid] = img
        img.save(os.path.join(HERE, goes))
        print("   %-16s -> %s   (%dx%d, %s)" % (oid, goes, img.width, img.height, finish))

    print("")
    print("%d file(s) written. Open the game and look before you push." % len(made))
    return 0


if __name__ == "__main__":
    sys.exit(main())
