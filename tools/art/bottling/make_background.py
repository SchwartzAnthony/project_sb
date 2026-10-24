# Free: the Bottling game's background = rbt2, the inside of the drawn Bottling Machine framing the hall wall (Anthony, 24 Oct).
# Usage (repo root): make_background.py /mnt/project-files/art_tool/rounds/rbt2/out/rbt2-machine-inside-wall.png
import sys
from PIL import Image
Image.open(sys.argv[1]).convert('RGB').resize((1280, 640), Image.LANCZOS).save('assets/brewery/games/bottling/background.png')
