# Adventure look - drafts (10 Oct 2026)

Small PixelLab drafts (create_image_pro, style image = `art_source/style_refs/stammtisch/board_places.png`).
Four options each. Pick one per row; finals are only made after your OK.

| Piece | Sheet | Draft size | Final size |
|---|---|---|---|
| Soccer & training board | `SHEET_board.png` | 160x112 | 688x384, board EMPTY (the game pins the scrolls on it) |
| Beer cave background | `SHEET_beer_cave.png` | 170x96 | 688x384 |
| Contract scroll window | `SHEET_scroll.png` | 96x160 | 384x688 |
| Isometric Marsh background | `SHEET_marsh_iso.png` | 170x96 | 688x384 |
| Adventure map / tile style | `SHEET_map_style.png` | 170x96 | 688x384 + iso tiles, drops and enemies as small sets |

Notes
- The boards came back with scribbles that look like words (WANTED, TACTICS).
  The final will ask for blank papers, because the real scroll names are drawn
  by the game from Bounties.csv.
- Every prompt ends with the art bible (built the same way as `tools/art_prompt.gd`).
- Finals will be layered (background, props, light/mist ...) + `.aseprite` in `art_source/aseprite/`.

## PixelLab orders (subjects; the clean rules + art bible are added after each)
- board: A big wooden notice board for a Bavarian village football club, carved oak frame with a painted football and crossed beer mugs on top, covered with pinned rolled paper scrolls, wanted posters of monsters, chalk tactics diagrams and training timetables, nails and red wax seals, front view.
- beer_cave: A mysterious Bavarian beer cave under a football ground, vaulted stone cellar with huge oak beer barrels, flickering torches, old torn football club banners and pennants on the walls, a glowing doorway deep in the back, mossy steps, mist on the floor, wide empty space in the middle for a notice board.
- scroll: An unrolled parchment contract scroll hanging open, dark wooden rods with brass knobs at the top and bottom, the paper filled with a light tan colour, a red wax seal with a football on it near the bottom, slightly torn edges, front view, empty paper with no writing.
- marsh_iso: Isometric view of a Bavarian marsh, a wide flat green football-sized clearing of wet grass in the middle surrounded by reed beds, dark pools of bog water, crooked willow trees, an old wooden boardwalk, a sunken goal post, will-o-wisps glowing in the mist, seen from above at a 2:1 isometric angle.
- map_style: An isometric adventure map like a 1980s Bavarian fantasy role-playing game board from a European comic book, diamond-shaped grass and marsh tiles joined by a winding dirt path with round stepping-stone stops, small tents, a wooden footbridge, little monsters waiting on some stops, sacks of loot on others, a castle ruin at the far end, seen from above at a 2:1 isometric angle.

## Finals (10 Oct, Anthony: "continue please")
Made from: board 2, cave 3, scroll 1, marsh 3. The map style waits for QAL1.
Parts and every candidate: `art_source/adventure_look/parts/`; layer CSVs
`art_source/adventure_look/*.csv` (rebuild with `tools/compose_layers.py`);
layered files `art_source/aseprite/adventure/`. In-game screenshots: `screens/`.
The big scroll final came back broken (PixelLab mixed the style board into
it), so the open scroll uses draft option 1 at a whole-pixel zoom.
