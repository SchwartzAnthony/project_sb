# THE ART STYLE: Stammtisch-Comic (round AM)

**This is Sturmball's art style from now on.** It comes from your Midjourney
pictures in `assets/references/`. Short-named copies and two style boards
are in `art_source/style_refs/stammtisch/`:
- `board_characters.png`: the brewer, the brew keeper, the Marsh King, the
  Brandteufel, two kickers, the scout and Lorelei;
- `board_places.png`: the beer-town maps, the Rhine, the bog, the fire beer
  and the stone.

**What it is:** a chaotic, crazy 1980s–90s German humour comic.
- **Ink:** thick, wobbly, energetic black ink, with scratchy hatching and
  cross-hatching in the shadows.
- **Colour:** very saturated, slightly gaudy (fire-engine red, cobalt blue,
  egg-yolk yellow, grass green, pink flesh), with marker-like gradients and
  white highlights.
- **Detail:** busy and dense, packed with funny little details.

**The character bible.** It's the same on every person and creature; only the
body proportions change:

| | always |
|---|---|
| eyes | big white ovals, small black pupils, heavy lids |
| nose | a huge round bulbous pink-red potato nose |
| mouth | wide, with big blocky white teeth or a gap-tooth grin |
| the rest | big floppy ears, ruddy cheeks and stubble, big four-fingered hands, huge clompy boots, wild scruffy hair |
| body | **pushed to an extreme**: beanpole-skinny and gangly, barrel-round and pot-bellied, tiny and squat, or huge. A skinny person and a fat person still clearly belong to the same world |

**The world bible:** buildings, trees, rocks and objects are drawn in the
same wobbly ink with scratchy hatching. They're crooked and bulging, and
overloaded with detail.

**Avoid** (this is what made round AL look "ChatGPT"): a clean vector look,
smooth digital shading, pastel, muted or brown-washed colours, a yellow or
sepia tint, the generic AI-cartoon look, anime and 3D.

**The words are in `data/ArtStyle.csv`:**
- `stammtisch_prompt` starts every prompt;
- `stammtisch_eyes`, `_nose`, `_mouth`, `_body`, `_world` and `_avoid` are
  the bible.

**How to use them:**
1. Every OpenAI prompt is `stammtisch_prompt`, then `SUBJECT: …`.
2. The reference image is `board_characters.png` for people and creatures,
   or `board_places.png` for places, buildings and objects. Add a sketch for
   the pose if you have one.
3. Use `input_fidelity` low and ask for a transparent background for a
   cut-out layer.
4. Then pixelate it with `tools/pixelate.py`: Smooth 3 (keeps the hatching)
   and 48 colours.

---

*Everything below is the earlier (round AK–AL) Marcinelle recipe, kept for
history.*

# The art style: Marcinelle school, then pixels

**Your references are in `art_source/style_refs/`. Keep them; they are the
style.** They are:

- Holger Aue's *Motomania* (covers and a strip);
- Ibáñez's *Clever & Smart* (covers);
- a Ralf König / Walter Moers-style black-and-white page;
- the comic soccer kicker.

## What makes it Marcinelle (and what doesn't)

| yes | no |
|---|---|
| ugly by **exaggeration**: a huge droopy or bulbous potato nose, bulging eyes with tiny pupils, buck or crooked teeth, a weak stubbly chin, big ears | ugly by **animal parts**: pig noses, a perfectly round ball head (round AJ) |
| gangly limbs and knobbly knees, **or** a pot belly on thin legs; enormous hands and feet | realistic proportions |
| bold, wobbly black **brush ink**, thick and thin strokes, sweat drops, motion lines | clean vector lines, glossy 3D or airbrush shading, anime |
| flat bright colours, 2–3 tones a shape | gradients |

## How a picture is made: always these two steps (round AL)

1. **The comic master: OpenAI** (gpt-image-1, through the Deck helper
   `tools/mcp/openai_images.mjs`).
   - **The prompt** is the `character_prompt` row of `data/ArtStyle.csv`,
     with the brackets filled in. It names the *school*, never a living
     artist: OpenAI refuses those, and the reference picture carries the style.
   - **The style reference** is `art_source/style_refs/ref_08.png`, your
     Midjourney kicker.
   - **A pose reference:** if you drew a sketch, it goes in second, for the
     pose only.
   - **Settings:** 1024 × 1536, transparent background, high quality, input
     fidelity low (so it borrows the style, not the exact picture).
   - **Where it goes:** `art_source/openai/<thing>/`.
2. **The pixel art.** A row in `data/Pixelate.csv`, then
   `python3 tools/pixelate.py`.
   - **Size:** about 280 px tall for a full figure, drawn 2× on screen.
   - **Colours:** 32.
   - **Ink:** 45.
   - **Smooth:** 7. This melts the painted hatching first, so the pixels
     come out clean and flat.

**Who makes what:** OpenAI makes the comic masters, PixelLab makes the pitch
sprites and animation, and Ludo and Suno make the music. Players on the
pitch stay simple pixel art. The menu, the bar, conversations and portraits
use this painted-then-pixelated look.
