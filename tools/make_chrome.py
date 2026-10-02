#!/usr/bin/env python3
# =============================================================
#  THE NINE-SLICE CHROME, DRAWN FROM YOUR PALETTE
#
#  ============ WHAT THIS IS, AND WHAT IT IS NOT ============
#
#  It is the seven files in assets/ui/ that dress every screen in the game —
#  drawn here, in code, from the colours in data/Theme.csv. Change a palette
#  row, run this, and every panel, button and window in the game changes.
#
#  IT IS NOT A SUBSTITUTE FOR DRAWING THEM. PixelLab orders 1-7 in
#  data/ArtOrders.csv will do this better, with a hand-inked line and real
#  wood grain. What this gives you is a WORKING SET IN THE RIGHT PALETTE
#  TODAY, and something to edit rather than a blank canvas — which is how you
#  said you like to work.
#
#  ============ THE RULE THAT SHAPES EVERY ONE OF THEM ============
#
#  These are NINE-SLICE. The four corners are kept at their drawn size, the
#  four edges are stretched along their run, and the middle is stretched to
#  fill. So:
#
#      DETAIL GOES IN THE CORNERS. Anything in the middle is stretched into a
#      smear the moment a panel is wider than 96 pixels, and anything on an
#      edge is stretched along that edge.
#
#  That is why the centres here are FLAT. It is not laziness — a wood grain
#  in the middle of a nine-slice is a wood grain you will see pulled into
#  spaghetti across the first wide panel you draw. The grain lives in the
#  corners, where it is safe.
#
#  ============ MARCINELLE, IN PIXELS ============
#
#      1px pure-black outline, closed all the way round
#      flat fills, two or three tones a shape, no gradients
#      one hot accent and nothing else bright
#
#  ============ RUNNING IT ============
#
#      python3 tools/make_chrome.py
#
#  From the project folder. It reads data/Theme.csv, writes assets/ui/, and
#  prints what it did. Needs Pillow:  pip install pillow
# =============================================================

import csv
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("This needs Pillow.  pip install pillow")
    sys.exit(1)

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEME = os.path.join(HERE, "data", "Theme.csv")
OUT = os.path.join(HERE, "assets", "ui")

BLACK = (0, 0, 0, 255)


# -------------------------------------------------------------
#  THE PALETTE, OUT OF Theme.csv
# -------------------------------------------------------------

def read_palette():
    """Every `colour x` row of Theme.csv, as {name: (r,g,b,a)}."""
    out = {}
    with open(THEME, encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            el = (row.get("Element") or "").strip().lower()
            if not el.startswith("colour "):
                continue
            out[el[7:].strip()] = hex_to_rgb((row.get("Fill") or "").strip())
    return out


def hex_to_rgb(text, fallback=(128, 128, 128, 255)):
    text = (text or "").strip().lstrip("#")
    if len(text) not in (6, 8):
        return fallback
    try:
        bits = [int(text[i:i + 2], 16) for i in range(0, len(text), 2)]
    except ValueError:
        return fallback
    if len(bits) == 3:
        bits.append(255)
    return tuple(bits)


def shade(colour, by):
    """Lighter (by > 0) or darker (by < 0). Marcinelle uses two or three
    tones a shape and never a gradient, so this is only ever called a couple
    of times per drawing."""
    r, g, b, a = colour
    if by >= 0:
        f = by
        return (int(r + (255 - r) * f), int(g + (255 - g) * f), int(b + (255 - b) * f), a)
    f = -by
    return (int(r * (1 - f)), int(g * (1 - f)), int(b * (1 - f)), a)


# -------------------------------------------------------------
#  THE PIECES
# -------------------------------------------------------------

def frame(size, fill, edge, inset_rule=None, outline=BLACK):
    """A box: black outline, a flat fill, and optionally a thin coloured rule
    set in from the edge. The bones of every one of these files."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, size - 1, size - 1], fill=fill, outline=outline, width=1)
    # THE EDGE IS TWO PIXELS IN FROM THE OUTLINE, so the outline stays pure
    # black and reads at any size. One pixel and they blend.
    d.rectangle([2, 2, size - 3, size - 3], outline=edge, width=2)
    if inset_rule is not None:
        d.rectangle([5, 5, size - 6, size - 6], outline=inset_rule, width=1)
    return img


def grain(img, slice_px, colour, rows=3):
    """A few short horizontal strokes, IN THE CORNERS ONLY.

    This is the whole nine-slice discipline in one function: a stroke drawn
    inside `slice_px` of a corner is kept at its drawn size whatever the panel
    grows to. A stroke one pixel further in is stretched into a smear."""
    d = ImageDraw.Draw(img)
    w, h = img.size
    for i in range(rows):
        y = 8 + i * 5
        d.line([(7, y), (slice_px - 4, y)], fill=colour, width=1)
        d.line([(w - slice_px + 3, y), (w - 8, y)], fill=colour, width=1)
        d.line([(7, h - 1 - y), (slice_px - 4, h - 1 - y)], fill=colour, width=1)
        d.line([(w - slice_px + 3, h - 1 - y), (w - 8, h - 1 - y)], fill=colour, width=1)


def studs(img, slice_px, colour, at=9, r=3):
    """Four round brass studs, one per corner, INSIDE the slice border.

    Outside it they stretch with the edges and smear across a wide window —
    which is the single easiest nine-slice mistake to make and the one worth
    checking for first on anything PixelLab returns."""
    d = ImageDraw.Draw(img)
    w, h = img.size
    dark = shade(colour, -0.45)
    for cx, cy in [(at, at), (w - 1 - at, at), (at, h - 1 - at), (w - 1 - at, h - 1 - at)]:
        assert cx < slice_px and cy < slice_px or cx > w - slice_px or cy > h - slice_px
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=colour, outline=BLACK)
        d.point((cx - 1, cy - 1), fill=shade(colour, 0.5))
        d.point((cx + 1, cy + 1), fill=dark)


def bevel(img, light, dark, flipped=False):
    """Lit from above, or pushed in. Two lines, which is all a bevel is when
    you are not allowed gradients."""
    d = ImageDraw.Draw(img)
    w, h = img.size
    top, bottom = (dark, light) if flipped else (light, dark)
    d.line([(3, 3), (w - 4, 3)], fill=top, width=1)
    d.line([(3, 3), (3, h - 4)], fill=top, width=1)
    d.line([(3, h - 4), (w - 4, h - 4)], fill=bottom, width=1)
    d.line([(w - 4, 3), (w - 4, h - 4)], fill=bottom, width=1)


def lozenge(img, slice_px, blue, cream, band=9):
    """The blue-and-white Bavarian lozenge, along the top and bottom.

    Drawn as whole diamonds that happen to tile — so when the edge stretches
    the pattern repeats cleanly instead of shearing."""
    d = ImageDraw.Draw(img)
    w, h = img.size
    for y0 in (3, h - 3 - band):
        d.rectangle([3, y0, w - 4, y0 + band], fill=cream)
        step = band
        x = 3
        while x < w - 4:
            mid = y0 + band // 2
            d.polygon([(x, mid), (x + step // 2, y0), (x + step, mid),
                       (x + step // 2, y0 + band)], fill=blue)
            x += step
        d.rectangle([3, y0, w - 4, y0 + band], outline=BLACK, width=1)


# -------------------------------------------------------------
#  THE SEVEN FILES
# -------------------------------------------------------------

def build(pal):
    oak = pal.get("background", (25, 17, 10, 255))
    wood = pal.get("panel", (58, 36, 21, 255))
    brass = pal.get("accent", (242, 179, 61, 255))
    cream = pal.get("text", (243, 232, 212, 255))
    blue = pal.get("defend", (90, 147, 204, 255))
    slot_c = pal.get("slot_empty", (76, 47, 28, 255))

    made = []

    # ---- 1. panel. THE MOST IMPORTANT FILE: every box goes through it ----
    img = frame(96, wood, shade(brass, -0.35), inset_rule=shade(wood, 0.12))
    grain(img, 28, shade(wood, -0.18))
    made.append(("beerhall_panel.png", img, 28))

    # ---- 2. window. Dark oak, brass border, four studs ----
    img = frame(96, oak, brass, inset_rule=shade(brass, -0.5))
    grain(img, 28, shade(oak, 0.10))
    studs(img, 28, brass)
    made.append(("beerhall_window.png", img, 28))

    # ---- 3-5. the button, in its three states ----
    img = frame(96, wood, shade(brass, -0.2))
    bevel(img, shade(wood, 0.22), shade(wood, -0.3))
    grain(img, 26, shade(wood, -0.14), rows=2)
    made.append(("beerhall_button.png", img, 26))

    lit = shade(wood, 0.26)
    img = frame(96, lit, brass)
    bevel(img, shade(lit, 0.22), shade(lit, -0.28))
    grain(img, 26, shade(lit, -0.14), rows=2)
    made.append(("beerhall_button_hover.png", img, 26))

    low = shade(wood, -0.22)
    img = frame(96, low, shade(brass, -0.45))
    bevel(img, shade(low, 0.2), shade(low, -0.3), flipped=True)
    made.append(("beerhall_button_pressed.png", img, 26))

    # ---- 6. slot. THE ONE LIGHT SURFACE in the game ----
    img = frame(96, cream, shade(brass, -0.3))
    lozenge(img, 28, blue, shade(cream, 0.4))
    made.append(("beerhall_slot.png", img, 28))

    # ---- 7. the two bars, at 32 ----
    img = frame(32, shade(oak, -0.25), shade(brass, -0.55))
    made.append(("beerhall_bar_back.png", img, 10))

    img = frame(32, brass, shade(brass, 0.45))
    d = ImageDraw.Draw(img)
    # the head on the beer: one lighter band along the top, inside the slice
    d.rectangle([3, 3, 28, 7], fill=shade(brass, 0.6), outline=BLACK, width=1)
    made.append(("beerhall_bar_fill.png", img, 10))

    return made


def main():
    if not os.path.exists(THEME):
        print("No data/Theme.csv beside this script. Run it from the project folder.")
        return 1
    pal = read_palette()
    if not pal:
        print("Theme.csv has no `colour x` rows — nothing to draw from.")
        return 1

    # ============ ROUND X: THE PIXELLAB ART IS IN ============
    #
    # assets/ui/ now holds the PixelLab chrome, cut by tools/cut_chrome.py.
    # Running this would paint the placeholders straight over it. So it
    # refuses, unless you ask for the placeholders on purpose:
    #
    #     python3 tools/make_chrome.py --placeholders
    #
    if os.path.isdir(os.path.join(HERE, "art_source", "pixellab")) and "--placeholders" not in sys.argv:
        print("assets/ui/ holds the PixelLab chrome now (see art_source/pixellab/).")
        print("To redo it from the PixelLab sheets:   python3 tools/cut_chrome.py")
        print("To go back to these drawn placeholders: python3 tools/make_chrome.py --placeholders")
        return 0

    os.makedirs(OUT, exist_ok=True)
    print("palette read from data/Theme.csv:")
    for key in ("background", "panel", "accent", "text", "defend"):
        if key in pal:
            print("   %-12s #%02x%02x%02x" % ((key,) + pal[key][:3]))
    print("")

    for name, img, slice_px in build(pal):
        path = os.path.join(OUT, name)
        img.save(path)
        print("   %-32s %dx%d   slice %d" % (name, img.width, img.height, slice_px))

    print("")
    print("Seven files written to assets/ui/.")
    print("Theme.csv already points at them, so the game picks them up on the")
    print("next run — nothing else to change.")
    print("")
    print("THE SLICE NUMBERS ABOVE MUST MATCH the Slice column of Theme.csv:")
    print("   panel 28 · window 28 · button 26 · slot 28 · bars 10")
    return 0


if __name__ == "__main__":
    sys.exit(main())
