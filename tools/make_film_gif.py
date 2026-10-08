"""Turn tools/play_maker_film.gd's frames into one GIF (round AN, 8 Oct).

    ~/.venvs/sturmball/bin/python tools/make_film_gif.py OUT.gif [TITLE]

Reads ~/.local/share/godot/app_userdata/Sturmball/play_maker_film/, keeps
every other frame before the Play Maker, every one after it and every
fourth one during it, stamps BEFORE / PLAY MAKER / AFTER in the corner and
shrinks it to 640 wide. A tool, not part of the game.
"""
import os
import sys

from PIL import Image, ImageDraw

FILM = os.path.expanduser("~/.local/share/godot/app_userdata/Sturmball/play_maker_film")
WIDTH = 640
STEP = {"before": 2, "during": 4, "after": 1}
WORDS = {"before": "BEFORE - open play", "during": "DURING - PLAY MAKER", "after": "AFTER - open play"}
COLOUR = {"before": (60, 160, 60), "during": (200, 140, 20), "after": (60, 160, 60)}


def main() -> None:
    out = sys.argv[1]
    title = sys.argv[2] if len(sys.argv) > 2 else ""
    rows = [line.split() for line in open(os.path.join(FILM, "frames.txt")) if line.strip()]
    frames = []
    seen = {}
    for index, stage in rows:
        seen[stage] = seen.get(stage, -1) + 1
        if seen[stage] % STEP.get(stage, 1):
            continue
        path = os.path.join(FILM, "f_%s.png" % index)
        if not os.path.exists(path):
            continue
        im = Image.open(path).convert("RGB")
        im = im.resize((WIDTH, int(im.height * WIDTH / im.width)), Image.LANCZOS)
        draw = ImageDraw.Draw(im)
        label = WORDS.get(stage, stage) + ("   " + title if title else "")
        draw.rectangle((0, im.height - 26, 9 * len(label) + 16, im.height), fill=COLOUR.get(stage, (0, 0, 0)))
        draw.text((8, im.height - 20), label, fill=(255, 255, 255))
        frames.append(im.quantize(colors=64, method=Image.Quantize.MEDIANCUT))
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=160, loop=0, optimize=True)
    print("%d frames -> %s (%.1f MB)" % (len(frames), out, os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    main()
