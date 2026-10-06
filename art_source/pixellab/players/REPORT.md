# Players: one PixelLab sprite sheet per class (round AN)

The 27 old files in assets/players/ were two identical placeholder sheets
(white kit / dark striped kit) used by every class. They are left in place.

New: one character per class, PixelLab `create_character` (size 32, low
top-down view) + `animate_character` (south-east, 3/4 view facing right).
Prompts from `tools/art_prompt.gd -- pixellab`. 60 generations.

| Class | Look | Ability animation |
|---|---|---|
| Lorelei | blue-green skin, long golden hair, teal striped shirt | arms spread, siren song |
| Rauhnacht-Feuergeister | flame hair, ember skin, black and orange kit | bursts into flame |
| Bergmännlein | white-bearded dwarf, red miner's cap with lamp | pounds the ground |
| Unkengeister | squat green toad, murky green kit | throat puffs up, hop |
| Normal | ordinary bloke, red and white kit | claps over his head |
| Rivals | scruffy journeyman, faded blue-grey kit | shoulder barge |

- Sheets: assets/players/class_<Class>.png, 1536x2496 = 12 x 39 cells of
  128x64, rows as in data/Animations.csv (idle 0, ability 3, run 8, kick 12,
  lose 19, win 38); unused rows repeat idle. Feet on y=48, centred on x=64.
- Aseprite: art_source/aseprite/players/class_<Class>.aseprite (one layer
  per animation row).
- Preview: preview.png. Masters: <Class>/ (PixelLab zip, frames, metadata).
- Wired in through data/Tuning.csv placeholder_art_<Class> rows;
  BasicEnemyTeam.csv (Rivals) points at class_Rivals.png.

Notes: create_character takes no style image, so the art bible text carries
the style. Size-48 versions (bigger, clearer) are in size48_unused/. Runs
look like a jog. Some kick frames draw their own ball.
