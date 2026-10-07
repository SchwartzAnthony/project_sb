#!/usr/bin/env python3
# =============================================================
#  THE MATCH LOADING SCREEN AS ONE LAYERED ASEPRITE FILE  (round AN)
#
#      ~/.venvs/sturmball/bin/python tools/make_loading_aseprite.py
#
#  Three layers - the Alps, the goal, the ball - on a 688 x 384 canvas, laid
#  out the way match_loader.gd lays them out with the Tuning.csv numbers
#  (match_loader_ground, _goal_size, _ball_size). Writes
#  art_source/aseprite/match_loading.aseprite. Edit a layer in Aseprite and
#  export it back over its PNG in assets/loading/.
# =============================================================
import csv
import os
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_aseprite import HERE, write_aseprite  # noqa: E402

W, H = 688, 384


def tuning():
    out = {}
    with open(os.path.join(HERE, "data/Tuning.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            out[(row.get("Key") or "").strip()] = (row.get("Value") or "").strip()
    return out


def picture(t, key, fallback):
    path = t.get(key) or fallback
    return Image.open(os.path.join(HERE, path.replace("res://", "", 1))).convert("RGBA")


def main():
    t = tuning()
    ground = float(t.get("match_loader_ground") or 0.93)
    goal_share = float(t.get("match_loader_goal_size") or 0.26)
    ball_share = float(t.get("match_loader_ball_size") or 0.08)

    back = picture(t, "match_loader_background", "res://assets/loading/alps_background.png")
    s = max(W / back.width, H / back.height)
    back = back.resize((round(back.width * s), round(back.height * s)), Image.NEAREST)

    goal = picture(t, "match_loader_goal", "res://assets/loading/goal.png")
    gh = round(H * goal_share)
    goal = goal.resize((round(gh * goal.width / goal.height), gh), Image.NEAREST)
    ball = picture(t, "match_loader_ball", "res://assets/loading/ball.png")
    bs = round(H * ball_share)
    ball = ball.resize((bs, bs), Image.NEAREST)

    ground_y = round(H * ground)
    goal_x = W - goal.width - round(W * 0.03)
    layers = [
        ("01 alps_background", back, (W - back.width) // 2, (H - back.height) // 2),
        ("02 goal", goal, goal_x, ground_y - goal.height),
        # The ball halfway along its roll, so it can be seen.
        ("03 ball", ball, (goal_x + goal.width // 2 - bs) // 2, ground_y - bs),
    ]
    out = os.path.join(HERE, "art_source/aseprite/match_loading.aseprite")
    write_aseprite(out, W, H, layers)
    print("  wrote %s: %dx%d, %d layers" % (out, W, H, len(layers)))


if __name__ == "__main__":
    main()
