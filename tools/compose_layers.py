#!/usr/bin/env python3
# =============================================================
#  ONE PICTURE FROM ITS LAYERS  (adventure-look, 10 Oct 2026)
#
#      ~/.venvs/sturmball/bin/python tools/compose_layers.py art_source/adventure_look/marsh_iso.csv
#
#  A layer CSV lists the parts of one picture, bottom layer first:
#      Layer   a name for the layer (shown in Aseprite)
#      Image   the part's PNG (a res:// path or a path from the project root)
#      X, Y    where its top-left corner goes, in the picture's own pixels
#      Flip    yes = mirrored left to right
#  A row with Layer = canvas gives the size (X = width, Y = height), and its
#  Image is where the finished, flattened PNG is saved (the one the game uses).
#
#  It writes the flattened PNG AND a layered .aseprite beside the CSV's name
#  in art_source/aseprite/, so every part stays editable. Move a part by
#  changing X / Y here and running it again.
# =============================================================
import csv
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "tools"))
from make_aseprite import write_aseprite  # noqa: E402


def path_of(text):
    return os.path.join(HERE, text.replace("res://", "", 1))


def main():
    if len(sys.argv) < 2:
        print("usage: compose_layers.py <layers.csv>")
        sys.exit(1)
    sheet = sys.argv[1]
    width, height, out_png = 0, 0, ""
    layers = []
    with open(path_of(sheet), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            name = (row.get("Layer") or "").strip()
            image = (row.get("Image") or "").strip()
            x = int(float(row.get("X") or 0))
            y = int(float(row.get("Y") or 0))
            if name.lower() == "canvas":
                width, height, out_png = x, y, image
                continue
            if not name or not image:
                continue
            im = Image.open(path_of(image)).convert("RGBA")
            if (row.get("Flip") or "").strip().lower() == "yes":
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            layers.append(("%02d %s" % (len(layers) + 1, name), im, x, y))
    if width <= 0 or height <= 0:
        print("no canvas row (Layer = canvas, X = width, Y = height)")
        sys.exit(1)

    flat = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for _name, im, x, y in layers:
        # Through a canvas-sized sheet, so a part may hang off any edge.
        sheet_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        sheet_layer.paste(im, (x, y))
        flat.alpha_composite(sheet_layer)
    if out_png:
        os.makedirs(os.path.dirname(path_of(out_png)), exist_ok=True)
        flat.save(path_of(out_png))
        print("  wrote", out_png)

    # The .aseprite canvas can't hold a part hanging off its edge, so each
    # part is clipped to the canvas there (the PNG part keeps all of it).
    clipped = []
    for name, im, x, y in layers:
        left, top = max(0, -x), max(0, -y)
        right = min(im.width, width - x)
        bottom = min(im.height, height - y)
        if right <= left or bottom <= top:
            continue
        clipped.append((name, im.crop((left, top, right, bottom)), max(0, x), max(0, y)))
    base = os.path.splitext(os.path.basename(sheet))[0]
    ase = os.path.join(HERE, "art_source", "aseprite", "adventure", base + ".aseprite")
    write_aseprite(ase, width, height, clipped)
    print("  wrote %s: %dx%d, %d layers" % (os.path.relpath(ase, HERE), width, height, len(clipped)))


if __name__ == "__main__":
    main()
