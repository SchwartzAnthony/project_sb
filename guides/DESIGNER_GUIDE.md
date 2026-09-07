# The designer's guide

This is step 1 of the base-building work: **the spine**. Nothing new is visible
on screen yet. What now exists is the machinery that buildings, the talent
tree, the pub, achievements and everything after them will hang off — and it is
all spreadsheets.

---

## ⚠ Do this first, or your exported build will ship empty

Every CSV in `data/` is currently being imported by Godot as a **translation
file**. That is what all those `Dialogue.Text.translation` files are.

In the editor everything works, because the real `.csv` is still sitting on
disk. **In an exported build it will not be there**, because Godot only ships
what the importer produced. The game would launch with zero cards, zero
dialogue and zero tuning.

**The fix, once per CSV:**

1. Click the `.csv` in the FileSystem dock
2. **Import** tab (next to Scene, top-left)
3. **Importer:** change to **"Keep File (No Import)"**
4. **Reimport**

You can select all the CSVs at once and do it in one go.

**Then belt-and-braces:** Project → Export → your preset → **Resources** tab →
**"Filters to export non-resource files/folders"** → put `*.csv` in it.

The `.translation` files can all be deleted afterwards.

---

## The idea

Everything the game remembers is one of four things:

| | | |
|---|---|---|
| **Flags** | on/off facts | `first_win`, `met_lorelei` |
| **Counters** | numbers | `goals` = 12, `matches_won` = 3 |
| **Texts** | words | `next_class` = "Lorelei" |
| **Unlocks** | a list of names you have earned | Brewery, Pub, Talent Tree |

**An achievement is a flag. A resource is a counter. A building is an unlock.**
There is nothing else to learn, and no new code is needed to add any of them.

Everything is saved to `user://story_state.json` between runs.

---

## Three files, three jobs

| File | Answers |
|---|---|
| `Stats.csv` | **What do we count?** |
| `Progression.csv` | **When does something happen?** |
| `Dialogue.csv` | **What is said, and what do choices change?** |

---

## Stats.csv — what the game counts

The match reports plain events as they happen. Every row here says "when this
event happens, add to this counter".

| Column | |
|---|---|
| **Counter** | which counter to add to |
| **Event** | `goal_scored` `goal_conceded` `duel_won` `duel_lost` `brew_drunk` `match_started` `match_ended` |
| **When** | optional filter. Blank = every time |
| **Amount** | blank = 1 |
| **Notes** | yours, ignored by the game |

### `{facts}` is the whole trick

Write this one row:

```
goals_with_brew_{brew},goal_scored,,,
```

…and a goal by a Fire-brewed player adds to `goals_with_brew_fire`, while a
Water-brewed one adds to `goals_with_brew_water`. **One row, a counter per
brew, forever, no code.** A goal by someone who drank nothing has no `brew`
fact, so the row is simply skipped — you never get a counter called
`goals_with_brew_`.

### The facts each event carries

| Event | Facts you can use |
|---|---|
| `goal_scored` / `goal_conceded` | `class` `tier` `card` `brew` `star` |
| `duel_won` / `duel_lost` | `class` `tier` `card` `brew` `star` |
| `brew_drunk` | `class` `tier` `card` `brew` |
| `match_ended` | `class` `result` `scored` `conceded` `margin` |
| `match_started` | `class` |

### The `When` filter

Semicolons between terms, all must pass.

```
result=win          the fact equals this
result!=draw        it does not
brew!=              the fact exists and is not blank
brew=               it is missing or blank
margin>=3           numbers: >=  <=  >  <  =  !=
```

---

## Progression.csv — when things happen

This is your control panel.

| Column | |
|---|---|
| **ID** | a unique name. Also how "only once" is remembered, so don't rename after shipping a save |
| **When** | `game_start` `menu_opened` `match_started` `match_ended` `story_ended` |
| **Requires** | the condition, blank = always |
| **Do** | what happens, semicolons between several |
| **Once** | `true` = fire once ever |
| **Notes** | yours |

### Conditions

```
count:matches_played>=3     a number
flag:first_win              a flag is set
!flag:first_win             it is not
unlocked:Brewery            you have it
count:gold>=10 and flag:brave      several, all must pass
```

### What a row can Do

Everything `Dialogue.csv` Effects can do:

```
flag:brave           count:coins+10        unlock:Brewery
set:next_class=Lorelei                     clear:next_class
```

Plus three that need the game itself:

```
story:prologue       play that dialogue scene
goto:base            change screen (menu, classes, builder, match, story)
announce:Text        put a line on screen
```

### Your example, as an actual shipped row

> *"a new brew machine might need a requirement fulfilled first, such as
> scoring 3 times with players who had had the fire brew"*

```
ID        unlock_brewery
When      match_ended
Requires  count:goals_with_brew_fire>=3
Do        unlock:Brewery;announce:The Brewery is open
Once      true
```

That row is in `Progression.csv` right now, and it works. I ran a simulated
six-match campaign through it: the Brewery unlocked on exactly the third
fire-brewed goal, not before.

Unlocks can chain — the Pub row requires `unlocked:Brewery and
count:matches_played>=5`, so one unlock gates another with no code.

---

## The safety net

Every launch prints one report to the Output panel. It gathers what each file
found wrong, and then does the checks **no single file can do alone**:

```
[content] 24 cards, 8 abilities, 10 story lines across 1 scene(s), 18 stat rules, 6 progression rows.
[content] 3 thing(s) worth a look:
          - counter 'goles' is tested by a condition but nothing ever adds to it — check the spelling against Stats.csv
          - progression: plays story 'chapter9', but no CSV defines a Scene by that name. Scenes found: prologue
          - 'Distillery' is required somewhere but nothing ever unlocks it — that content cannot be reached yet
[content] None of the above stops the game — it just means that content will not appear.
```

Those three are the mistakes that **cost you an afternoon** if nothing tells
you. A misspelled counter does not crash and does not warn — the condition is
just false forever and your content silently never appears. Now it is named out
loud, with the file and row.

I tested this with four deliberately broken rows; all four were caught.

---

## What to do next

Try this, and you will have used every part of the system:

1. Open `Progression.csv`
2. Add: `my_test,match_ended,count:goals>=1,announce:I did this myself,true,`
3. Play a match and score
4. See your line appear

Then change `count:goals>=1` to `count:goals>=99` and watch it stop firing.
That is the entire loop you will use to build the rest of the game.

---

## Where this is going

| Step | | |
|---|---|---|
| **1** | **The spine** | **done — this delivery** |
| 2 | Base building | `Buildings.csv` + the base screen. A building is an unlock with art and a Requires — the spine already carries it |
| 3 | Talent tree | `Talents.csv`, itself unlocked by a building, same grammar |
| 4 | Pub and brews | `Brews.csv`. A brew changes a card's class for one match; `active_brew` already exists on every unit and is already reported with every goal and duel |

Step 4's plumbing is already in: `player_unit.gd` has `active_brew`, and the
match reports it with every goal and duel. The moment `Brews.csv` exists and
the Pub sets that field, `goals_with_brew_fire` starts filling by itself.

---

## Files in this step

| File | Where | |
|---|---|---|
| `stats_rules.gd` | `src/core/` | reads Stats.csv, turns events into counters |
| `progression.gd` | `src/core/` | reads Progression.csv, decides when things fire |
| `content_report.gd` | `src/core/` | the safety net |
| `Stats.csv` | `data/` | 18 example rows |
| `Progression.csv` | `data/` | 6 example rows including yours |
| `game_state.gd` | `src/core/` | unchanged — it already did this job |
| `main_scene.gd`, `main_menu.gd`, `player_unit.gd`, `scene_paths.gd` | | wired up to report events |
