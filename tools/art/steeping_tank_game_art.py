# Free: cuts the redrawn Steeping Tank stir game pictures (fal rounds r148-r150)
# to the size the game draws them, into assets/brewery/games/malthouse/.
# Usage: python3 tools/art/steeping_tank_game_art.py <rounds folder>
import sys
from PIL import Image
R = sys.argv[1].rstrip('/') + '/'
OUT = 'assets/brewery/games/malthouse/'
K = 0.33  # the tank picture (1536 wide) is drawn at a third of its size


def cut(im):
    return im.crop(im.getchannel('A').point(lambda a: 255 if a > 40 else 0).getbbox())


tank = Image.open(R + 'r148/out/r148-stir-tank-open.png').convert('RGBA')
tank.resize((round(1536 * K), round(1024 * K)), Image.LANCZOS).save(OUT + 'tank.png')
pad = cut(Image.open(R + 'r148/out/r148-stir-paddle.png').convert('RGBA'))
h = round(676 * K)
pad.resize((round(pad.width * h / pad.height), h), Image.LANCZOS).save(OUT + 'paddle.png')
mash = cut(Image.open(R + 'r149/out/r149-stir-mash.png').convert('RGBA'))
d = round(2 * 630 * K)
mash.resize((d, d), Image.LANCZOS).save(OUT + 'mash.png')
for n in ['small', 'medium', 'large']:
    c = cut(Image.open(R + f'r150/out/r150-clump-{n}.png').convert('RGBA'))
    s = 0.26 * 1536 / 1200 * K
    c.resize((round(c.width * s), round(c.height * s)), Image.LANCZOS).save(OUT + f'clump_{n}.png')
