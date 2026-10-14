# Sturmball: rules for Claude

Football autobattler with card duels, Bavarian folklore and Oktoberfest chaos,
built in Godot 4.7 by Anthony, a designer who doesn't code.

## THE ART BIBLE (never change, never paraphrase)

> 1990s European comic book art style, Marcinelle school, Walter Moers / Kleines Arschloch style, thick bold ink lines, flat bold colors, dark humor, Oktoberfest theme.

- It lives in `data/ArtStyle.csv`, row `art_bible` (rewritten 14 Oct 2026
  for the new look). If this file and the CSV ever differ, the CSV wins.
  `art_bible_no_names` is the same without names, for Sunburst.
- **The new look (Anthony, 13 Oct 2026): all art in the game today is
  placeholder.** The style comes from Anthony's own Midjourney pictures
  (`/mnt/project-files/art_tool/references/`), sent with every job. Published
  comics are a mood board only. The full guide is `guides/ART_STYLE.md`.
- **Generators on fal.ai** (key only in the cloud environment, never in chat):
  - **Seedream 4 edit** (`fal-ai/bytedance/seedream/v4/edit`, ~$0.03) for
    first drafts.
  - **Sunburst** (`openai/gpt-image-2.5/sunburst/edit`, ~$0.04-0.06) for
    spot fixes, new poses and see-through stickers. It refuses artist and
    comic names.
  - **Ask Anthony before every paid job** and quote his approving words in
    the job spec. Tiny test first. Log the cost on the Art Desk.
- **Character rules:** `/mnt/project-files/art_tool/characters/rules.json`
  plus his notes on the Art Desk. Every edit of a character sends its model
  sheet and these rules. Finished sets: Head Coach, Hanna, Koch
  (`/mnt/project-files/art_tool/characters/<name>/`).
- **Art Desk** (https://claude.ai/artifact/L3TBrS1q71nwZ2DxsAUCGL, source
  `/mnt/project-files/art_tool/desk/`): Stickers, Parts, Animate, Sketch and
  Jobs & money. Paid or game-side work waits in its Jobs list until Anthony
  says "run my jobs" in the thread.
- **Pictures stay in parts.** Backgrounds are a ground tile plus separate
  stickers (an Art Desk scene), so each piece can be changed on its own.
- **Placeholder art tools** (`tools/pixelate.py`, the `make_*.py` builders,
  `art_source/pixellab/`, `art_source/openai/`, `data/Pixelate.csv`) stay
  only to keep today's game building until each picture is replaced. Never
  make new art with PixelLab or them.
- Python tools on the Deck run with `~/.venvs/sturmball/bin/python` (Pillow and
  numpy live there; SteamOS's own Python has no pip).

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
