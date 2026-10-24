# Free: the Bottling game's background = the drawn hall around the drawn Bottling Machine, soft and a bit darker.
# Usage (repo root): make_background.py
from PIL import Image, ImageFilter, ImageEnhance
h = Image.open('assets/brewery/brewery_hall.png').convert('RGBA')
h.alpha_composite(Image.open('assets/brewery/hall_bottling.png').convert('RGBA'))
c = h.crop((360, 420, 880, 680)).resize((1280, 640), Image.LANCZOS).convert('RGB').filter(ImageFilter.GaussianBlur(3))
ImageEnhance.Brightness(c).enhance(0.8).save('assets/brewery/games/bottling/background.png')
