#!/usr/bin/env python3
# =============================================================
#  COMIC FIRST, PIXELS SECOND  (round AJ)
#
#      python3 tools/pixelate.py                 every row of data/Pixelate.csv
#      python3 tools/pixelate.py menu_hero       just that row
#
#  Your rule: draw it as a Marcinelle-school comic FIRST, then pixelate it.
#  The comic master (from Ludo.ai, or one you drew) lives in art_source/;
#  this script turns it into the pixel-art file the game uses.
#
#  ============ data/Pixelate.csv - one row per picture ============
#
#    ID         a name for the row
#    Source     the comic master, from the project folder
#    Output     where the pixel art goes (assets/...)
#    Height     how many pixels tall the pixel art is (the width follows).
#               The game then draws it 2x, 3x ... bigger, so it stays sharp.
#    Colours    how many colours it may use. Fewer = more "pixel".
#    Outline    yes = a 1-pixel black ink line all round the outside
#    Ink        how dark a colour must be to become pure black ink (0-255;
#               0 = off). Keeps the comic's black lines crisp.
#    Crop       yes = cut away the empty space round the figure first
#    Smooth     round AL: 0 = off; 5, 7, 9 = melt away the fine ink hatching
#               and paint texture BEFORE shrinking, so the pixel art comes out
#               clean and flat like hand-made pixel art (odd numbers only).
#    Aspect     round AL: e.g. 16:9 = trim the picture to that shape first
#               (from the middle) - for full-screen backgrounds. Blank = keep.
#    Widen      round AL: 1.5 = make it 1.5x wider by stretching only the
#               middle (the ends keep their shape) - for buttons and signs.
#    Neutral    round AL: 0-1. Takes the yellow "AI painting" tint out by
#               making the near-white parts truly white (1 = fully). Blank = off.
#    Flip       round AL: yes = mirror it left-right (turn a character round)
#    Fill Holes a colour (#f4f1ea) for see-through holes INSIDE the figure.
#               PixelLab's background removal sometimes eats white areas
#               that are enclosed - the white panels of a football. Blank = off.
#    Max Hole   round AL: only fill holes smaller than this % of the picture
#               (0.6 = ball panels yes, the gap between arm and body no).
#               Blank = fill every enclosed hole.
#    Notes      anything
#
#  Change a number, run it again, look in Godot.
# =============================================================

import csv
import os
import sys

from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(HERE, "data", "Pixelate.csv")
INK = (20, 14, 10)


def fill_holes(im, colour, max_percent=0.0):
    """Transparent pixels that cannot reach the edge of the picture are holes:
    paint them `colour`, fully opaque. With max_percent, only holes smaller
    than that share of the picture are filled - the white panels of a ball,
    not the gap between an arm and the body."""
    import numpy as np
    from scipy import ndimage
    a = np.array(im.getchannel("A")) > 0
    lab, n = ndimage.label(~a)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])).tolist())
    limit = (max_percent / 100.0) * a.size if max_percent else a.size
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    fill = np.zeros_like(a)
    for i, size in enumerate(sizes, start=1):
        if i not in edge and size < limit:
            fill |= lab == i
    rgb = tuple(int(colour.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    arr = np.array(im)
    arr[fill] = rgb + (255,)
    return Image.fromarray(arr, "RGBA")


def neutralise(im, strength):
    """Take the yellow (or any) colour cast out: the near-white pixels -
    clouds, white walls, foam - are made truly white, and every other colour
    shifts by the same amount. strength 0 = off, 1 = full."""
    import numpy as np
    arr = np.array(im).astype(np.float32)
    rgb, a = arr[..., :3], arr[..., 3]
    lum = rgb.mean(-1)
    spread = rgb.max(-1) - rgb.min(-1)
    pick = (a > 200) & (lum > 175) & (spread < 70)
    if pick.sum() < 200:
        return im
    white = rgb[pick].mean(0)
    gains = (white.mean() / np.maximum(white, 1.0)) ** float(strength)
    arr[..., :3] = np.clip(rgb * gains, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def pixelate(src, height, colours, outline, ink, crop, holes="", smooth=0, max_hole=0.0, aspect="", flip=False, widen=1.0, neutral=0.0):
    im = Image.open(src).convert("RGBA")
    if neutral:
        im = neutralise(im, neutral)
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if aspect and ":" in aspect:
        aw, ah = (float(x) for x in aspect.split(":"))
        want = aw / ah
        if im.width / im.height > want:
            w = round(im.height * want)
            x = (im.width - w) // 2
            im = im.crop((x, 0, x + w, im.height))
        else:
            h = round(im.width / want)
            y = (im.height - h) // 2
            im = im.crop((0, y, im.width, y + h))
    if smooth and smooth > 1:
        a = im.getchannel("A")
        im = im.convert("RGB").filter(ImageFilter.MedianFilter(int(smooth) | 1)).convert("RGBA")
        im.putalpha(a)
    if holes:
        im = fill_holes(im, holes, max_hole)
    if crop:
        # Only count pixels that are really there (AI paintings leave faint haze).
        box = im.getchannel("A").point(lambda v: 255 if v > 110 else 0).getbbox()
        if box:
            im = im.crop(box)
    if widen and widen != 1.0:
        # Stretch only the MIDDLE, so corners and end ornaments keep their shape.
        w, h = im.size
        a, b = int(w * 0.3), int(w * 0.7)
        mid = im.crop((a, 0, b, h)).resize((max(1, int((b - a) + w * (widen - 1.0))), h), Image.LANCZOS)
        out = Image.new("RGBA", (a + mid.width + (w - b), h))
        out.paste(im.crop((0, 0, a, h)), (0, 0))
        out.paste(mid, (a, 0))
        out.paste(im.crop((b, 0, w, h)), (a + mid.width, 0))
        im = out
    width = max(1, round(im.width * height / im.height))
    # Shrink in two steps (box, then lanczos) so thin ink lines survive.
    mid = im.resize((width * 2, height * 2), Image.BOX)
    small = mid.resize((width, height), Image.LANCZOS)
    alpha = small.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    # Flatten onto mid-grey so transparent edges do not pull colours to black.
    flat = Image.new("RGBA", small.size, (128, 128, 128, 255))
    flat.alpha_composite(small)
    rgb = flat.convert("RGB").quantize(colors=colours, method=Image.Quantize.FASTOCTREE,
                                       kmeans=4, dither=Image.Dither.NONE).convert("RGB")
    px = rgb.load()
    if ink > 0:
        for y in range(rgb.height):
            for x in range(rgb.width):
                r, g, b = px[x, y]
                if (r + g + b) / 3 < ink:
                    px[x, y] = INK
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    if outline:
        ap = alpha.load()
        op = out.load()
        for y in range(out.height):
            for x in range(out.width):
                if ap[x, y] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        X, Y = x + dx, y + dy
                        if 0 <= X < out.width and 0 <= Y < out.height and ap[X, Y] == 255:
                            op[x, y] = INK + (255,)
                            break
    return out


def main():
    only = sys.argv[1:]
    with open(SHEET, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rid = (row.get("ID") or "").strip()
            if not rid or (only and rid not in only):
                continue
            src = os.path.join(HERE, row["Source"].strip())
            dst = os.path.join(HERE, row["Output"].strip())
            if not os.path.isfile(src):
                print("  ! %s: no comic master at %s" % (rid, row["Source"]))
                continue
            out = pixelate(src, int(float(row.get("Height") or 160)), int(float(row.get("Colours") or 32)),
                           (row.get("Outline") or "yes").strip().lower() == "yes",
                           int(float(row.get("Ink") or 60)), (row.get("Crop") or "yes").strip().lower() == "yes",
                           (row.get("Fill Holes") or "").strip(), int(float(row.get("Smooth") or 0)), float(row.get("Max Hole") or 0),
                           (row.get("Aspect") or "").strip(), (row.get("Flip") or "").strip().lower() == "yes",
                           float(row.get("Widen") or 1.0), float(row.get("Neutral") or 0))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            out.save(dst)
            print("  %s: %s -> %s (%dx%d, %s colours)" % (rid, row["Source"], row["Output"], out.width, out.height, row.get("Colours")))


if __name__ == "__main__":
    main()
