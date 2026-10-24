"""The goalie window's drawn pieces (Anthony 24 Oct 2026: the shootout window in our new art, picked from
the draft /mnt/project-files/art_tool/goalie/goalie_window_draft_v1.png).

    python3 tools/make_shootout_pieces.py

Writes assets/ui/shootout/:
  mat_panel.png        the beer mat cream panel (the inventory's piece of assets/cards/beermat_frame.webp),
                       at 0.9 size; its drawn edge is 54 pixels (ShootoutLook.csv mat_edge)
  mat_panel_small.png  the same at 0.6 size for the caption box; edge 36 (ShootoutLook.csv caption_edge)
  goal_stage.png       the village (art_source/shootout/village_goal_r127.png) with the goal drawn straight on;
                       where the goal is inside it goes in ShootoutLook.csv goal_box
  keeper_ready.png     the round 11 keeper (art_source/shootout/keeper_r11.webp, Anthony said yes 13 Oct),
                       stand-in until the drawn keeper sheets are in Goalies.csv
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets/ui/shootout'
INK = (25, 17, 10)
STAGE = (1100, 470)
# The goal inside the stage, as fractions: left, top, right, bottom (the crossbar's top to the goal line).
GOAL = (0.20, 0.14, 0.80, 0.80)


def mat():
    f = Image.open(ROOT / 'assets/cards/beermat_frame.webp').convert('RGBA')
    x, y, w, h = 0.0586, 0.7194, 0.8838, 0.14            # CardFace.csv sign
    piece = f.crop((int(x * f.width), int(y * f.height), int((x + w) * f.width), int((y + h) * f.height)))
    for name, k in (('mat_panel.png', 0.9), ('mat_panel_small.png', 0.6)):
        piece.resize((int(piece.width * k), int(piece.height * k)), Image.LANCZOS).save(OUT / name)


def stage():
    sw, sh = STAGE
    v = Image.open(ROOT / 'art_source/shootout/village_goal_r127.png').convert('RGBA')
    cw = 600
    st = v.crop((550, 455, 550 + cw, 455 + int(cw * sh / sw))).resize(STAGE, Image.LANCZOS)
    st = ImageEnhance.Sharpness(st).enhance(1.4)
    gx0, gtop, gx1, gfoot = int(sw * GOAL[0]), int(sh * GOAL[1]), int(sw * GOAL[2]), int(sh * GOAL[3])
    back, deep = 46, 28
    net = Image.new('RGBA', STAGE, (0, 0, 0, 0)); nd = ImageDraw.Draw(net)
    bx0, bx1, by0, by1 = gx0 + back, gx1 - back, gtop + deep, gfoot - deep
    nd.polygon([(bx0, by0), (bx1, by0), (bx1, by1), (bx0, by1)], fill=(255, 255, 255, 40))
    line = (238, 238, 238, 140)
    for k in range(0, gx1 - gx0 + 1, 18):
        x = bx0 + (bx1 - bx0) * k / (gx1 - gx0)
        nd.line((gx0 + k, gtop, x, by0), fill=line, width=2)
        nd.line((x, by0, x, by1), fill=line, width=2)
    for yy in range(by0, by1, 18):
        nd.line((bx0, yy, bx1, yy), fill=line, width=2)
    for xa, xb in ((gx0, bx0), (gx1, bx1)):
        for t in range(11):
            nd.line((xa, gtop + (gfoot - gtop) * t / 10, xb, by0 + (by1 - by0) * t / 10), fill=line, width=2)
    st.alpha_composite(net)
    d = ImageDraw.Draw(st)
    d.line((gx0 - 40, gfoot + 4, gx1 + 40, gfoot + 4), fill=(250, 250, 245), width=10)
    pw = 18
    for rect in ((gx0 - pw, gtop - pw, gx1 + pw, gtop), (gx0 - pw, gtop - pw, gx0, gfoot), (gx1, gtop - pw, gx1 + pw, gfoot)):
        d.rectangle(rect, fill=(250, 250, 248), outline=INK, width=4)
    st.convert('RGB').save(OUT / 'goal_stage.png')
    print('goal_box', ','.join(f'{v:.3f}' for v in GOAL))


def keeper():
    k = Image.open(ROOT / 'art_source/shootout/keeper_r11.webp').convert('RGBA')
    k = k.crop(k.getbbox())
    k.thumbnail((600, 600), Image.LANCZOS)
    k.save(OUT / 'keeper_ready.png')


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    mat(); stage(); keeper()
