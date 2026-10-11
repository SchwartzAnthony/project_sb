#!/usr/bin/env python3
# =============================================================
#  ISOMETRIC PITCH SHEETS  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_pitch_sheet.py art_source/pixellab/iso_players/club_m club_m
#
#  Takes a PixelLab character export (the unzipped download: metadata.json
#  plus its frames) and builds:
#    assets/players/pitch/<name>.png           the sheet the game plays
#    art_source/aseprite/players/pitch/<name>.aseprite   one layer per animation
#    art_source/pixellab/iso_players/<name>_preview.gif  every animation, south-east
#
#  Where each animation goes is data/PitchAnims.csv: First Row, then 8 rows
#  (east, south-east, south, south-west, west, north-west, north,
#  north-east). The PixelLab column is the animation's name in the export
#  (several separated by | : the first one the export has).
#  Frames are centred in square cells of Tuning.csv pitch_sheet_cell.
#  The script prints each animation's real frame count; if it differs from
#  the Frames column it says so.
# =============================================================
import csv
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_aseprite import write_aseprite  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRECTIONS = ["east", "south-east", "south", "south-west",
              "west", "north-west", "north", "north-east"]


def tuning(key, default):
    with open(os.path.join(HERE, "data/Tuning.csv"), newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if row and row[0] == key:
                return row[1]
    return default


def drop_specks(im, smallest=6):
    """PixelLab sometimes leaves loose dots round a figure (a dotted halo,
    a stray pixel). Any separate patch smaller than `smallest` pixels goes."""
    px = im.load()
    w, h = im.size
    seen = set()
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or px[x, y][3] == 0:
                continue
            patch, todo = [], [(x, y)]
            seen.add((x, y))
            while todo:
                cx, cy = todo.pop()
                patch.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and px[nx, ny][3] > 0:
                        seen.add((nx, ny))
                        todo.append((nx, ny))
            if len(patch) < smallest:
                for cx, cy in patch:
                    px[cx, cy] = (0, 0, 0, 0)
    return im


def anims():
    with open(os.path.join(HERE, "data/PitchAnims.csv"), newline="", encoding="utf-8") as f:
        return [r for r in csv.DictReader(f) if r.get("Animation", "").strip()]


def main():
    if len(sys.argv) < 3:
        print(__doc__ or "usage: make_pitch_sheet.py <export folder> <name>")
        sys.exit(1)
    src, name = sys.argv[1], sys.argv[2]
    cell = int(float(tuning("pitch_sheet_cell", 72)))
    meta = json.load(open(os.path.join(src, "metadata.json")))
    state = meta["states"][0]
    found = state["frames"]["animations"]
    rotations = state["frames"]["rotations"]
    rows = anims()
    cols = max(int(r["Frames"]) for r in rows)
    def export_of(r):
        # Several names separated by | : the first one the export has.
        for pl_name in r["PixelLab"].split("|"):
            if found.get(pl_name.strip()):
                return found[pl_name.strip()]
        return {}

    for r in rows:
        got = export_of(r)
        if got:
            cols = max(cols, max(len(v) for v in got.values()))
    height_rows = max(int(r["First Row"]) + 8 for r in rows)
    sheet = Image.new("RGBA", (cols * cell, height_rows * cell))
    layers = []

    def paste(target, path, col, row):
        im = drop_specks(Image.open(os.path.join(src, path)).convert("RGBA"))
        x = col * cell + (cell - im.width) // 2
        y = row * cell + (cell - im.height) // 2
        target.alpha_composite(im, (max(0, x), max(0, y)))

    for r in rows:
        anim, first = r["Animation"].strip(), int(r["First Row"])
        got = export_of(r)
        layer = Image.new("RGBA", sheet.size)
        counts = set()
        for d, direction in enumerate(DIRECTIONS):
            frames = got.get(direction)
            if not frames:
                # Missing direction: the standing drawing in every frame, so
                # nobody vanishes.
                print(f"  {anim}: no {direction} in the export, using the standing pose")
                frames = [rotations[direction]] * int(r["Frames"])
            counts.add(len(frames))
            for i, path in enumerate(frames[:cols]):
                paste(layer, path, i, first + d)
        sheet.alpha_composite(layer)
        layers.append((anim, layer, 0, 0))
        real = max(counts)
        note = "" if real == int(r["Frames"]) else f"   <- PitchAnims.csv says {r['Frames']}"
        print(f"{anim:8s} rows {first}-{first + 7}  frames {sorted(counts)}{note}")

    out = os.path.join(HERE, "assets/players/pitch", name + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    ase = os.path.join(HERE, "art_source/aseprite/players/pitch", name + ".aseprite")
    write_aseprite(ase, sheet.width, sheet.height, layers)

    # Preview: one row per animation, one column per direction (south
    # first, then turning round clockwise), every cell playing at its own FPS.
    order = [2, 3, 4, 5, 6, 7, 0, 1]
    ticks = 40
    gif_frames = []
    for t in range(ticks):
        fr = Image.new("RGBA", (8 * cell, len(rows) * cell), (95, 140, 70, 255))
        for a_i, r in enumerate(rows):
            first, n, fps = int(r["First Row"]), int(r["Frames"]), float(r["FPS"])
            step = int(t * 0.1 * fps)
            step = step % n if r["Loop"].strip().lower() == "true" else min(step % (n + 4), n - 1)
            for c, d in enumerate(order):
                box = (step * cell, (first + d) * cell, (step + 1) * cell, (first + d + 1) * cell)
                fr.alpha_composite(sheet.crop(box), (c * cell, a_i * cell))
        gif_frames.append(fr.resize((fr.width * 2, fr.height * 2), Image.NEAREST))
    gif = os.path.join(HERE, "art_source/pixellab/iso_players", name + "_preview.gif")
    os.makedirs(os.path.dirname(gif), exist_ok=True)
    gif_frames[0].save(gif, save_all=True, append_images=gif_frames[1:], duration=100, loop=0)
    print(f"wrote {out} ({sheet.width}x{sheet.height}), {ase}, {gif}")


if __name__ == "__main__":
    main()
