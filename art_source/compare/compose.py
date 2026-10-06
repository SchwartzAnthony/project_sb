#!/usr/bin/env python3
# Puts one set of layers together into a 1920 x 1080 title screen, the same
# way for every tool, so the tools can be compared fairly.
#
#   ~/.venvs/sturmball/bin/python art_source/compare/compose.py <set> [paint|pixel]
#
# <set> is a folder next to this file with bg.png, brewery.png, tent.png,
# crowd.png, brawl.png, sign.png and hero.png (see layout.csv).
#   paint (default): smooth pictures -> tools/pixelate.py turns each layer
#                    into pixel art at half size (Smooth 7, Neutral 0.5),
#                    then it is drawn x2, like the game does.
#   pixel:           the layers are already pixel art -> only scaled up with
#                    hard edges.
# Writes <set>/title.png (and <set>/px/ with the pixelated layers).
import csv, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import pixelate as px

W, H = 1920, 1080


def layer(path, height, cutout, mode, cache):
    if mode == "paint":
        if path not in cache:
            small = px.pixelate(path, max(1, height // 2), 32, cutout, 45, cutout, smooth=7,
                                aspect="" if cutout else "16:9", neutral=0.5)
            cache[path] = small
        small = cache[path]
        return small.resize((small.width * 2, small.height * 2), Image.NEAREST)
    im = Image.open(path).convert("RGBA")
    if cutout:
        box = im.getchannel("A").point(lambda v: 255 if v > 110 else 0).getbbox()
        if box:
            im = im.crop(box)
    # Exactly the layout height, hard edges: every layer ends up the size the
    # layout asks for, even if its pixels are then not all the same size.
    w = max(1, round(im.width * height / im.height))
    return im.resize((w, height), Image.NEAREST)


def main():
    name = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "paint"
    folder = os.path.join(HERE, name)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    cache = {}
    with open(os.path.join(HERE, "layout.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            x, y, h = int(row["X"]), int(row["Y"]), int(row["Height"])
            if row["Layer"] == "title":
                font = ImageFont.truetype(os.path.join(ROOT, "assets/fonts/Bonum-Bold.otf"), h)
                d = ImageDraw.Draw(canvas)
                d.text((x, y), "STURMBALL", font=font, anchor="mm", fill=(250, 214, 92),
                       stroke_width=5, stroke_fill=(20, 12, 6))
                continue
            path = os.path.join(folder, row["File"])
            if not os.path.isfile(path):
                print("  ! %s: missing %s" % (name, row["File"]))
                continue
            cut = row["Cutout"] == "yes"
            im = layer(path, h, cut, mode, cache)
            if not cut:
                # The back layer covers the whole screen.
                s = max(W / im.width, H / im.height)
                im = im.resize((round(im.width * s), round(im.height * s)), Image.NEAREST)
                canvas.alpha_composite(im, ((W - im.width) // 2, (H - im.height) // 2))
                continue
            if row["Flip"] == "yes":
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            canvas.alpha_composite(im, (x - im.width // 2, y - im.height // 2)) if (x - im.width // 2) >= 0 and (y - im.height // 2) >= 0 else paste_clipped(canvas, im, x - im.width // 2, y - im.height // 2)
    if mode == "paint":
        os.makedirs(os.path.join(folder, "px"), exist_ok=True)
        for path, small in cache.items():
            small.save(os.path.join(folder, "px", os.path.basename(path)))
    out = os.path.join(folder, "title.png")
    canvas.convert("RGB").save(out)
    print("  %s: %s" % (name, os.path.relpath(out, ROOT)))


def paste_clipped(canvas, im, x, y):
    layer_img = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer_img.paste(im, (x, y), im)
    canvas.alpha_composite(layer_img)


if __name__ == "__main__":
    main()
