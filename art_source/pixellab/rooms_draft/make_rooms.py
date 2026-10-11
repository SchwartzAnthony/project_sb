#!/usr/bin/env python3
# =============================================================
#  THE CLUB HOUSE AND THE TRAINING GROUND, THREE LOOKS EACH  (round AN,
#  Anthony 10 Oct: "be as creative as you want - Oktoberfest, Bavarian,
#  soccer, Marcinelle school")
#
#      ~/.venvs/sturmball/bin/python art_source/pixellab/rooms_draft/make_rooms.py
#
#  DRAFTS ONLY. Each PixelLab scene (the clickable things are drawn into it
#  for now; once picked, each becomes its own layer) is put inside the
#  beer hall building window, with what hovering and buying would look
#  like: a luggage tag, price cards, the one status line. Writes
#  mockup_<look>.png and sheet_clubhouse.png / sheet_training.png.
# =============================================================
import os
import sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "dorms_ui_draft"))
import pixfont  # noqa: E402

# The game's own screenshots with the beer hall frame and the right sign.
SCREENS = os.path.join(HERE, "..", "window_frame_draft", "screens")
# The inside of the beer hall frame on the 1779 x 1001 screenshot.
INSIDE = (158, 130, 1620, 870)
SIGN_MIDDLE = 889
INK = (40, 26, 12)
CREAM = (247, 233, 201)
GOLD = (242, 179, 61)

TAG = Image.open(os.path.join(ROOT, "assets/dorms/ui/tag.png")).convert("RGBA")
CARD = Image.open(os.path.join(ROOT, "assets/dorms/ui/card.png")).convert("RGBA")
SIGN = Image.open(os.path.join(ROOT, "assets/ui/building_title.png")).convert("RGBA")

# What each look shows. X and Y are shares of the scene picture.
#   ("glow", x, y, w, h)          the thing under the mouse, lit
#   ("tag", x, y, [lines])        the luggage tag over it
#   ("card", x, y, "words")       a price card pinned by a thing
#   ("lock", x, y)                a locked thing: a padlock card
LOOKS = {
    "club_a_bar": ("CLUB HOUSE", "KEYS 6 for sale    UPGRADES 2 for sale    3 new faces on the board", [
        ("glow", 0.25, 0.34, 0.19, 0.14),
        ("tag", 0.33, 0.20, ["Bottling Machine Key  100", "opens the Bottling Machine"]),
        ("card", 0.345, 0.50, "6 keys"),
        ("card", 0.11, 0.38, "Feather Beds  300"),
        ("lock", 0.11, 0.18),
        ("card", 0.93, 0.62, "Sign  30"),
    ]),
    "club_b_office": ("CLUB HOUSE", "KEYS 6 for sale    UPGRADES 2 for sale    3 new faces on the desk", [
        ("glow", 0.21, 0.06, 0.28, 0.9),
        ("tag", 0.36, 0.30, ["Lucky Boots  250", "+1 to every shot"]),
        ("card", 0.11, 0.64, "6 keys"),
        ("card", 0.34, 0.90, "Upgrades"),
        ("card", 0.60, 0.88, "Sign  30"),
    ]),
    "club_c_beergarden": ("CLUB HOUSE", "KEYS 6 for sale    UPGRADES 2 for sale    3 new faces on the board", [
        ("glow", 0.62, 0.02, 0.15, 0.42),
        ("tag", 0.42, 0.06, ["Feather Beds  300", "one fixture less in bed"]),
        ("card", 0.36, 0.43, "6 keys"),
        ("card", 0.69, 0.47, "Upgrades"),
        ("card", 0.93, 0.62, "Sign  30"),
    ]),
    "train_a_pitch": ("TRAINING GROUND", "AUSBILDUNG 1 of 3    MINI-GAMES 2 of 5    4 players waiting for a role", [
        ("glow", 0.54, 0.62, 0.17, 0.14),
        ("tag", 0.50, 0.42, ["Long Legs  120", "+1 speed for the side"]),
        ("card", 0.62, 0.79, "Long Legs  120"),
        ("card", 0.19, 0.99, "Mini-games"),
        ("card", 0.66, 0.99, "Team sheet"),
        ("card", 0.79, 0.99, "Roles"),
    ]),
    "train_b_turnhalle": ("TRAINING GROUND", "AUSBILDUNG 1 of 3    MINI-GAMES 2 of 5    4 players waiting for a role", [
        ("glow", 0.10, 0.62, 0.15, 0.25),
        ("tag", 0.16, 0.44, ["Cold Nerve  150", "steadier penalties"]),
        ("card", 0.17, 0.88, "Cold Nerve  150"),
        ("card", 0.45, 0.80, "Keeper  100"),
        ("card", 0.85, 0.80, "Team sheet"),
    ]),
    "train_c_breweryyard": ("TRAINING GROUND", "AUSBILDUNG 1 of 3    MINI-GAMES 2 of 5    4 players waiting for a role", [
        ("glow", 0.33, 0.52, 0.16, 0.22),
        ("tag", 0.30, 0.32, ["The Turning Floor  200", "one more Steeping Tank vat"]),
        ("card", 0.41, 0.76, "Mini-game  200"),
        ("card", 0.87, 0.45, "Keeper  100"),
        ("card", 0.49, 0.95, "Team sheet"),
    ]),
}


def stretch_wide(art, width):
    if width <= art.width:
        return art
    c = art.width // 3
    out = Image.new("RGBA", (width, art.height))
    out.alpha_composite(art.crop((0, 0, c, art.height)), (0, 0))
    out.alpha_composite(art.crop((c, 0, art.width - c, art.height)).resize((width - 2 * c, art.height), Image.NEAREST), (c, 0))
    out.alpha_composite(art.crop((art.width - c, 0, art.width, art.height)), (width - c, 0))
    return out


def plate(img, words, x, y, colour=CREAM):
    w = pixfont.width(words)
    img.alpha_composite(Image.new("RGBA", (w + 14, 26), (0, 0, 0, 150)), (x - 7, y - 4))
    pixfont.draw(img, words, x, y, colour)


def tag(img, x, y, lines):
    art = TAG.resize((TAG.width * 2, TAG.height * 2), Image.NEAREST)
    widest = max(pixfont.width(l) for l in lines)
    width = widest + 130
    high = 22 * len(lines) + 22
    # Stretch the paper: left end (hole and string) and right end kept.
    left, right = art.crop((0, 0, 48, art.height)), art.crop((art.width - 40, 0, art.width, art.height))
    mid = art.crop((48, 0, art.width - 40, art.height))
    body = Image.new("RGBA", (width, art.height))
    body.alpha_composite(left, (0, 0))
    body.alpha_composite(mid.resize((width - 88, art.height), Image.NEAREST), (48, 0))
    body.alpha_composite(right, (width - 40, 0))
    body = body.resize((width, high), Image.NEAREST)
    img.alpha_composite(body, (x, y))
    for i, line in enumerate(lines):
        pixfont.draw(img, line, x + 74, y + 11 + i * 22, INK if i == 0 else (96, 50, 20), shadow=False)


def card(img, cx, y, words):
    art = CARD.resize((CARD.width * 2, CARD.height * 2), Image.NEAREST)
    art = stretch_wide(art, max(art.width, pixfont.width(words) + 36))
    img.alpha_composite(art, (cx - art.width // 2, y))
    pixfont.draw(img, words, cx - pixfont.width(words) // 2, y + art.height // 2 - 4, INK, shadow=False)


def build(look_id, title, status, marks):
    img = Image.open(os.path.join(SCREENS, "clubhouse.png" if look_id.startswith("club")
        else "training.png")).convert("RGBA")
    x0, y0, x1, y1 = INSIDE
    scene = Image.open(os.path.join(HERE, look_id + ".png")).convert("RGBA")
    rw, rh = x1 - x0, y1 - y0
    s = max(rw / scene.width, rh / scene.height)
    pic = scene.resize((round(scene.width * s), round(scene.height * s)), Image.NEAREST)
    off = ((rw - pic.width) // 2, rh - pic.height)
    room = Image.new("RGBA", (rw, rh))
    room.alpha_composite(pic, off)
    img.alpha_composite(room, (x0, y0))

    def at(fx, fy):
        return round(x0 + off[0] + fx * pic.width), round(y0 + off[1] + fy * pic.height)

    for mark in marks:
        kind = mark[0]
        if kind == "glow":
            ax, ay = at(mark[1], mark[2])
            bx, by = at(mark[1] + mark[3], mark[2] + mark[4])
            ImageDraw.Draw(img).rounded_rectangle([ax, ay, bx, by], 8, outline=GOLD, width=3)
    for mark in marks:
        kind = mark[0]
        if kind == "card":
            cx, cy = at(mark[1], mark[2])
            card(img, cx, min(cy, y1 - 50), mark[3])
        elif kind == "lock":
            cx, cy = at(mark[1], mark[2])
            card(img, cx, cy, "LOCKED - earn Ten Wins")
    for mark in marks:
        if mark[0] == "tag":
            tx, ty = at(mark[1], mark[2])
            tag(img, tx, ty, mark[3])
    plate(img, status, x0 + 18, y0 + 14)

    out = os.path.join(HERE, "mockup_%s.png" % look_id)
    img.convert("RGB").save(out)
    print("wrote", os.path.basename(out))
    return out


if __name__ == "__main__":
    made = {k: build(k, *v) for k, v in LOOKS.items()}
    for group in ("club", "train"):
        paths = [p for k, p in made.items() if k.startswith(group)]
        tw, th = 890, 500
        sheet = Image.new("RGB", (tw * len(paths) + 10 * (len(paths) - 1), th), (30, 30, 30))
        for i, p in enumerate(paths):
            sheet.paste(Image.open(p).resize((tw, th)), (i * (tw + 10), 0))
        name = "sheet_clubhouse.png" if group == "club" else "sheet_training.png"
        sheet.save(os.path.join(HERE, name))
        print("wrote", name)
