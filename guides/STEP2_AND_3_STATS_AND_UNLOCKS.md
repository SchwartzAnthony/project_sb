# Steps 2 and 3 — the post-match screen, and "why is this locked?"

Both were on the list. They share one engine, so doing them together was less
work than doing them apart. **Everything you asked for is now done** — the
list at the bottom says what is left.

---

## STEP 1 — Where every file goes

| File | Folder |
|---|---|
| `unlock_progress.gd` | `src/core/` |
| `progress_row.gd` | `src/ui/` |
| `match_stats_screen.gd` | `src/ui/` |
| `match_stats_screen.tscn` | `src/ui/` |
| `unlock_board.gd` | `src/ui/` |
| `unlock_board.tscn` | `src/ui/` |
| `new_unlocks_panel.gd` | `src/ui/` |
| `stats_rules.gd` | `src/core/` *(replace)* |
| `match_report.gd` | `src/core/` *(replace)* |
| `season_db.gd` | `src/core/` *(replace)* |
| `content_report.gd` | `src/core/` *(replace)* |
| `scene_paths.gd` | `src/core/` *(replace)* |
| `base_screen.gd` | `src/ui/` *(replace)* |
| `main_scene.gd` | `src/formations/` *(replace)* |
| `Stats.csv` | `data/` *(replace)* |
| `Tuning.csv` | `data/` *(replace)* |

**No new CSV file**, so there is no import step. `Stats.csv` already exists in
your project and keeps whatever import setting it has.

Press F5. The new flow is:

```
match  ->  90:00  ->  STATS SCREEN  ->  Continue  ->  SEASON TABLE  ->  base
                          |                                            |
                     Play it again                            "NEW AT THE BASE"
                     Back to the base                         flashes, Continue
```

Two new buttons at the top-right of the base: **Unlocks** and **The season**.

---

# THE POST-MATCH SCREEN

Left panel: every number that moved during the match, in groups.
Right panel: bars for what you are close to, filling up and shining when done.

## Adding a stat is a row in Stats.csv. That is the whole job.

`Stats.csv` has two new columns:

| Column | What it does |
|---|---|
| **Group** | which panel it appears in — `Goals`, `Duels`, `Keeper`, `Match`, `Brews`, or any new word you invent |
| **Label** | what the screen calls it. Blank = the counter name tidied up |

The panels appear in the order the Groups first appear in the file, so you
control the layout of the screen from the spreadsheet.

## Three new events you can count

| Event | Facts it carries |
|---|---|
| `shot_taken` | class, tier, card, brew, star, **power**, result |
| `save_made` | class, **card** (the keeper), **power**, **stamina** |
| `stamina` on a save | how much that save actually cost |

**Only your side is ever counted.** An enemy shot does not land in `shots`,
and their keeper's save does not land in `saves`. Everything the game unlocks
is about what you did.

## Amount can now be a {fact}

This is the row that answers your "used 600 stamina" example:

```
keeper_stamina_spent,save_made,,{stamina},Keeper,Keeper stamina spent,
```

`{stamina}` in the **Amount** column means "add however much that save
actually cost", not 1. Any fact the event carries works there.

And this is your "fire keeper has blocked 40 times":

```
saves_by_{card},save_made,,,Keeper,,
```

One row, one counter per keeper. Then anywhere in any CSV:

```
Requires   count:saves_by_Fire Keeper>=40
```

I have already added rows for who scored (`goals_by_{card}`), who wins their
fights (`duels_won_by_{card}`), saves per keeper, keeper stamina, big saves,
shots, shots by tier and clean sheets.

## Where "this match" comes from

The match photographs your save at kick-off and again at the whistle. The
difference **is** this match: `duels_won` went 40 to 47, so you won seven
today.

That is why adding a stat needs no code. There is no list in the screen to
add it to, and nothing in that file knows what a duel is.

---

# THE BARS

`progress_row.gd` draws them and is the one place to restyle them. A finished
bar pulses gently, because a full bar and a nearly-full bar look identical
when they are both sitting still.

Order on the post-match screen: anything you finished **this match** first
(shining), then whatever you are closest to. `progress_bars_max` in
`Tuning.csv` sets how many. Anything at zero is left off — a bar that has
never moved says nothing and would push out the ones that have.

---

# THE UNLOCK BOARD — "why is this locked?"

**Base → Unlocks.** Every earnable thing in the game on one page: buildings,
talents, brews, fixtures, unlocks and achievements. Filter by kind, or hide
what you already have.

## What it actually does for you

Ask it why the Pub has not appeared, and it says:

> **Pub** — Pub, which needs Brewery, which needs goals with brew fire: 0 of 3
> *(and more)*    `[Buildings.csv]`

That is the answer, in one line, without opening a single spreadsheet.

Getting there took a real fix. The Pub building's `Requires` is
`unlocked:Pub` — true, and useless. The actual work lives one row further
along, on the Progression row that grants `unlock:Pub`. **So the board
follows the chain**: an unmet `unlocked:X` is replaced by whatever X is
itself waiting for, and the bar inherits X's progress instead of sitting at
zero. It follows two links and then stops, because
"A, which needs B, which needs C" is a sentence and a third one is not.

It also translates. A talent is required by its spreadsheet ID, so the raw
condition says `unlocked:swarm`; the board says **Swarm**.

Every row shows which CSV it comes from, in brackets. When something looks
wrong, that is the file to open.

## It is a content check as well as a player screen

If something sits at 0% saying "needs X" and nothing in the game grants X,
you have found unreachable content. The startup report already warns about
that; this shows you where it sits in the web.

## The one rule that makes it trustworthy

Whether something is **done** is decided by the same call the game itself
makes. The board cannot say "yours" about something that never appears — the
answer is not computed twice. The bar's *fraction* is worked out separately
and is decoration.

Two rules follow from that, both learned by getting them wrong first:

- Something you have not got, with no visible requirement, is at **zero**,
  not full. (An empty condition passes every test — that is how the Cup came
  to be "yours" before a ball was kicked.)
- An unfinished bar **never reaches the end**. A full bar next to "not yet"
  is the screen contradicting itself, and the player believes the bar.

---

# THE FLASH AT THE BASE

Walk into the base having unlocked something and it flashes up on top with a
**Continue** button, then never flashes again. Clicking anywhere also
dismisses it.

"Seen" is remembered as an ordinary flag, `seen_unlock_<name>`, so a CSV can
test it too:

```
Requires   unlocked:Brewery and !flag:seen_unlock_Brewery
```

...is a perfectly good condition for a visitor who wants a word with you the
first time you notice the Brewery.

---

# PLAY IT AGAIN — and an honest note

The stats screen's middle button says **"Play it again (does not count)"**.

It plays the same opposition again from scratch. The season table is not
touched, because that fixture is already recorded.

**It is not a rewatch.** You asked to rewatch the match, and I want to be
straight about why this is not that: nothing about the match is recorded
anywhere, so there is nothing to play back. A true replay means storing the
random seed and every decision made during the match and replaying them
deterministically. That is a real feature and a decent chunk of work — say
the word and I will do it, but I would rather tell you it does not exist than
label a rerun a replay.

---

# WHAT I CHECKED

Six passes, all green, all against your real CSVs.

- **The new stats.** A save recording its keeper, its class, its power and its
  stamina; 40 blocks by one named keeper adding up to 80 stamina and being
  testable from a CSV; big saves only over 4 power; who scored; shots by tier.
- **The grouping.** Every counter found its panel, the panels come out in file
  order, labelled rows use their Label and `{fact}` rows fall back to the
  spelling.
- **The board on a fresh save.** 27 earnable things found; the only ones
  already "yours" are the three with no requirement at all (Clubhouse, the
  Gate, the Keeper's Tonic) — which is correct, not a bug.
- **The chain**, on the Pub, the Trophy Room and Master Brewer.
- **The bars over five matches**: 20, 40, 60, 80, 100% and then done; never
  over 100%; nothing finished showing less than full; and **the board never
  once disagreed with the game** about what is unlocked.
- **The flash**: appears, clears on Continue, stays cleared, reappears for
  something new, and is testable as a flag.
- Plus the earlier season, camera and controls passes, the static sweep of 53
  scripts, and the scene check on all 14 `.tscn` files.

Three real bugs were caught this way and fixed before you saw them: the Cup
counting as earned before kick-off, the Pub saying "the Pub needs the Pub",
and a duplicate bar for every building that shares its name with its unlock.

---

# WHAT IS LEFT

Everything you have asked for is now built. Two things remain from my own
earlier list, and I would not do either of them yet:

**The save-state inspector** (set any flag or counter by hand, to jump
straight to "six wins and the Brewery"). Hold `F` plus the unlock board
probably covers most of what it was for. Worth doing if you find yourself
still replaying matches to test content.

**The content map** — one generated picture of what unlocks what. The board
now answers the same question one row at a time, which is enough while the
web is this size. Ask for it when it stops fitting in your head.

**A true replay**, if you want the rewatch button to really rewatch.

Say which, or say what has come up from playing it — I would rather fix what
you actually hit than build the next thing on a list.
