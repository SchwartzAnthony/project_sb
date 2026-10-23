#!/usr/bin/env python3
# =============================================================
#  THE VILLAGE PITCH  (Anthony, 23 Oct 2026)
#
#      python3 tools/make_village_pitch.py
#
#  Anthony: "switch matches to this village with the straight-on pitch",
#  "Redraw the grass and lines for sure". The match is played on the drawn
#  village seen from above (art_source/drawn_pitch/village_from_above.png,
#  r182 with the trophy hut painted over with trees). Two pictures come out:
#
#    assets/field/match_ground_village.png  the village, x2 (PitchView.csv
#                                           background)
#    assets/field/soccerfield_village.png   the mowing stripes, the inked
#                                           lines and the goals, see-through
#                                           everywhere else (PitchView.csv
#                                           pitch_image)
#
#  The lines are drawn where PitchView.csv says the line corners land on the
#  village (corner_top_left / corner_top_right / corner_bottom_left), then
#  turned back into the flat pitch picture the game tilts. So in a match
#  they land exactly on those corners, round circles stay round and every
#  line is the same thickness. Move a corner in the CSV and run this again.
#
#  The grass itself is the drawn grass of the village picture; this only adds
#  flat mowing stripes over it. Change a colour or size below and run again.
# =============================================================

import csv
import math
import os
import random
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(HERE, "art_source", "drawn_pitch", "village_from_above.png")
GROUND = os.path.join(HERE, "assets", "field", "match_ground_village.png")
PITCH = os.path.join(HERE, "assets", "field", "soccerfield_village.png")
GROUND_SCALE = 2
# r183 (Anthony, 23 Oct: "Yes please do that"): a sharper drawing of only the
# grass, laid over the village's own grass so it stays crisp close up. Blank
# GRASS = the village's own grass. GRASS_BOX is where it goes in the village
# picture (1536 wide), GRASS_FEATHER how softly its edge fades into the old.
GRASS = os.path.join(HERE, "art_source", "drawn_pitch", "pitch_grass.png")
GRASS_BOX = (272, 266, 1276, 666)
GRASS_FEATHER = 24
GRASS_MATCH = 0.8                  # 1 = its colours moved fully onto the old

LINE = (243, 232, 212, 255)        # Theme.csv cream, never pure white
INK = (25, 17, 10, 255)            # the black ink edge round each line
LINE_W = 9                         # cream, in village pixels (x2 picture)
INK_W = 3                          # ink each side of the cream
WOBBLE = 1.6                       # how far a hand-drawn line wanders
STRIPES = 12                       # mowing stripes between the goal lines
STRIPE = (20, 50, 5, 46)           # the darker stripe, see-through
RUNOFF = 40                        # stripes reach this far past the lines
NET = (243, 232, 212, 200)
SS = 2                             # drawn at x2, then smoothed down


def pitch_view():
    with open(os.path.join(HERE, "data", "PitchView.csv"), encoding="utf-8") as f:
        return {r["Key"].strip(): r["Value"].strip() for r in csv.DictReader(f)}


def pair(text):
    a, b = text.split(",")
    return float(a), float(b)


def wobbly(points, rng):
    """A ruler line made to look inked by hand: it wanders a little."""
    out = []
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        n = max(2, int(math.hypot(x1 - x0, y1 - y0) / 40))
        phase, freq = rng.uniform(0, 6.3), rng.uniform(0.6, 1.4)
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length
        for i in range(n + 1):
            t = i / n
            w = WOBBLE * math.sin(phase + t * freq * 6.3) * math.sin(t * math.pi)
            out.append((x0 + dx * t + nx * w, y0 + dy * t + ny * w))
    return out


def stroke(d, points, rng, closed=False):
    if closed:
        points = points + [points[0]]
    path = [(x * SS, y * SS) for x, y in wobbly(points, rng)]
    d.line(path, fill=INK, width=(LINE_W + 2 * INK_W) * SS, joint="curve")
    for p in (path[0], path[-1]):
        r = (LINE_W + 2 * INK_W) * SS / 2
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=INK)
    return path


def cream(d, path):
    d.line(path, fill=LINE, width=LINE_W * SS, joint="curve")
    for p in (path[0], path[-1]):
        r = LINE_W * SS / 2
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=LINE)


def arc_points(cx, cy, rx, ry, a0, a1, steps=48):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / steps)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / steps)))
            for i in range(steps + 1)]


def spot(d, x, y, r):
    for col, rr in ((INK, r + INK_W), (LINE, r)):
        d.ellipse([(x - rr) * SS, (y - rr) * SS, (x + rr) * SS, (y + rr) * SS], fill=col)


def lay_grass(ground):
    """The sharper grass over the old, its colours moved onto the old ones."""
    from PIL import ImageFilter, ImageStat
    box = tuple(v * GROUND_SCALE for v in GRASS_BOX)
    size = (box[2] - box[0], box[3] - box[1])
    new = Image.open(GRASS).convert("RGB").resize(size, Image.LANCZOS)
    old = ground.crop(box)
    om, os_ = ImageStat.Stat(old).mean, ImageStat.Stat(old).stddev
    nm, ns = ImageStat.Stat(new).mean, ImageStat.Stat(new).stddev
    bands = []
    for i, band in enumerate(new.split()):
        k = 1 + GRASS_MATCH * (os_[i] / max(ns[i], 1) - 1)
        shift = nm[i] + GRASS_MATCH * (om[i] - nm[i])
        bands.append(band.point(lambda v, k=k, m=nm[i], t=shift: max(0, min(255, int((v - m) * k + t)))))
    new = Image.merge("RGB", bands)
    f = GRASS_FEATHER * GROUND_SCALE
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rectangle([f, f, size[0] - f, size[1] - f], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(f / 2))
    ground.paste(new, box[:2], mask)


def main():
    view = pitch_view()
    src = Image.open(SOURCE).convert("RGB")
    ground = src.resize((src.width * GROUND_SCALE, src.height * GROUND_SCALE), Image.LANCZOS)
    if GRASS and os.path.exists(GRASS):
        lay_grass(ground)
    ground.save(GROUND)

    tl, tr, bl = (pair(view[k]) for k in ("corner_top_left", "corner_top_right", "corner_bottom_left"))
    L, T = tl
    R, B = tr[0], bl[1]
    W, H = ground.size
    mx, my = (R - L) / 105.0, (B - T) / 68.0     # village pixels per metre
    cx, cy = (L + R) / 2, (T + B) / 2
    rng = random.Random(182)

    art = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)

    # Mowing stripes, flat and see-through so the drawn grass shows.
    band = (R - L) / STRIPES
    for i in range(-1, STRIPES + 1):
        if i % 2:
            continue
        x0 = max(L - RUNOFF, L + i * band)
        x1 = min(R + RUNOFF, L + (i + 1) * band)
        d.rectangle([x0 * SS, (T - RUNOFF) * SS, x1 * SS, (B + RUNOFF) * SS], fill=STRIPE)

    # The goals first, behind the goal lines, so the lines are drawn over them.
    gh, gd = 7.32 * my / 2 * 1.6, 2.2 * mx    # a little big, to read from above
    for side in (-1, 1):
        gx = L if side < 0 else R
        back = gx + side * gd
        x0, x1 = sorted((gx, back))
        d.rectangle([x0 * SS, (cy - gh) * SS, x1 * SS, (cy + gh) * SS], fill=(30, 40, 20, 150))
        step = 9
        y = cy - gh + step
        while y < cy + gh:
            d.line([(x0 * SS, y * SS), (x1 * SS, y * SS)], fill=NET, width=2 * SS)
            y += step
        x = x0 + step
        while x < x1:
            d.line([(x * SS, (cy - gh) * SS), (x * SS, (cy + gh) * SS)], fill=NET, width=2 * SS)
            x += step
        frame = [(gx, cy - gh), (back, cy - gh), (back, cy + gh), (gx, cy + gh)]
        cream(d, stroke(d, frame, rng))

    # Every line in ink first, then all the cream on top, so crossings join.
    paths = []
    paths.append(stroke(d, [(L, T), (R, T), (R, B), (L, B)], rng, closed=True))
    paths.append(stroke(d, [(cx, T), (cx, B)], rng))
    # Seen from above at a slant, a circle is an oval: 9.15 m across and along.
    rx, ry = 9.15 * mx, 9.15 * my
    paths.append(stroke(d, arc_points(cx, cy, rx, ry, 0, 360, 64), rng))
    for side in (-1, 1):
        gx = L if side < 0 else R
        inward = -side
        box_d, box_h = 16.5 * mx, 40.3 * my / 2
        six_d, six_h = 5.5 * mx, 18.3 * my / 2
        for dd, hh in ((box_d, box_h), (six_d, six_h)):
            ix = gx + inward * dd
            paths.append(stroke(d, [(gx, cy - hh), (ix, cy - hh), (ix, cy + hh), (gx, cy + hh)], rng))
        px = gx + inward * 11 * mx
        reach = box_d - 11 * mx
        a = math.degrees(math.acos(min(1.0, reach / rx)))
        if side < 0:
            pts = arc_points(px, cy, rx, ry, -a, a)
        else:
            pts = arc_points(px, cy, rx, ry, 180 - a, 180 + a)
        paths.append(stroke(d, pts, rng))
    for (x, y, a0) in ((L, T, 0), (R, T, 90), (R, B, 180), (L, B, 270)):
        paths.append(stroke(d, arc_points(x, y, 1.2 * mx, 1.2 * my, a0, a0 + 90, 12), rng))
    for p in paths:
        cream(d, p)
    spot(d, cx, cy, 5)
    for side in (-1, 1):
        spot(d, (L if side < 0 else R) - side * 11 * mx, cy, 4)

    art = art.resize((W, H), Image.LANCZOS)

    # Back into the flat pitch picture the game tilts onto those corners.
    iw, ih = pair(view["pitch_image_size"])
    lx, ly, lw, lh = (float(v) for v in view["lines_in_pitch_image"].split(","))
    sx, sy = (R - L) / lw, (B - T) / lh
    flat = art.transform((int(iw), int(ih)), Image.AFFINE,
                         (sx, 0, L - lx * sx, 0, sy, T - ly * sy), resample=Image.BICUBIC)
    flat.save(PITCH)
    print("wrote %s (%dx%d) and %s (%dx%d); lines x %d..%d y %d..%d on the village"
          % (os.path.relpath(GROUND, HERE), W, H, os.path.relpath(PITCH, HERE),
             iw, ih, L, R, T, B))


if __name__ == "__main__":
    main()
