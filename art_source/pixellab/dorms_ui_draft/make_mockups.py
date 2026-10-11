#!/usr/bin/env python3
# =============================================================
#  THREE LOOKS FOR THE DORMS SCREEN  (round AN, Anthony 10 Oct: "still looks
#  very AI and generic - what would make this look more polished?")
#
#      ~/.venvs/sturmball/bin/python art_source/pixellab/dorms_ui_draft/make_mockups.py
#
#  DRAFTS ONLY - nothing here is in the game. Each look is built from the
#  PixelLab pieces in this folder over the cellar, at game pixels (960 x 540
#  = 1920 x 1080 at x2), and saved twice:
#      mockup_<look>.png          the picture to look at
#      layers_<look>/NN_part.png  one PNG per part, for the .aseprite file
#  The words are the game's own pixel font (pixfont.py).
# =============================================================
import csv
import os
import shutil
from PIL import Image, ImageDraw
import pixfont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
W, H = 960, 540

CREAM = (247, 233, 201)
CHALK = (236, 240, 236)
INK = (40, 28, 18)
GOLD = (242, 179, 61)


def load(name):
    return Image.open(os.path.join(HERE, name)).convert("RGBA")


def asset(path):
    return Image.open(os.path.join(ROOT, path)).convert("RGBA")


def big(im, s):
    return im.resize((round(im.width * s), round(im.height * s)), Image.NEAREST)


def dim(im, k):
    """Darker, for a tab you are not on - colour only, never see-through."""
    r, g, b, a = im.split()
    r, g, b = (c.point(lambda v: int(v * k)) for c in (r, g, b))
    return Image.merge("RGBA", (r, g, b, a))


def cropped(im):
    return im.crop(im.getbbox())


class Look:
    """A stack of layers, bottom first, each a full-canvas RGBA image."""

    def __init__(self, name):
        self.name = name
        self.layers = []

    def layer(self, part):
        im = Image.new("RGBA", (W, H))
        self.layers.append((part, im))
        return im

    def save(self):
        out = Image.new("RGBA", (W, H), (0, 0, 0, 255))
        folder = os.path.join(HERE, "layers_" + self.name)
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(folder)
        for i, (part, im) in enumerate(self.layers):
            out.alpha_composite(im)
            im.save(os.path.join(folder, "%02d_%s.png" % (i + 1, part)))
        out.convert("RGB").save(os.path.join(HERE, "mockup_%s.png" % self.name))
        # And the layers as a .aseprite file, via the project's own tool.
        rows = [["Part", "Image", "X", "Y", "Width", "Height", "Scale", "Flip"]]
        for i, (part, im) in enumerate(self.layers):
            path = "res://art_source/pixellab/dorms_ui_draft/layers_%s/%02d_%s.png" % (self.name, i + 1, part)
            rows.append(["picture", path, W, H, W * 2, H * 2, "", ""])
        with open(os.path.join(folder, "layers.csv"), "w", newline="") as f:
            csv.writer(f, lineterminator="\n").writerows(rows)
        print("wrote mockup_%s.png (%d layers)" % (self.name, len(self.layers)))


# ---- the room and its beds: the same in every look ----------

ROOM = asset("assets/dorms/dorms_bg.png")
BED = asset("assets/dorms/bed.png")
SLEEPER = asset("assets/dorms/bed_sleeper.png")
SPOTS = [(float(r["X"]), float(r["Y"]), float(r["Size"]))
         for r in csv.DictReader(open(os.path.join(ROOT, "data", "DormBeds.csv")))]
# A FULL-SCREEN ROOM puts the front row on the bottom edge, so the mockups
# lift both rows a little (front 0.03, back 0.01). If a full-screen look is
# picked, DormBeds.csv gets the same change.
SPOTS = [(x, y - (0.03 if y > 0.9 else 0.01), size) for (x, y, size) in SPOTS]
# Rest left / full, one per bed, so every look shows the same sleepers.
REST = [(2, 4), (1, 3), (3, 5), (0, 2), (2, 2), (1, 1), (4, 5), (0, 3), (2, 3), (1, 2)]


def room_layers(look, mugs, rect=(0, 0, W, H), top_cut=0.0):
    """The cellar filling `rect` (x, y, w, h), then the beds on its floor.
    `top_cut` is the share of the picture's top (the ceiling) left out."""
    rx, ry, rw, rh = rect
    bg = look.layer("room")
    shown_h = ROOM.height * (1 - top_cut)
    s = max(rw / ROOM.width, rh / shown_h)
    pic = big(ROOM, s)
    off_x = rx + (rw - pic.width) // 2
    off_y = ry - round(pic.height * top_cut)
    clip = Image.new("RGBA", (W, H))
    clip.alpha_composite(pic, (off_x, off_y))
    bg.alpha_composite(clip.crop((rx, ry, rx + rw, ry + rh)), (rx, ry))

    beds = look.layer("beds")
    marks = look.layer("zzz_and_rest")
    order = sorted(range(len(SPOTS)), key=lambda i: SPOTS[i][1])
    for i in order:
        x, y, size = SPOTS[i]
        art = SLEEPER if i not in (4, 9) else BED
        wide = size * pic.width
        bed = big(art, wide / art.width)
        fx = off_x + x * pic.width
        fy = off_y + y * pic.height
        bx, by = round(fx - bed.width / 2), round(fy - bed.height)
        beds.alpha_composite(bed, (bx, by))
        if art is SLEEPER:
            pixfont.draw(marks, "Z", bx + 10, by - 10, (200, 225, 255))
            pixfont.draw(marks, "z", bx + 20, by - 18, (200, 225, 255))
            pixfont.draw(marks, "z", bx + 28, by - 24, (200, 225, 255))
            left, full = REST[i]
            done = full - left
            empty_m, full_m = mugs
            step = full_m.width + 1
            sx = round(fx - step * full / 2)
            for k in range(full):
                marks.alpha_composite(full_m if k < done else empty_m, (sx + k * step, round(fy) + 1))
    return off_x, off_y, pic


def say(layer, words, x, y, colour=CREAM, scale=1):
    """Words on the game's see-through black plate (text_backdrop_alpha)."""
    w = pixfont.width(words, scale)
    plate = Image.new("RGBA", (w + 12, 18 * scale + 6), (0, 0, 0, 140))
    layer.alpha_composite(plate, (x - 6, y - 3))
    pixfont.draw(layer, words, x, y, colour, scale)


def hover_tag(layer, x, y, name, power, left):
    """A brown paper luggage tag on a string: the hover name and power."""
    d = ImageDraw.Draw(layer)
    w = max(pixfont.width(name), pixfont.width("P:%d  %d to go" % (power, left))) + 16
    d.line([(x, y), (x + 10, y + 12)], fill=INK, width=1)
    box = [x + 6, y + 10, x + 6 + w, y + 10 + 38]
    d.rounded_rectangle(box, 4, fill=(214, 178, 122), outline=INK, width=2)
    d.ellipse([box[0] + 4, box[1] + 4, box[0] + 9, box[1] + 9], outline=INK)
    pixfont.draw(layer, name, box[0] + 12, box[1] + 3, INK, shadow=False)
    pixfont.draw(layer, "P:%d  %d to go" % (power, left), box[0] + 12, box[1] + 19, (90, 50, 20), shadow=False)


def mug_pips():
    """One mug per fixture of rest: full = slept, empty = still to sleep."""
    return big(cropped(load(MUG_EMPTY)), 0.32), big(cropped(load(MUG_FULL)), 0.32)


# ---- chosen candidates (the rest stay in the folder) --------

PENNANT = "pennant_00.png"
PLATE = "doorplate_01.png"
NOTICE = "noticeboard_a.png"
CHALKBOARD = "chalkboard_a.png"
KEY = "key_00.png"
CAMPBED = "campbed_01.png"
MUG_FULL = "mug_full_00.png"
MUG_EMPTY = "mug_empty_00.png"


def price_tag(layer, x, y, words):
    """A little cream card pinned with a red drawing pin."""
    d = ImageDraw.Draw(layer)
    w = pixfont.width(words) + 12
    d.rectangle([x, y, x + w, y + 20], fill=CREAM, outline=INK, width=2)
    d.ellipse([x + w // 2 - 3, y - 3, x + w // 2 + 3, y + 3], fill=(200, 40, 40), outline=INK)
    pixfont.draw(layer, words, x + 6, y + 3, INK, shadow=False)
    return w


# =============================================================
#  LOOK A - THE CLUB NOTICEBOARD
#  Pennants on a string are the room tabs; the shop is the club's wooden
#  notice board, a camp bed and a door key pinned to it with price cards.
# =============================================================

def look_noticeboard():
    look = Look("a_noticeboard")
    room_layers(look, mug_pips())

    tabs = look.layer("room_tabs")
    d = ImageDraw.Draw(tabs)
    d.line([(14, 18), (250, 26)], fill=INK, width=2)
    pen = big(cropped(load(PENNANT)), 1.25)
    for i in range(3):
        x = 22 + i * 70
        drop = 10 if i == 0 else 0           # the room you are in hangs lower
        p = pen if i == 0 else dim(pen, 0.8)
        tabs.alpha_composite(p, (x, 12 + drop))
        cx = x + p.width // 2
        n = str(i + 1)
        pixfont.draw(tabs, n, cx - pixfont.width(n) // 2, 12 + drop + int(p.height * 0.47) - 9, (30, 60, 140), 1, False)
    say(tabs, "ROOM 1   8 asleep   10 of 10 beds", 30, 112, CREAM)

    shop = look.layer("notice_board")
    # On the right-hand wall, above the beds - never over them.
    board = big(cropped(load(NOTICE)), 1.5)
    bx, by = W - board.width - 12, 8
    shop.alpha_composite(board, (bx, by))
    items = look.layer("shop_items")
    bed = big(cropped(load(CAMPBED)), 0.8)
    key = big(cropped(load(KEY)), 0.8)
    items.alpha_composite(bed, (bx + 38, by + 34))
    items.alpha_composite(key, (bx + 150, by + 34))
    price_tag(items, bx + 34, by + 100, "Bed 25")
    price_tag(items, bx + 130, by + 100, "Room 250")

    hover = look.layer("hover_tag")
    hover_tag(hover, 330, 236, "Baumgartner", 4, 2)
    look.save()


# =============================================================
#  LOOK B - THE CHALKBOARD
#  Enamel door plates down the left wall are the room tabs; the shop is the
#  team's chalkboard, prices written in chalk, things to buy on its tray.
# =============================================================

def look_chalkboard():
    look = Look("b_chalkboard")
    room_layers(look, mug_pips())

    tabs = look.layer("room_tabs")
    plate = big(cropped(load(PLATE)), 2.1)
    for i in range(3):
        y = 20 + i * (plate.height + 6)
        p = plate if i == 0 else dim(plate, 0.7)
        x = 16 if i == 0 else 10
        tabs.alpha_composite(p, (x, y))
        n = "Zimmer %d" % (i + 1)
        pixfont.draw(tabs, n, x + p.width // 2 - pixfont.width(n) // 2, y + p.height // 2 - 9, (30, 60, 140) if i == 0 else (90, 90, 100), 1, False)

    board_layer = look.layer("chalkboard")
    board = big(cropped(load(CHALKBOARD)), 1.75)
    bx, by = W - board.width - 10, 10
    board_layer.alpha_composite(board, (bx, by))
    chalk = look.layer("chalk_words")
    lines = [("ROOM 1", GOLD), ("8 asleep  10/10", CHALK), ("", CHALK),
             ("A bed .... 25", CHALK), ("Room 4 .. 250", CHALK)]
    for k, (words, colour) in enumerate(lines):
        pixfont.draw(chalk, words, bx + 30, by + 30 + k * 20, colour, 1, False)
    items = look.layer("buy_buttons")
    bed = big(cropped(load(CAMPBED)), 0.62)
    key = big(cropped(load(KEY)), 0.62)
    items.alpha_composite(bed, (bx + 40, by + board.height - bed.height - 40))
    items.alpha_composite(key, (bx + 120, by + board.height - key.height - 40))

    hover = look.layer("hover_tag")
    hover_tag(hover, 330, 236, "Baumgartner", 4, 2)
    look.save()


# =============================================================
#  LOOK C - THE BEER HALL (the game's own frame and banners)
#  The blue menu banners are the room tabs; a shelf in the game's own brass
#  window along the bottom with beer-mat buttons; pretzel corners.
# =============================================================

def look_beerhall():
    look = Look("c_beerhall")
    # THE ROOM IN THE GAME'S OWN BRASS FRAME, the shelf underneath.
    look.layer("dark").paste((26, 18, 11, 255), (0, 0, W, H))
    room_layers(look, mug_pips(), (14, 50, W - 28, 372), 0.30)

    tabs = look.layer("room_banners")
    banner = cropped(asset("assets/ui/banners/teams.png"))
    # The shirt is drawn on that banner; cover it with a cream disc for a number.
    for i in range(3):
        b = big(banner, 0.42 if i == 0 else 0.36)
        x = 20 + i * 66
        tabs.alpha_composite(b if i == 0 else dim(b, 0.75), (x, 0))
        d = ImageDraw.Draw(tabs)
        cx, cy = x + b.width // 2, int(b.height * 0.33)
        d.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=CREAM, outline=INK, width=2)
        n = str(i + 1)
        pixfont.draw(tabs, n, cx - pixfont.width(n, 2) // 2 + 1, cy - 14, (30, 60, 140), 2, False)

    shelf = look.layer("shelf_window")
    frame = asset("assets/ui/beerhall_window.png")
    # Nine-slice the game's own window into a long shelf.
    sw, sh, c = W - 28, 104, 28
    x0, y0 = 14, H - sh - 8
    fw, fh = frame.size
    parts = {
        (0, 0): (0, 0, c, c), (1, 0): (c, 0, fw - c, c), (2, 0): (fw - c, 0, fw, c),
        (0, 1): (0, c, c, fh - c), (1, 1): (c, c, fw - c, fh - c), (2, 1): (fw - c, c, fw, fh - c),
        (0, 2): (0, fh - c, c, fh), (1, 2): (c, fh - c, fw - c, fh), (2, 2): (fw - c, fh - c, fw, fh)}
    xs, ys = [0, c, sw - c, sw], [0, c, sh - c, sh]
    for (i, j), box in parts.items():
        piece = frame.crop(box).resize((xs[i + 1] - xs[i], ys[j + 1] - ys[j]), Image.NEAREST)
        shelf.alpha_composite(piece, (x0 + xs[i], y0 + ys[j]))
    corners = asset("assets/ui/duel/duel_box.png")
    cw = corners.width // 2
    for (cx, cy, bx, by) in [(0, 0, x0 - 8, y0 - 8), (1, 0, x0 + sw - cw + 8, y0 - 8),
                             (0, 1, x0 - 8, y0 + sh - corners.height // 2 + 8), (1, 1, x0 + sw - cw + 8, y0 + sh - corners.height // 2 + 8)]:
        piece = corners.crop((cx * cw, cy * corners.height // 2, (cx + 1) * cw, (cy + 1) * corners.height // 2))
        shelf.alpha_composite(piece, (bx, by))

    items = look.layer("beer_mat_buttons")
    mat = asset("assets/ui/beerhall_slot.png")
    for k, (art, words) in enumerate([(CAMPBED, "A bed 25"), (KEY, "Room 4  250"), (None, "Rest day")]):
        mx = x0 + 40 + k * 300
        m = mat.resize((84, 84), Image.NEAREST)
        items.alpha_composite(m, (mx, y0 + 10))
        if art:
            thing = big(cropped(load(art)), 0.75)
            items.alpha_composite(thing, (mx + 42 - thing.width // 2, y0 + 52 - thing.height // 2))
        else:
            pixfont.draw(items, "Zzz", mx + 22, y0 + 38, (30, 60, 140), 1, False)
        pixfont.draw(items, words, mx + 92, y0 + 42, CREAM)
    say(items, "ROOM 1   8 asleep   10 of 10 beds", 250, 16, GOLD)

    hover = look.layer("hover_tag")
    hover_tag(hover, 300, 160, "Baumgartner", 4, 2)
    look.save()


if __name__ == "__main__":
    look_noticeboard()
    look_chalkboard()
    look_beerhall()
