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
- Pipeline: OpenAI paints the comic master in `art_source/openai/stammtisch/`,
  `tools/pixelate.py` turns it into pixels (one row in `data/Pixelate.csv`),
  and every layer is shown at Scale 2. On the Deck, run it with
  `~/.venvs/sturmball/bin/python tools/pixelate.py` (Pillow lives in that
  venv; SteamOS's own Python has no pip). Players on the pitch stay simple
  PixelLab sprites.

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
