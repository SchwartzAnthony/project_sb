# Title screen tool comparison (round AN)

Anthony wants the SAME title screen made from scratch by each tool, to see
which is best. Each set makes the same 7 layers with ONE tool only; the
merge (pixelating and stacking) is the same for every set, done by
`compose.py`.

Anthony's feedback that started this: the round AM pictures had **too many
unnecessary lines** (hatching) and a **bad yellow filter**. Clean lines,
flat bold colours, neutral white balance.

## The prompt

Never type style words yourself. Build every prompt with:

    ~/Desktop/Godot_v4.7.1-stable_linux.x86_64 --headless --path . --script res://tools/art_prompt.gd -- <tool> "<SUBJECT below>"

`<tool>` is `pixellab`, `ludo`, `openai` or `claude`. It prints the prompt
(the clean rules + the art bible from `data/ArtStyle.csv`).

**Reference picture:** for the three layers with people (crowd, brawl, hero)
pass `art_source/style_refs/stammtisch/board_characters.png` as the style
reference, if the tool takes one. The other layers: text only.

## The layers (files go in `art_source/compare/<set>/`)

| file | shape | SUBJECT |
|---|---|---|
| `bg.png` | wide, opaque, full frame | the back layer of a game title screen, one full-frame wide landscape: a bright blue sky with a few puffy clouds, distant snowy Alps, a line of round green trees, and an empty grass football pitch with white lines filling the lower third, seen low from the touchline. No buildings, no people |
| `brewery.png` | square-ish, cut-out | a traditional Bavarian brewery building: white walls, half-timbering, a red tiled roof, a copper chimney, flower boxes, a big wooden barrel by the door. One object, whole building in frame, on a transparent background |
| `tent.png` | square-ish, cut-out | an Oktoberfest beer tent with blue-and-white stripes, pennant flags on the poles, pretzel decorations over the entrance. One object, whole tent in frame, on a transparent background |
| `crowd.png` | wide, cut-out | a wide row of cheering Bavarian football fans, waist up, behind a low advertising board: lederhosen, Tyrolean hats, raised beer steins, scarves, comic faces with big potato noses and gap-tooth grins. A wide strip, on a transparent background |
| `brawl.png` | wide, cut-out | a comic dust-cloud brawl: two or three caricature footballers fighting inside a round cloud of dust, with a beer stein, a pretzel, a bratwurst, a football, stars and a boot flying out. On a transparent background |
| `sign.png` | wide, cut-out | a blank, wide wooden Oktoberfest sign board with a blue-and-white diamond border, hanging from two short chains, the middle EMPTY for a title. No letters. On a transparent background |
| `hero.png` | tall, cut-out | the front guy: a gangly, skinny Bavarian football fan in lederhosen and a green Tyrolean hat with a feather, wild hair, a huge potato nose, a gap-tooth grin, holding a foaming beer stein high in one hand, one boot on a football, full body, facing right. On a transparent background |

Cut-outs must have a real transparent background (remove it if the tool
can't). Save each layer as PNG with exactly the file name above.

## The merge

    ~/.venvs/sturmball/bin/python art_source/compare/compose.py <set> paint   # smooth pictures: pixelated the same way for all
    ~/.venvs/sturmball/bin/python art_source/compare/compose.py <set> pixel   # layers that are already pixel art

It writes `art_source/compare/<set>/title.png` (1920 x 1080). Positions and
sizes are in `layout.csv`.
