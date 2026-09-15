# Writing story in a spreadsheet

Open a CSV. Type a line of dialogue. Press F5. It is in the game.

There is no editor work, no import step, no scene to wire up. This is the same
deal as the card CSVs: **the spreadsheet is the story.**

---

## The five-minute version

`res://data/Dialogue.csv` already has a working scene in it. To see it, press
**F5** and click **Story** on the main menu.

To write your own, the only two columns that must be filled in are **Node ID**
and **Text**:

| Scene | Node ID | Speaker | Text |
|---|---|---|---|
| prologue | open | | Floodlights. Ninety thousand voices. |
| prologue | meet | Heatwave | So you're the new one. |
| prologue | end | | You walk into the tunnel. |

Three rows, no Next column, and it plays top to bottom and ends. That is a
complete scene.

---

## How a file is recognised

Any CSV in `res://data/` whose header row has **both** a `Node ID` column and a
`Text` column is treated as dialogue. The file name does not matter — call it
`Dialogue.csv`, `Chapter3.csv` or `lorelei_intro.csv`.

Column order does not matter either, and neither does case, spaces or
underscores: `Node ID`, `node_id` and `NODEID` are the same column. Columns you
do not use can be left out of the file entirely.

---

## Every column

| Column | What it does |
|---|---|
| **Scene** | Groups rows into one story. Blank means `main`. One file can hold many scenes; one scene can span many files. |
| **Node ID** | The row's name. `Next` and choices point at this. Unique within its Scene. |
| **Speaker** | Name on the plate. Blank = narration, and the plate disappears. |
| **Portrait** | PNG name, looked for in `assets/portraits/`. The `.png` is optional. |
| **Side** | `left`, `right` or `centre`. Where the portrait stands. |
| **Animation** | A row in `Animations.csv`. Turns the portrait into a playing spritesheet. |
| **Background** | PNG name, looked for in `assets/backgrounds/`. **Blank keeps the one already up**, so you only set it when it changes. |
| **Music** | OGG/WAV/MP3 name in `assets/music/`. Re-naming the same track does not restart it. |
| **Text** | The line. |
| **Next** | Node ID to continue to. **Blank falls through to the next row in the file**, which is why simple scenes need no Next at all. Write `other_scene/node_id` to jump between scenes. |
| **Requires** | When this row may be used. See below. |
| **Effects** | What showing this row changes. See below. |
| **Choice 1 Text** | A button under the text. Up to 4. |
| **Choice 1 Next** | Where that button goes. Blank ends the scene. |
| **Choice 1 Requires** | When that button appears at all. |
| **Choice 1 Effects** | What clicking it changes. |

…and the same four for **Choice 2**, **Choice 3** and **Choice 4**.

---

## Requires and Effects

This is the whole language. Both columns take a list separated by semicolons
(or the word `and`, if that reads better in a cell). Every term in a Requires
must pass.

### Requires — when something appears

| Write | True when |
|---|---|
| `flag:brave` | the flag is set |
| `!flag:brave` | the flag is **not** set |
| `unlocked:Lorelei` | you have unlocked it |
| `!unlocked:Lorelei` | you have not |
| `count:gold>=10` | a number comparison. `>=` `>` `<=` `<` `=` `!=` all work |
| `count:gold` | shorthand for "more than zero" |
| `is:next_class=Lorelei` | a stored word matches |

A choice whose Requires fails is **not greyed out — it is not there.** The
player never sees a door they cannot open.

### Effects — what something changes

| Write | Does |
|---|---|
| `flag:brave` | set a flag |
| `flag:brave=false` | clear it |
| `count:gold+10` | add |
| `count:gold-5` | subtract |
| `count:gold=0` | set outright |
| `unlock:Lorelei` | unlock a class, a card, anything by name |
| `set:next_class=Lorelei` | remember a word |
| `clear:next_class` | forget it |

Effects on a **row** fire when the line is shown. Effects on a **choice** fire
when it is clicked, before the jump.

---

## The bit that matters for later

`count:` and `set:` are deliberately generic, and they are how everything you
have not built yet will work without me touching this code again:

```
Base building     count:wood+10        count:barracks_level+1
Achievements      flag:beat_the_keeper flag:undefeated_season
A shop            count:gold-25
Chapters          count:chapter=2
Reputation        count:respect+2      then  Requires: count:respect>=5
```

None of that needs new columns or new code. Write it in the spreadsheet and it
works, and it is all saved between runs.

It lives in `user://story_state.json` — beside the game's other save data, not
in your project folder. Four kinds of memory: **flags** (on/off), **counters**
(numbers), **texts** (words) and **unlocks** (a list of names).

---

## Making a choice change the match

One hook is wired up already, as the worked example:

```
Choice 1 Effects:  set:next_class=Lorelei
```

The class select screen opens on the Lorelei, and prints why in the Output
panel. The name is consumed, so the match after that starts free again.

Everything else follows the same two-step pattern:

1. Write to state from a CSV — `count:keeper_stamina_bonus+3`
2. Read it where the thing is decided — `GameState.fetch(get_tree()).count("keeper_stamina_bonus")`

The reading half is one line wherever it belongs. `class_select.gd`'s
`_opening_class()` is the model to copy.

---

## Two rows, one Node ID

This is legal, and it is how you write "if they were kind, say this, otherwise
say that":

| Node ID | Requires | Text |
|---|---|---|
| chose | `count:respect>=2` | Walk out beside me, then. |
| chose | `count:respect<2` | Then go. I'll decide about you later. |

The first one whose Requires passes is the one that plays. Two rows sharing an
ID where **neither** has a Requires is flagged as a problem, because the second
could never be reached.

---

## Art

All optional. Everything works with no art at all — you get a plain dark panel
and readable text.

```
res://assets/backgrounds/    the Background column
res://assets/portraits/      the Portrait column
res://assets/music/          the Music column
```

Portraits can be plain pictures **or** spritesheets. Fill in the `Animation`
column with the name of a row in `Animations.csv` and the portrait plays that
animation on a loop — the same system the units on the pitch use, so a talking
sprite you have already drawn works here for free.

---

## Starting a scene

From the main menu, `MenuConfig.csv` does it with no code:

```
STORY,Story,640,448,260,68,story:prologue,,Plays the scene called prologue
```

The word after the colon is the Scene name, so `story:chapter2` and
`story:lorelei_intro` are two more buttons and still no new code.

From a script:

```gdscript
DialogueView.play(get_tree(), "prologue")
DialogueView.play(get_tree(), "chapter2", ScenePaths.MATCH)   # then go to a match
```

---

## When something is wrong

The Output panel gets one report at startup, and it names the file and row:

```
[Story] 10 line(s) across 1 scene(s): prologue
[Story] 2 thing(s) need attention in your dialogue CSVs:
        - Dialogue.csv row 7 ('meet'): choice 2 goes to 'freindly', which does not exist
        - Dialogue.csv row 9 ('pick_side'): Requires 'count:gold' — expected a comparison
```

Checked for you at load: destinations that point nowhere, choices with a
destination but no text, rows with neither text nor choices, misspelled
condition words, and comparisons written the wrong way round. **The story still
runs** — the report tells you what to fix rather than stopping the game.

At the end of a scene, everything your choices changed is printed too:

```
[Story] 'prologue' finished. Changes this session:
        - flag polite = true
        - respect +2 -> 2
        - unlocked Lorelei
        - nextclass = "Lorelei"
```

---

## Controls

| | |
|---|---|
| Click / Space / Enter | advance, or finish the typing early |
| Escape | leave the scene |

Choices only appear once the line has finished typing, so you cannot answer a
question you have not read.
