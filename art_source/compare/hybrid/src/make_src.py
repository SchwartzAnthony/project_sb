# Makes small source copies of the OpenAI paintings for PixelLab image_to_pixelart.
# Crops cut-outs to their visible area, scales to the output size, keeps transparency,
# and writes a data: URL text file next to each image.
import base64, io, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "openai")
TGT = {"bg": ("w", 512), "brewery": ("w", 256), "tent": ("w", 256), "crowd": ("w", 384),
       "brawl": ("w", 384), "sign": ("w", 384), "hero": ("h", 340)}

for n, (ax, v) in TGT.items():
    im = Image.open(os.path.join(SRC, n + ".png")).convert("RGBA")
    if n != "bg":
        im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox())
    w, h = im.size
    sz = (v, round(h * v / w)) if ax == "w" else (round(w * v / h), v)
    if max(sz) > 512:
        s = 512 / max(sz)
        sz = (round(sz[0] * s), round(sz[1] * s))
    r = im.resize(sz, Image.LANCZOS)
    b = io.BytesIO()
    if n == "bg":
        r.convert("RGB").save(b, "JPEG", quality=72)
        mime, ext = "image/jpeg", "jpg"
    else:
        r.quantize(48, method=Image.FASTOCTREE).save(b, "PNG", optimize=True)
        mime, ext = "image/png", "png"
    open(os.path.join(HERE, n + "." + ext), "wb").write(b.getvalue())
    u = "data:%s;base64,%s" % (mime, base64.b64encode(b.getvalue()).decode())
    open(os.path.join(HERE, n + ".dataurl.txt"), "w").write(u)
    open(os.path.join(HERE, n + ".wrapped.txt"), "w").write(
        "\n".join(u[i:i + 1000] for i in range(0, len(u), 1000)))
    print(n, sz, len(u))
