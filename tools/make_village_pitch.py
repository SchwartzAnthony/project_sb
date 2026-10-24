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
# 24 OCT (Anthony: "Redraw the grass on the field, it looks very bad when
# close up", with a photo of mown stripes): DRAWN = the lawn inside the wall
# is drawn fresh by this script at full size, in flat comic colours: wide
# mown stripes, fine mowing streaks and a few small inked grass tufts, so it
# stays crisp however close the camera gets. False = the r183 picture above.
DRAWN = True
LAWN_LIGHT = (124, 178, 44)        # the light mown stripe
LAWN_DARK = (98, 152, 32)          # the dark mown stripe
LAWN_RUNOFF = (106, 160, 36)       # the grass outside the white lines
TUFT_INK = (44, 92, 18)            # the inked grass tufts (dark green, not black)
TUFTS = 450                        # how many tufts on the whole lawn
STREAKS = 9000                     # how many fine mowing streaks
LAWN_BOX = (470, 505, 2612, 1364)  # the lawn lies inside this box (x2 picture)

LINE = (243, 232, 212, 255)        # Theme.csv cream, never pure white
INK = (25, 17, 10, 255)            # the black ink edge round each line
LINE_W = 9                         # cream, in village pixels (x2 picture)
INK_W = 3                          # ink each side of the cream
WOBBLE = 1.3                       # how far a hand-drawn line wanders
STRIPES = 12                       # mowing stripes between the goal lines
STRIPE = (20, 50, 5, 46)           # the darker stripe, see-through
RUNOFF = 0                         # stripes reach this far past the lines (0 = they stop at the white lines, Anthony 23 Oct)
NET = (243, 232, 212, 200)
SS = 2                             # drawn at x2, then smoothed down


def pitch_view():
    with open(os.path.join(HERE, "data", "PitchView.csv"), encoding="utf-8") as f:
        return {r["Key"].strip(): r["Value"].strip() for r in csv.DictReader(f)}


def pair(text):
    a, b = text.split(",")
    return float(a), float(b)


def wobbly(points, rng):
    """A ruler line made to look inked by hand: it wanders a little, slowly
    and smoothly along its whole length (never in little bumps)."""
    path = dense(points, 6.0)
    total, s = [0.0], 0.0
    for (x0, y0), (x1, y1) in zip(path, path[1:]):
        s += math.hypot(x1 - x0, y1 - y0)
        total.append(s)
    p1, p2 = rng.uniform(0, 6.3), rng.uniform(0, 6.3)
    f1, f2 = rng.uniform(140, 220), rng.uniform(60, 90)
    out = []
    for i, (x, y) in enumerate(path):
        a, b = path[max(0, i - 1)], path[min(len(path) - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1.0
        ease = min(1.0, total[i] / 80.0, (total[-1] - total[i]) / 80.0)   # ends land exactly
        w = ease * WOBBLE * (0.75 * math.sin(p1 + total[i] / f1 * 6.3) + 0.25 * math.sin(p2 + total[i] / f2 * 6.3))
        out.append((x - dy / length * w, y + dx / length * w))
    return out


def dense(path, step):
    """The path with a point every `step` pixels, so a round brush can be
    stamped along it (PIL's own wide lines go jagged on tight curves)."""
    out = [path[0]]
    for (x0, y0), (x1, y1) in zip(path, path[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0) / step))
        out += [(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n) for i in range(1, n + 1)]
    return out


def brush(d, path, width, col):
    r = width / 2
    for x, y in dense(path, max(1.0, r / 4)):
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)


def stroke(d, points, rng, closed=False):
    if closed:
        points = points + [points[0]]
    path = [(x * SS, y * SS) for x, y in wobbly(points, rng)]
    brush(d, path, (LINE_W + 2 * INK_W) * SS, INK)
    return path


def cream(d, path):
    brush(d, path, LINE_W * SS, LINE)


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


def lawn_mask(ground):
    """The lawn inside the stone wall and fence: the green joined to the
    centre spot, inside LAWN_BOX, with its small holes filled."""
    from PIL import ImageFilter
    import numpy as np
    g = np.asarray(ground).astype(int)
    r, gr, b = g[..., 0], g[..., 1], g[..., 2]
    box = np.zeros(r.shape, bool)
    x0, y0, x1, y1 = LAWN_BOX
    box[y0:y1, x0:x1] = True
    green = Image.fromarray((((gr > r + 20) & (gr > b + 40) & box) * 255).astype("uint8"))
    green = green.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    ImageDraw.floodfill(green, ((x0 + x1) // 2, (y0 + y1) // 2), 128)
    lawn = np.asarray(green) == 128
    outside = Image.fromarray(np.where(lawn, 0, 255).astype("uint8")).copy()
    ImageDraw.floodfill(outside, (0, 0), 128)
    lawn = np.asarray(outside) != 128
    return Image.fromarray((lawn * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(1.2))


def draw_grass(ground, view):
    """Flat comic grass, drawn at x2 and smoothed down so it stays crisp."""
    from PIL import ImageChops, ImageFilter
    tl, tr, bl = (pair(view[k]) for k in ("corner_top_left", "corner_top_right", "corner_bottom_left"))
    L, T, R, B = tl[0], tl[1], tr[0], bl[1]
    W, H = ground.size
    rng = random.Random(2410)
    k = SS
    art = Image.new("RGB", (W * k, H * k), LAWN_RUNOFF)
    d = ImageDraw.Draw(art)
    band = (R - L) / STRIPES
    for i in range(STRIPES):
        col = LAWN_LIGHT if i % 2 else LAWN_DARK
        d.rectangle([(L + i * band) * k, T * k, (L + (i + 1) * band) * k, B * k], fill=col)

    def shade(col, n):
        return tuple(max(0, min(255, c + n)) for c in col)

    def stripe_colour(x, y):
        if not (L <= x <= R and T <= y <= B):
            return LAWN_RUNOFF
        return LAWN_LIGHT if int((x - L) / band) % 2 else LAWN_DARK

    x0, y0, x1, y1 = LAWN_BOX
    # Fine mowing streaks along the stripes, like the cut in the photo.
    for _ in range(STREAKS):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        n = rng.choice((-9, -6, 6, 9))
        ln = rng.uniform(18, 70)
        d.line([(x * k, y * k), (x * k + rng.uniform(-1, 1) * k, (y + ln) * k)],
               fill=shade(stripe_colour(x, y), n), width=k)
    # Small inked tufts: two or three short strokes from one root.
    for _ in range(TUFTS):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        h = rng.uniform(4, 7)
        for a in (-0.5, 0.0, 0.45):
            hh = h * rng.uniform(0.7, 1.15)
            mid = (x + math.sin(a) * hh * 0.5, y - hh * 0.55)
            tip = (x + math.sin(a * 1.6) * hh, y - math.cos(a) * hh)
            d.line([(x * k, y * k), (mid[0] * k, mid[1] * k), (tip[0] * k, tip[1] * k)],
                   fill=TUFT_INK, width=int(1.4 * k), joint="curve")
    art = art.resize((W, H), Image.LANCZOS)

    # Keep the shadows the wall, fence and trees throw on the old grass.
    old = ground.convert("L").filter(ImageFilter.GaussianBlur(10))
    from PIL import ImageStat
    mean = ImageStat.Stat(old.crop((int(L), int(T), int(R), int(B)))).mean[0]
    dark = old.point(lambda v: 255 if v >= mean else int(255 * (0.55 + 0.45 * v / mean)))
    art = ImageChops.multiply(art, Image.merge("RGB", (dark, dark, dark)))
    ground.paste(art, (0, 0), lawn_mask(ground))


def main():
    view = pitch_view()
    src = Image.open(SOURCE).convert("RGB")
    ground = src.resize((src.width * GROUND_SCALE, src.height * GROUND_SCALE), Image.LANCZOS)
    if DRAWN:
        draw_grass(ground, view)
    elif GRASS and os.path.exists(GRASS):
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
    for i in range(0 if DRAWN else STRIPES):    # DRAWN grass has its own stripes
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
