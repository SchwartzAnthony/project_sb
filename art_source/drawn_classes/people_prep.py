"""Free: the club women and the Rival man (r184 stills, r185 run + kick clips, cut by key_cut.py into elements/<name>/frames/)
into game source frames in the repo's art_source/drawn_classes/<name>/ (144px cells like the elemental classes, own colours).
Only run and kick were drawn (Anthony 23 Oct, 'Women too': run and kick only). Standing is cut from the end of the kick clip;
tackle, fall and cheer hold that standing picture until their own clips are made."""
import glob, os
from PIL import Image
src = open('game_prep.py').read(); exec(src[:src.index("TH = '")])
OUT = f'{REPO}/art_source/drawn_classes'
C = 144; FEET = 138
def fit(im, extra=1.0):
    dy = 0
    while to_cell(im, extra, dy=dy).getbbox()[1] < 2 and to_cell(im, extra, dy=dy + 2).getbbox()[3] < C - 1 and dy < 80: dy += 2
    return to_cell(im, extra, dy=dy)
HOLD = {'tackle': 6, 'fall': 7, 'cheer': 9}     # frame counts of PitchAnims.csv
for name in ('woman_blonde_ponytail', 'woman_plaits', 'woman_bob', 'woman_afro_puffs', 'woman_ginger', 'rival_man_stubble'):
    fr = f'elements/{name}/frames'
    d = f'{OUT}/{name}'; os.makedirs(d, exist_ok=True)
    for f in glob.glob(f'{d}/*.png'): os.remove(f)
    L = lambda m: [Image.open(f) for f in sorted(glob.glob(f'{fr}/{m}_[0-9]*.png'))]
    for i, im in enumerate(resample(debob(L('run')), 8)): to_cell(im).save(f'{d}/run_w_{i + 1:02d}.png')
    for i, im in enumerate(L('kick')): fit(im).save(f'{d}/kick_w_{i + 1:02d}.png')
    idle = L('idle')
    for i, im in enumerate(idle): fit(im).save(f'{d}/idle_s_{i + 1:02d}.png')
    still = fit(idle[0])
    for mv, n in HOLD.items():
        for i in range(n): still.save(f'{d}/{mv}_s_{i + 1:02d}.png')
    print(name, len(glob.glob(f'{d}/*.png')))
