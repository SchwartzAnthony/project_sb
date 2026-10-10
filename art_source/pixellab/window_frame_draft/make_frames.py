#!/usr/bin/env python3
# =============================================================
#  THREE LOOKS FOR THE SHARED BUILDING WINDOW  (round AN, Anthony 10 Oct:
#  "everywhere" - the brown box with the title and the X round every
#  building screen)
#
#      ~/.venvs/sturmball/bin/python art_source/pixellab/window_frame_draft/make_frames.py
#
#  DRAFTS ONLY. Each look is a PixelLab frame (stretched as a nine-slice,
#  the way the game would), a title plate and a close button, put over real
#  screenshots of three building windows (tools/dorms_shot.gd). Writes
#      mockup_<look>_<screen>.png       to look at
#      layers_<look>/                   the pieces, cleaned, for Aseprite
#      sheet.png                        all nine side by side
# =============================================================
import collections
import os
import shutil
import sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "dorms_ui_draft"))
import pixfont  # noqa: E402

SHOTS = os.path.expanduser("~/.local/share/godot/app_userdata/Sturmball")
SCREENS = {"dorms": "DORMS", "clubhouse": "CLUB HOUSE", "brewery": "BREWERY"}
# base_window.gd MARGIN (90 x 64 each side), measured on the 1779 x 1001 shots.
RECT = (86, 62, 1693, 937)
# Where the old title bar ends (its separator line), to cover it.
TITLE_BOTTOM = 190

LOOKS = {
    "a_wood_brass": {"frame": "frame_a_01.png", "title": "title_a_03.png", "close": "close_a_00.png",
                     "ink": (40, 26, 12), "slice": 34, "scale": 2.0, "title_scale": 2.2, "close_scale": 1.6},
    "b_bavarian": {"frame": "frame_b_00.png", "title": "title_b_01.png", "close": "close_b_00.png",
                   "ink": (247, 233, 201), "slice": 30, "scale": 1.5, "title_scale": 2.2, "close_scale": 1.6},
    "c_beer_hall": {"frame": "frame_c_01.png", "title": "title_c_01.png", "close": "close_c_01.png",
                    "ink": (52, 30, 12), "slice": 34, "scale": 2.0, "title_scale": 2.2, "close_scale": 1.6},
}


def load(name):
    return Image.open(os.path.join(HERE, name)).convert("RGBA")


def cropped(im):
    return im.crop(im.getbbox())


def big(im, s):
    return im.resize((round(im.width * s), round(im.height * s)), Image.NEAREST)


def hollow(frame):
    """A frame PixelLab left with a white middle: flood the middle out."""
    w, h = frame.size
    px = frame.load()
    start = (w // 2, h // 2)
    if px[start][3] < 40:
        return frame
    seen, q = set(), collections.deque([start])
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        r, g, b, a = px[x, y]
        if a > 40 and min(r, g, b) < 225:
            continue
        px[x, y] = (0, 0, 0, 0)
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return frame


def nine_slice(art, size, cut, scale):
    """Stretch `art` to `size` keeping its corners: what a StyleBoxTexture does."""
    w, h = art.size
    out = Image.new("RGBA", size)
    c = cut
    sc = round(c * scale)
    xs_src, ys_src = [0, c, w - c, w], [0, c, h - c, h]
    xs_dst, ys_dst = [0, sc, size[0] - sc, size[0]], [0, sc, size[1] - sc, size[1]]
    for i in range(3):
        for j in range(3):
            box = (xs_src[i], ys_src[j], xs_src[i + 1], ys_src[j + 1])
            dw, dh = xs_dst[i + 1] - xs_dst[i], ys_dst[j + 1] - ys_dst[j]
            if dw <= 0 or dh <= 0:
                continue
            out.alpha_composite(art.crop(box).resize((dw, dh), Image.NEAREST), (xs_dst[i], ys_dst[j]))
    return out


def stretch_wide(art, width):
    """Make a plate wider by stretching its middle third: the ends keep
    their screws, chains or ropes."""
    if width <= art.width:
        return art
    c = art.width // 3
    out = Image.new("RGBA", (width, art.height))
    out.alpha_composite(art.crop((0, 0, c, art.height)), (0, 0))
    mid = art.crop((c, 0, art.width - c, art.height)).resize((width - 2 * c, art.height), Image.NEAREST)
    out.alpha_composite(mid, (c, 0))
    out.alpha_composite(art.crop((art.width - c, 0, art.width, art.height)), (width - c, 0))
    return out


def build(look_id, look):
    frame = hollow(cropped(load(look["frame"])))
    title = cropped(load(look["title"]))
    close = cropped(load(look["close"]))
    folder = os.path.join(HERE, "layers_" + look_id)
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    frame.save(os.path.join(folder, "frame.png"))
    title.save(os.path.join(folder, "title_plate.png"))
    close.save(os.path.join(folder, "close_button.png"))

    made = []
    for screen, words in SCREENS.items():
        shot = Image.open(os.path.join(SHOTS, screen + ".png")).convert("RGBA")
        x0, y0, x1, y1 = RECT
        # THE OLD TITLE BAR GOES and the screen moves up into its place:
        # the title is on the frame now, so the room gets that height back.
        fill = shot.getpixel((x0 + 300, y0 + 40))
        content = shot.crop((x0 + 4, TITLE_BOTTOM, x1 - 4, y1 - 4))
        shot.alpha_composite(Image.new("RGBA", (x1 - x0 - 8, y1 - y0 - 6), fill), (x0 + 4, y0 + 2))
        shot.alpha_composite(content, (x0 + 4, y0 + 52))
        pad = 14
        frame_img = nine_slice(frame, (x1 - x0 + pad * 2, y1 - y0 + pad * 2), look["slice"], look["scale"])
        shot.alpha_composite(frame_img, (x0 - pad, y0 - pad))
        tw = pixfont.width(words, 3)
        plate = big(title, look["title_scale"])
        plate = stretch_wide(plate, tw + round(plate.width * 0.45))
        px = (x0 + x1) // 2 - plate.width // 2
        py = y0 - plate.height // 2 + 10
        shot.alpha_composite(plate, (px, py))
        pixfont.draw(shot, words, px + plate.width // 2 - tw // 2, py + plate.height // 2 - 26,
                     look["ink"], 3, shadow=False)
        btn = big(close, look["close_scale"])
        shot.alpha_composite(btn, (x1 - btn.width // 2 - 6, y0 - btn.height // 2 + 6))
        out = os.path.join(HERE, "mockup_%s_%s.png" % (look_id, screen))
        shot.convert("RGB").save(out)
        made.append(out)
        print("wrote", os.path.basename(out))
    return made


if __name__ == "__main__":
    tiles = []
    for look_id, look in LOOKS.items():
        tiles.append(build(look_id, look))
    tw, th = 640, 360
    sheet = Image.new("RGB", (tw * 3 + 20, th * 3 + 20), (30, 30, 30))
    for r, row in enumerate(tiles):
        for c, path in enumerate(row):
            sheet.paste(Image.open(path).resize((tw, th)), (c * (tw + 10), r * (th + 10)))
    sheet.save(os.path.join(HERE, "sheet.png"))
    print("wrote sheet.png")
