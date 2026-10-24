"""The drawn keeper (Anthony 24 Oct 2026, paid round rgk1: the round 11 yellow keeper, a side idle clip for the
pitch and a front dive clip for the shot window, both on flat magenta).

    python3 tools/make_keeper_sheets.py   (needs opencv-python-headless, numpy, Pillow)

Reads art_source/keeper/*.mp4 and writes assets/players/keeper/:
  keeper_pitch_home.png   side on, facing right (the home goal is on the left), swaying on the spot; a strip
  keeper_pitch_away.png   the same in a green kit for the other side (the match mirrors him)
  keeper_window.png       front on: frame 0 = ready with the ball, then the dive to his right
  keeper_window_away.png  the same in the green kit (their keeper, when you shoot)
Frame counts and sizes go in data/GoalieLook.csv."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from keeper_cut import frames, cut, strip

SRC = ROOT / 'art_source/keeper'
OUT = ROOT / 'assets/players/keeper'


def green_kit(im):
    """Yellow kit to green: only the strong yellows move, skin and outlines stay."""
    hsv = np.array(im.convert('RGB').convert('HSV')).astype(np.int16)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    yellow = (h >= 25) & (h <= 52) & (s > 110) & (v > 90)
    h = np.where(yellow, h + 45, h)
    out = Image.fromarray(np.dstack([h, s, v]).clip(0, 255).astype(np.uint8), 'HSV').convert('RGBA')
    out.putalpha(im.getchannel('A'))
    return out


def no_white_patch(im):
    """The start picture had a white patch between his legs (the old sticker's background)."""
    a = np.array(im); bb = im.getbbox(); top = bb[1] + int((bb[3] - bb[1]) * 0.62)
    white = (a[..., 0] > 228) & (a[..., 1] > 228) & (a[..., 2] > 228)
    white[:top] = False
    a[white, 3] = 0
    return Image.fromarray(a)


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    idle = frames(str(SRC / 'keeper_side_idle.mp4'))
    ims = [cut(idle[i]) for i in range(0, 120, 4)]
    strip(ims, 200, OUT / 'keeper_pitch_home.png')
    strip([green_kit(im) for im in ims], 200, OUT / 'keeper_pitch_away.png')
    dive = frames(str(SRC / 'keeper_front_dive.mp4'))
    picks = [44, 47, 50, 53, 56, 72, 76, 80, 84, 88, 92, 96]      # no take-off dust, no floating ball
    window = [no_white_patch(cut(dive[0]))] + [cut(dive[i]) for i in picks]
    strip(window, 520, OUT / 'keeper_window.png')
    strip([green_kit(im) for im in window], 520, OUT / 'keeper_window_away.png')
