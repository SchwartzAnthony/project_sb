# THE ART STYLE

## The new look (13 Oct 2026)

You wiped the old look on 13 Oct. Everything in the game today is
placeholder art. The new style comes from **your own Midjourney pictures**,
with Marcinelle school comics (Spirou, Dupuis) at its core: big wild eyes,
thick bold ink lines, cartoon faces with huge expressions, detail in clothes,
hair and shoes.

- **Who draws:** fal.ai. Seedream 4 makes first drafts from your pictures
  (about 3 cents each). Sunburst fixes spots, makes new poses and see-through
  stickers (about 4 to 6 cents). PixelLab is no longer used for new art.
- **Nothing is paid without your OK** in the thread. Every job is logged in
  the Art Desk's "Jobs & money" tab with its cost.
- **Characters:** pick one of 8 options as the model sheet, then moods,
  side view and poses from it. Finished: Head Coach, Hanna, Koch. Each has
  "watch for" rules (Jobs & money tab) that go with every edit.
- **The Art Desk** (https://claude.ai/artifact/L3TBrS1q71nwZ2DxsAUCGL):
  - **Stickers:** build backgrounds from a grass tile and stickers.
  - **Parts:** cut parts out, paint, recolour. "Fix this spot" asks for a
    paid redraw of only the part you circle.
  - **Animate:** puppet pieces, turning points, keyframes, sprite sheet.
  - **Sketch:** draw or photograph a sketch; it comes back in our style.
  - **Jobs & money:** waiting jobs, the fal.ai balance, character rules.
  - "Send to game" on a sticker, scene or animation asks Claude to put it in
    the right game folder and CSV.
- **Say "run my jobs"** in the art thread to start everything waiting.

---

# The art bible

> 1990s European comic book art style, Marcinelle school, Walter Moers / Kleines Arschloch style, thick bold ink lines, flat bold colors, dark humor, Oktoberfest theme.

It lives in `data/ArtStyle.csv` with the other style rows (look rules,
generators, references). On 14 Oct the words "pixel art" came out: the new
pictures are ink comics. "Dark humor" stayed.

# The placeholder art, and what keeps it working

Everything in the game today was made the old way (PixelLab, OpenAI,
pixelated). It stays until each picture is replaced. These keep it
building, so they stay too, but nothing new is made with them:

- `tools/pixelate.py` with `data/Pixelate.csv`, and the `make_*.py`
  builders (base town, village, pitch, banners, font, Aseprite files).
- The masters they read: `art_source/pixellab/`, `art_source/openai/`,
  `art_source/legacy/`, `art_source/aseprite/`.

Removed on 14 Oct because nothing used them any more: the prompt builder
(`tools/art_prompt.gd`), the PixelLab work orders (`data/ArtOrders.csv`,
`tools/art_status.py`, `tools/cut_chrome.py`), the tool comparison
(`art_source/compare/`) and the old prompt rows in `ArtStyle.csv`.
