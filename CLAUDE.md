# Sturmball: rules for Claude

Football autobattler with card duels, Bavarian folklore and Oktoberfest chaos,
built in Godot 4.7 by Anthony, a designer who doesn't code.

## THE ART BIBLE (never change, never paraphrase)

> 1990s European comic book art style, Marcinelle school, Walter Moers / Kleines Arschloch style, flat bold colors, dark humor pixel art, Oktoberfest theme.

- It lives in `data/ArtStyle.csv`, row `art_bible`. That row is the master copy.
  If this file and the CSV ever differ, the CSV wins.
- **Every PixelLab prompt ends with this exact string.** Don't type style
  words into a prompt yourself. Build the prompt with the tool:
  `godot --headless --path . --script res://tools/art_prompt.gd -- pixellab "<what to draw>"`
- **OpenAI prompts** use `-- openai "<what to draw>"`. It uses the row
  `art_bible_openai` (the same words without the artist and comic names,
  which OpenAI refuses) after `stammtisch_prompt`.
- The recipes are the `recipe_pixellab` and `recipe_openai` rows. To add a
  tool, add a `recipe_<tool>` row.
- Style references: `art_source/style_refs/stammtisch/board_characters.png`
  (people and creatures) and `board_places.png` (places and objects).
  The full style guide is `guides/ART_STYLE.md`.
- **PixelLab ONLY for all game art** (Anthony, 6 Oct 2026): characters,
  buttons, frames, backgrounds, everything. Not OpenAI, Ludo.ai or
  hand-drawn. Use `create_image_pro` (largest sizes: 688x384, 384x688,
  512x512), with `board_characters.png` as the style image for people.
- **Every image stays in layers.** Generate each part separately (background,
  buildings, crowd, action, sign, hero ...), save one PNG per part, and write
  a layered `.aseprite` file with `tools/make_aseprite.py` so Anthony can edit
  it in Aseprite. Never hand over only a flattened picture.
- PixelLab quirk: background removal punches holes in white areas (e.g. a
  blank sign's middle). Ask for a coloured fill there.
- Python tools on the Deck run with `~/.venvs/sturmball/bin/python` (Pillow and
  numpy live there; SteamOS's own Python has no pip).
- Older pipeline, kept for history: OpenAI masters in `art_source/openai/`
  plus `tools/pixelate.py`.

## Standing rules

- Everything is data-driven from CSVs and folders, so a designer can extend
  it without code.
- Every round: update all affected CSVs, `sturmball_workbench.html` (built
  from `tools/workbench_src/` with `sh build.sh`) and
  `guides/DESIGNER_MANUAL.md`. Stamp the round in `data/Tuning.csv`
  `build_stamp`.
- Read `data/Questions.csv` for Anthony's answers, and write new questions
  there.
- Write short, clear guides. Raise questions, concerns and suggestions.
- Run and test the game yourself. Checks: `--import`, then `--check-only` on
  every `.gd`, `python3 tools/gd_lint.py`, and GUT with
  `godot --headless -s addons/gut/gut_cmdln.gd`.
- Work on a round branch (`round-AN` …). Never push to `main`; Anthony does.
- API keys live only in the Deck's Claude config. Never ask for them in chat.
