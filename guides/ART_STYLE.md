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

## How a picture is made: always these two steps

1. **The comic master.** PixelLab `create_image_pro`, 384 px:
   - **The prompt** is the rows of `data/ArtStyle.csv` (style, ugliness,
     line, colour), then what the picture is.
   - **The style image** is `art_source/style_refs/style_sheet.png`, with
     outline, detail and shading copied from it.
   - **A pose reference:** if you drew a sketch, it goes in as the pose.
   - **Where it goes:** `art_source/pixellab/<thing>/`.
2. **The pixel art.** A row in `data/Pixelate.csv`, then
   `python3 tools/pixelate.py`.
   - **Size:** half the master's size keeps the ink lines.
   - **Colours:** about 48.
   - **Fill Holes:** for white areas PixelLab made see-through.

**PixelLab is for art; Ludo is for music** (your round AK rule).
