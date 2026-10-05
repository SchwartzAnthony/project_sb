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
