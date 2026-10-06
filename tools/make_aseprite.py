#!/usr/bin/env python3
# =============================================================
#  LAYERED ASEPRITE FILES  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_aseprite.py data/MainMenu.csv art_source/aseprite/title_screen.aseprite
#      ~/.venvs/sturmball/bin/python tools/make_aseprite.py data/ScreenLook.csv art_source/aseprite/settings.aseprite settings
#
#  For a CSV with a Screen column (ScreenLook.csv), name the screen last.
#  Turns a layered screen (a CSV like MainMenu.csv: Part, Image, X, Y,
#  Width, Height, Scale, Flip) into ONE .aseprite file with one layer per
#  picture, in the same order (top row = bottom layer), so you can open the
#  whole screen in Aseprite and edit any part on its own.
#
#  The canvas is the screen in game pixels: 1920 x 1080 divided by the pixel
#  size (default 2, because every layer is drawn at Scale 2). A layer drawn
#  at Scale 2 goes in pixel for pixel. A layer drawn at another size is
#  resized to fit, and the script says so.
#  The title text is not a picture, so it is not a layer: the game writes it.
#
#  After editing in Aseprite, export each layer back to its PNG
#  (File > Export > Export As..., with "Layers" set to that one layer).
# =============================================================
import csv
import os
import struct
import sys
import zlib

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCREEN_W, SCREEN_H = 1920, 1080


def project_path(res_path):
    return os.path.join(HERE, res_path.replace("res://", "", 1))


def number(row, key, default=0.0):
    try:
        return float((row.get(key) or "").strip() or default)
    except ValueError:
        return default


def layers_from_csv(csv_path, pixel, screen=""):
    """[(name, RGBA image at canvas pixels, x, y)] bottom layer first."""
    cw, ch = SCREEN_W // pixel, SCREEN_H // pixel
    out = []
    with open(csv_path, encoding="utf-8") as f:
        for i, row in enumerate(csv.DictReader(f), start=2):
            if screen and (row.get("Screen") or "").strip().lower() != screen:
                continue
            part = (row.get("Part") or "").strip().lower()
            image = (row.get("Image") or "").strip()
            if part not in ("background", "picture") or not image:
                continue
            path = project_path(image)
            if not os.path.isfile(path):
                print("  ! row %d: no picture at %s - skipped" % (i, image))
                continue
            im = Image.open(path).convert("RGBA")
            name = "%02d %s" % (len(out) + 1, os.path.splitext(os.path.basename(path))[0])
            if part == "background":
                # Like the game: cover the whole screen, keep the shape.
                s = max(cw / im.width, ch / im.height)
                size = (round(im.width * s), round(im.height * s))
                if size != im.size:
                    print("  %s: resized %dx%d -> %dx%d to cover the canvas" % (name, im.width, im.height, size[0], size[1]))
                    im = im.resize(size, Image.NEAREST)
                out.append((name, im, (cw - im.width) // 2, (ch - im.height) // 2))
                continue
            frames = max(1, int(number(row, "Frames", 1)))
            if frames > 1:
                im = im.crop((0, 0, im.width // frames, im.height))
            scale = number(row, "Scale") or 1.0
            w = number(row, "Width") or im.width * scale
            h = number(row, "Height") or im.height * scale
            size = (max(1, round(w / pixel)), max(1, round(h / pixel)))
            if size != im.size:
                print("  %s: resized %dx%d -> %dx%d (drawn at a size other than Scale %d)" % (name, im.width, im.height, size[0], size[1], pixel))
                im = im.resize(size, Image.NEAREST)
            if (row.get("Flip") or "").strip().lower() == "yes":
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            x = round(number(row, "X") / pixel - im.width / 2)
            y = round(number(row, "Y") / pixel - im.height / 2)
            out.append((name, im, x, y))
    return cw, ch, out


def chunk(kind, data):
    return struct.pack("<IH", len(data) + 6, kind) + data


def write_aseprite(path, width, height, layers):
    """The .aseprite format (github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md):
    one frame, RGBA, one normal layer + one compressed cel per picture."""
    chunks = []
    for name, _im, _x, _y in layers:
        raw = name.encode("utf-8")
        # flags 3 = visible + editable; normal layer; blend normal; opacity 255
        chunks.append(chunk(0x2004, struct.pack("<HHHHHHB3x", 3, 0, 0, 0, 0, 0, 255) + struct.pack("<H", len(raw)) + raw))
    for index, (_name, im, x, y) in enumerate(layers):
        pixels = zlib.compress(im.tobytes(), 9)
        # cel type 2 = compressed image; z-index 0
        chunks.append(chunk(0x2005, struct.pack("<HhhBHh5x", index, x, y, 255, 2, 0) + struct.pack("<HH", im.width, im.height) + pixels))
    body = b"".join(chunks)
    frame = struct.pack("<IHHH2xI", 16 + len(body), 0xF1FA, min(len(chunks), 0xFFFF), 100, len(chunks)) + body
    # flags 1 = layer opacity is valid; 32 bits per pixel; pixel ratio 1:1
    header = struct.pack("<IHHHHHIHIIB3xHBBhhHH84x", 128 + len(frame), 0xA5E0, 1, width, height, 32, 1, 100, 0, 0, 0, 0, 1, 1, 0, 0, 16, 16)
    assert len(header) == 128
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(header + frame)


def main():
    if len(sys.argv) < 3:
        print("usage: make_aseprite.py <screen.csv> <out.aseprite> [screen]")
        sys.exit(1)
    screen = sys.argv[3].lower() if len(sys.argv) > 3 else ""
    width, height, layers = layers_from_csv(sys.argv[1], 2, screen)
    write_aseprite(sys.argv[2], width, height, layers)
    print("  wrote %s: %dx%d, %d layers" % (sys.argv[2], width, height, len(layers)))


if __name__ == "__main__":
    main()
