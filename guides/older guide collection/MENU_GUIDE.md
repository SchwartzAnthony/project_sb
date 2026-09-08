# The menus, and how to change them without code

Four screens, in this order:

```
Main Menu  →  Choose Your Class  →  Build Your Team  →  Match
```

Everything you can see on them — the buttons, the class names and blurbs, the
banner art, which cards you are allowed to field — is a row in a CSV or a PNG
in a folder. The rules are the same as the rest of the game: **column order
does not matter, capitals and spaces and underscores are ignored, extra
columns are skipped, and a missing file falls back to something sensible
rather than crashing.**

---

## Where the art goes

```
res://assets/menu/
├── background.png              full-screen art behind the main menu
├── button_start.png            one PNG per button (optional)
├── button_quick.png
├── button_quit.png
├── banner_brandteufel.png      one per class, shown on class select (optional)
└── banner_lorelei.png
```

Every one of these is optional. With the folder empty you get plain framed
buttons and a dark background, and the whole flow still works — so you can
play now and draw later.

Suggested sizes: buttons **260 × 68**, banners **900 × 300**, background at
least **1280 × 720**. Nothing enforces these; art is scaled to whatever the
CSV says the box is.

---

## 1. Main menu — `res://data/MenuConfig.csv`

```csv
Button ID,Label,X,Y,Width,Height,Action,Art Path,Notes
START_GAME,Start Game,640,400,260,68,start_game,res://assets/menu/button_start.png,Goes to class select
QUICK_MATCH,Quick Match,640,484,260,68,quick_match,res://assets/menu/button_quick.png,Skips team building
QUIT,Quit,640,568,260,68,quit_game,res://assets/menu/button_quit.png,Closes the game
```

| Column | What it does |
|---|---|
| `Button ID` | your own label for the row. The game ignores it — it is for you |
| `Label` | the words on the button, when there is no art |
| `X` / `Y` | the **centre** of the button on screen. 640, 360 is the middle of a 1280 × 720 window |
| `Width` / `Height` | the button's box |
| `Action` | **the only column that changes behaviour** — see below |
| `Art Path` | a PNG to wear instead of the label. Wrong or missing path = plain button, and a note in the Output panel |

### The four Action words

| Action | What happens |
|---|---|
| `start_game` | class select → team builder → match |
| `quick_match` | straight to a match with a random class and roster |
| `open_settings` | placeholder — says "not built yet" |
| `quit_game` | closes the game |

Add a row with a word that is not on this list and the game says so in the
Output panel rather than doing something surprising. New actions are the one
thing here that needs a code change, and it is a two-line one — tell me the
button you want and I will add the word.

**Reordering or moving buttons:** change the `Y` numbers. Nothing else.
**Removing a button:** delete its row.

---

## 2. Class select — `res://data/ClassInfo.csv`

This screen builds its class list **automatically** from your unit CSVs.
Any class with at least one `Player Type = Star` row appears here on the next
launch. You do not have to register it anywhere.

`ClassInfo.csv` is purely cosmetic — it dresses up a class that is already
there:

```csv
Class,Display Name,Description,Banner Art,Formation Art,Notes
Brandteufel,Brandteufel,Fire-born forwards who trade defence for raw pressure.,res://assets/menu/banner_brandteufel.png,,
```

| Column | What it does |
|---|---|
| `Class` | **must match the `Unit Type` column in your unit CSV**, spelling ignored for case and spaces |
| `Display Name` | a prettier name for the button and heading. Blank = use the raw class name |
| `Description` | the blurb under the title |
| `Banner Art` | a wide PNG across the top of the panel |
| `Formation Art` | a picture of the formation. **Leave blank** and the game draws the formation diagram itself |

No row for a class? It still shows up, just with its plain name and no blurb.

### What the screen shows you

- **The three Star Players**, as clickable cards. Click one to read its full
  card — power, the printed Attack and Defend text, and, when the card points
  at a row in `Abilities.csv`, that ability written out as a sentence.
- **A roster health check.** Each tier is counted against the 3-cards-per-tier
  rule and flagged in orange if it is short. This is the cheapest place to
  notice a CSV problem — much better than finding out mid-match.
- **The formation**, drawn from your Star's tier. The Star stands alone in its
  own column; the other three tiers have three each.

---

## 3. Team builder

The left column is your team, Tier I at the top down to Tier IV. The right
column is your collection.

- **Click a card on the right** → it drops into the first free slot of its own
  tier. A Tier II card can only ever go in Tier II.
- **Click a card on the left** → it goes back to the collection.
- **Right-click any card** → read its full card.
- **AUTO-FILL** fills every empty slot at random. The screen opens already
  auto-filled, so you can hit READY straight away and tune later.
- **CLEAR** empties every unlocked slot.

**The Star tier is locked.** Your three Star Players always hold it, and the
match rotates through them at each HOLD UP! — that is the design, so there is
nothing to choose there. It is drawn in amber with a padlock so it reads as
deliberate rather than broken.

**READY** only lights up when all three unlocked tiers hold three cards each.
Until then the bar along the bottom tells you exactly what is missing.

### Limiting the collection — `res://data/Collection.csv` (optional)

By default you can field every card of your class. To model unlocks, add:

```csv
Card Name,Owned,Notes
Emberling,true,starter
Cinderfoot,true,starter
Ashling,false,not unlocked yet
```

Cards marked `false` disappear from the collection. **A card not listed in the
file at all stays available**, so you only have to write down the ones you want
to hide — a half-finished file is harmless. Delete the file and everything is
available again.

---

## Adding a whole new class, start to finish

Nothing below is code.

1. **Cards.** Export a CSV into `res://data/` with the same headers as your
   existing unit files. Three rows with `Player Type = Star`, all sharing one
   Tier; nine `Normal` rows, three in each of the other three tiers.
2. **Art.** Put the card spritesheets in `res://assets/players/`, named exactly
   as each row's `Artwork` column says.
3. **Keeper.** Add a row to `Goalies.csv` whose `Team` matches the new
   `Unit Type` exactly.
4. **Launch.** The class is on the class select screen.
5. *Optional:* a `ClassInfo.csv` row for the blurb and banner.
6. *Optional:* `res://src/formations/<class>_formation.tscn` to hand-place the
   pitch positions. Without one, a formation is generated.

The class select screen's roster health check tells you immediately if step 1
came out wrong.

---

## What is still hard-coded

Being straight with you about the edges, so nothing surprises you later:

- **Three cards per tier, four tiers.** Changing that is a code change.
- **The four Action words** on the main menu. New ones need two lines added.
- **Screen layout** — which panel is left and which is right, the fonts, the
  spacing. The colours all live in one block at the bottom of
  `menu_support.gd` (`COLOUR_ACCENT`, `COLOUR_PANEL`, and so on) if you want
  to reskin without touching anything structural.
- **The formation diagram** is drawn to the same 3 × 3 shape the match uses.
  Point `Formation Art` at a PNG to override it with your own picture.

Everything else — classes, cards, abilities, art, buttons, unlocks, balance,
pacing — is a CSV row or a file in a folder.
