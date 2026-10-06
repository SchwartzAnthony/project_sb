#!/usr/bin/env python3
# =============================================================
#  THE PITCH  (round AH, art phase A1 - ArtOrders.csv order 11)
#
#      python3 tools/make_pitch.py
#
#  PixelLab draws the GRASS (art_source/pixellab/11_pitch_grass.png - no
#  lines on it, on purpose). This script draws the LINES on top, exactly
#  where the game measures them from:
#
#      pitch_inset_x / pitch_inset_y in data/Tuning.csv
#
#  A generated picture never puts its lines where the game measures; a ruler
#  does. Then it adds the goals and writes assets/field/soccerfield.png at
#  2560 x 1440 (Stadium.csv).
#
#  ROUND AN (village ground): THE LINES ARE THE EDGE OF THE PLAYER ZONES.
#  The zones are the first camera view (the window, 1920 x 1080, centred on
#  the picture) shrunk by pitch_inset_x / pitch_inset_y - NOT the whole
#  picture shrunk by them, which is where the old lines were drawn (far
#  outside the zones). Only a strip of run-off grass (RUNOFF) goes round the
#  lines; everything else is see-through, so the village behind it
#  (tools/make_village.py, Stadium.csv background and crowd) shows.
#
#  Everything is drawn on a 1280 x 720 grid and blown up x2 with no
#  smoothing, so it stays crisp pixel art like the rest of the game.
#
#  Change a colour or a size below and run it again. Regenerate the grass in
#  PixelLab, save it over the old one, and run it again - that is the loop.
# =============================================================

import csv
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRASS = os.path.join(HERE, "art_source", "pixellab", "11_pitch_grass.png")
OUT = os.path.join(HERE, "assets", "field", "soccerfield.png")

# 1280x720 x2 = 2560x1440. (Round AH tried 640x360 x4 first: in a match
# the camera is close enough that its pixels were four times the size of a
# player's, and the lines looked like bricks.)
W, H, SCALE = 1280, 720, 2

LINE = (243, 232, 212, 255)        # Theme.csv cream, never pure white
LINE_SHADOW = (40, 70, 20, 255)    # a dark-green ink edge under each line
INK = (25, 17, 10, 255)            # Theme.csv background - the outline
NET = (243, 232, 212, 160)

# THE SPECKS. PixelLab scattered little sandy marks over the grass; read up
# close they look like scribbles. TIDY_SPECKS True turns each one into a
# slightly darker green of its own stripe - texture without the noise.
TIDY_SPECKS = True
LIGHT_SPECK = (140, 180, 30, 255)
DARK_SPECK = (78, 128, 18, 255)

LINE_W = 2
RUNOFF = 22                        # grass beyond the lines, on the 1280 grid
                                   # (the goals sit in it)


def tune(key, fallback):
    with open(os.path.join(HERE, "data", "Tuning.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("Key", "").strip() == key:
                try:
                    return float(row["Value"])
                except ValueError:
                    return fallback
    return fallback


def setting(path, key, fallback):
    """One value out of project.godot (the window size)."""
    with open(os.path.join(HERE, path), encoding="utf-8") as f:
        for raw in f:
            if raw.strip().startswith(key + "="):
                return float(raw.split("=", 1)[1])
    return fallback


def pitch_size():
    """Width and Height of the pitch row in data/Stadium.csv."""
    with open(os.path.join(HERE, "data", "Stadium.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("Layer", "").strip() == "pitch":
                return float(row["Width"]), float(row["Height"])
    return 2560.0, 1440.0


def zone_rect(w, h):
    """Where the game puts the player zones, in pixels of a w x h picture.
    Mirrors get_play_rect() in main_scene.gd: the window centred on the
    pitch, clipped to it, then pulled in by the two inset rows."""
    pw, ph = pitch_size()
    vw = setting("project.godot", "window/size/viewport_width", 1920)
    vh = setting("project.godot", "window/size/viewport_height", 1080)
    aw, ah = min(vw, pw), min(vh, ph)
    ix, iy = tune("pitch_inset_x", 0.06), tune("pitch_inset_y", 0.10)
    x0 = (pw - aw) / 2 + aw * ix
    y0 = (ph - ah) / 2 + ah * iy
    x1 = (pw + aw) / 2 - aw * ix
    y1 = (ph + ah) / 2 - ah * iy
    sx, sy = w / pw, h / ph
    return x0 * sx, y0 * sy, x1 * sx, y1 * sy


def line(d, a, b):
    """A pitch line: dark ink one pixel down-right, cream on top."""
    (x0, y0), (x1, y1) = a, b
    d.line([(x0 + 1, y0 + 1), (x1 + 1, y1 + 1)], fill=LINE_SHADOW, width=LINE_W)
    d.line([a, b], fill=LINE, width=LINE_W)


def rect(d, x0, y0, x1, y1):
    for a, b in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        line(d, a, b)


def arc(d, cx, cy, r, start, end):
    box = [cx - r, cy - r, cx + r, cy + r]
    d.arc([b + 1 for b in box], start, end, fill=LINE_SHADOW, width=LINE_W)
    d.arc(box, start, end, fill=LINE, width=LINE_W)


def tidy(img):
    """Every pixel that is not plainly green becomes a darker green of its stripe."""
    px = img.load()
    w, h = img.size
    def green(c):
        r, g, b = c[0], c[1], c[2]
        return g > r + 25 and g > b + 60
    out = img.copy()
    op = out.load()
    for x in range(w):
        col = [px[x, y] for y in range(h) if green(px[x, y])]
        light = sum(1 for c in col if c[1] > 175) > len(col) / 2 if col else True
        for y in range(h):
            if not green(px[x, y]):
                op[x, y] = LIGHT_SPECK if light else DARK_SPECK
    return out


def main():
    grass = Image.open(GRASS).convert("RGBA")
    if TIDY_SPECKS:
        grass = tidy(grass)
    grass = grass.resize((W, H), Image.NEAREST)

    # The lines, measured exactly as the game measures the zones.
    zx0, zy0, zx1, zy1 = zone_rect(W, H)
    L, R = round(zx0), round(zx1) - 1
    T, B = round(zy0), round(zy1) - 1

    # Grass only inside the lines and a strip of run-off; the rest is
    # see-through, so the village shows round it.
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    box = (L - RUNOFF, T - RUNOFF, R + RUNOFF + 1, B + RUNOFF + 1)
    img.paste(grass.crop(box), box[:2])
    d = ImageDraw.Draw(img)
    d.rectangle([box[0], box[1], box[2] - 1, box[3] - 1], outline=INK, width=1)
    pw, ph = R - L, B - T                      # pitch in pixels
    mx, my = pw / 105.0, ph / 68.0             # pixels per metre
    cx, cy = (L + R) // 2, (T + B) // 2
    rect(d, L, T, R, B)
    line(d, (cx, T), (cx, B))
    arc(d, cx, cy, round(9.15 * my), 0, 360)
    d.rectangle([cx - 2, cy - 2, cx + 2, cy + 2], fill=LINE)
    for side in (-1, 1):
        x_goal = L if side < 0 else R
        inward = 1 if side < 0 else -1
        box_d, box_h = round(16.5 * mx), round(40.3 * my / 2)
        six_d, six_h = round(5.5 * mx), round(18.3 * my / 2)
        xa, xb = sorted((x_goal, x_goal + inward * box_d))
        rect(d, xa, cy - box_h, xb, cy + box_h)
        xa, xb = sorted((x_goal, x_goal + inward * six_d))
        rect(d, xa, cy - six_h, xb, cy + six_h)
        spot = x_goal + inward * round(11 * mx)
        d.rectangle([spot - 2, cy - 2, spot + 2, cy + 2], fill=LINE)
        # The arc outside the box.
        # (Metres across and along are not the same number of pixels, so the
        # angle where the arc meets the box is worked out in pixels.)
        import math
        r = round(9.15 * my)
        reach = abs(box_d - round(11 * mx))
        a = math.degrees(math.acos(min(1.0, reach / r))) if r > reach else 0
        if side < 0:
            arc(d, spot, cy, r, -a, a)
        else:
            arc(d, spot, cy, r, 180 - a, 180 + a)
        # The goal, behind the line: a net in cream, framed in ink.
        gd, gh = max(4, round(2.0 * mx)), round(7.32 * my / 2)
        gx0, gx1 = sorted((x_goal, x_goal - inward * gd))
        d.rectangle([gx0, cy - gh, gx1, cy + gh], fill=(30, 40, 20, 255), outline=INK)
        for y in range(cy - gh + 3, cy + gh, 5):
            d.line([(gx0 + 1, y), (gx1 - 1, y)], fill=NET)
        for x in range(gx0 + 3, gx1, 5):
            d.line([(x, cy - gh + 1), (x, cy + gh - 1)], fill=NET)
        d.line([(x_goal, cy - gh), (x_goal, cy + gh)], fill=LINE, width=LINE_W)
    # The corner arcs.
    for (x, y, a0) in ((L, T, 0), (R, T, 90), (R, B, 180), (L, B, 270)):
        arc(d, x, y, 9, a0, a0 + 90)

    img.resize((W * SCALE, H * SCALE), Image.NEAREST).save(OUT)
    print("wrote %s (%dx%d) - lines on the zone edge, x %d..%d y %d..%d of %dx%d"
          % (os.path.relpath(OUT, HERE), W * SCALE, H * SCALE,
             L * SCALE, (R + 1) * SCALE, T * SCALE, (B + 1) * SCALE, W * SCALE, H * SCALE))


if __name__ == "__main__":
    main()
