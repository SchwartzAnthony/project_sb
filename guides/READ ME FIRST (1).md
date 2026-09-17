# Read me first

## Nothing to delete this time

You cleaned the duplicates up — I cloned the repo and checked. There is one
leftover you can bin whenever you like: `data/FileManifest.What it is.translation`.
Nothing reads it.

## But you only copied `src/` last time, not `data/`

That is why the last round half worked. `juice.gd` and `juice_db.gd` are in
your project, but **`data/Juice.csv` never arrived**, so the whole juice
system has been loading nothing and doing nothing. None of last round's
Tuning rows arrived either.

**This zip has both folders and everything that was missing.** Copy `data/`
as well as `src/` and `tools/`, over the top of your project.

---

# The crash

```
AdventureEncounter._note: Cannot call method 'add_child' on a null value
```

`_build_ui()` called `_build_command_bar()` and `_build_choice_window()` and
never called `_build_log_window()`. I dropped that line when I rewrote the
card window last round. So `_log` stayed null, the fight worked perfectly,
and the first thing it tried to **say** — "Focusing the Mire Grub" — killed
it. One missing line, one dead mode.

Fixed, and `_note()` now checks before it writes, so if that ever happens
again you get a line in the Output panel instead of a dead run.

---

# The window cut off at the bottom

Three windows had the same bug, and it is worth understanding because it will
come up again: **when a Godot control needs more room than its box, it grows
in whichever direction `grow` says, and the default is BOTH ways.**

* The **COMBAT bar** is pinned to the bottom. When the prompt wrapped onto a
  second line, half the extra height went *downwards*, off the screen, taking
  the buttons with it. It now grows **upwards only** — the bottom edge is
  nailed down and cannot move.
* The **card window** had the opposite problem: my fix last round anchored it
  to the whole screen so it could not be cut off, which made it fill the
  screen. It now sits on top of the COMBAT bar and grows upwards to fit its
  cards, with a ceiling; past that, the cards scroll.
* The **WHAT HAPPENED log** was running off the right-hand edge for the same
  reason. It grows **left and down** now, and its lines wrap.

Here is the result, taken from the running game:

    adventure_bar_height        104   how tall the COMBAT bar starts
    adventure_bar_inset          16   how far it sits above the bottom
    adventure_choice_top        130   the ceiling on the card window
    adventure_choice_bottom     140   where its bottom edge sits, and stays
    adventure_log_top           150   where the log hangs from

---

# Adventure combat, remade

## The idea

In a league match a player brings their **abilities**. In Adventure they
bring their **icons**. Every player you send into the move drops their icons
onto a pile, and the pile is what you are really playing. Three Fire on the
pile and every shot is worth four more. Four Wand and a Treant walks on to
replace somebody you lost.

**Abilities are not read in Adventure at all.** Not ignored — not read. The
same eleven players are a different game here, which is what stops the two
modes feeling like one game with two backdrops.

**The pile does not empty each round.** It empties at the end of the round in
which the **cycle** comes round — when every tier has fielded everybody it
has, the same rotation your Stars use in a league match. So a fight is one
long build with a reset in the middle of it, and "do I spend my last Fire now
or hold the tier open" is a real question.

## The three spreadsheets

### `data/AdventureTraits.csv` — what the icons are

| Column | |
|---|---|
| `From` | where the icon comes from: `element`, `class`, `star` or `tier` |
| `Value` | which value in that column counts. Blank for `star` |
| `Icon` | a file in `assets/icons/`. Missing = a coloured pip, which plays fine |
| `Colour` | `#rrggbb` |
| `Order` | left to right along the top |
| `Max` | how far the bar counts |

**A player carries several icons.** A Lorelei whose Element is Water stacks
*Water* and *Lorelei*, from two different rows, and both bars move.

**What they drank counts.** `From = element` reads the new `Element` column of
Brews.csv, and `From = class` reads the brewed class. So a Lorelei who drinks
a Fire Brew genuinely brings a Fire icon and a Brandteufel icon to the move —
that is the "based on what they drink" you asked for, and it is now a real
mechanical difference rather than a change of picture. I added the `Element`
column to Brews.csv and filled it in for the two brews you have.

Eight icons ship: Fire, Water, Wand, Brandteufel, Lorelei, Star, Journeyman
(your starter team — without it those players would put nothing on the pile)
and The Rivals.

### `data/AdventureCombos.csv` — what reaching one does

| Column | |
|---|---|
| `Trait` | which row of AdventureTraits.csv |
| `At` | **how many it takes**. 2 means two of that icon on the pile |
| `Effect` | `attack` `strike` `heal` `stamina` `revive` `shield` `spawn` |
| `Value` | the number. What it means is per effect |
| `Target` | who or what. Per effect |
| `Lasts` | `held` = true while you hold it. `once` = fires when you reach it |
| `Icon` | **the icon at this breakpoint**, so the picture changes as you climb |
| `Description` | the line a player reads |

**Only the highest breakpoint you have reached is active**, for `held`
effects — three Fire gives you Blaze, not Kindling *and* Blaze. That is what
makes 3/4 worth chasing. `once` effects all fire as you pass them.

What the effects do:

```
attack    Value is added to the SHOT. Never to a card — the tier ladder
          is the one rule nothing is allowed to move
strike    Value damage straight into enemies. Target = all / focus
heal      Value stamina back. Target = lowest / all / last
stamina   the same thing, under a name that reads better in some rows
revive    Value knocked-out players get up. Target = how much stamina each
shield    Value comes off every hit against you while you hold it
spawn     Value stand-ins walk on. Target = a row of AdventureSpawns.csv
```

An `Effect` the game has never heard of is reported **by name** on load, with
the list of the ones it knows, and that row is skipped. Nothing crashes.

### `data/AdventureSpawns.csv` — the Treants

A stand-in that walks on to replace somebody who is out, taking that
player's tier. **Its power is clamped into that tier's legal rungs** — the
ladder is not broken even by a spawn, and the log says so if a number had to
be moved. It is then a real member of the party: it can be drafted, hit,
knocked out, and it puts its own icons on the pile.

Three ship: Treant, Reed Wisp, Ember.

## What it looks like

Every icon is on the bar across the top, always — greyed at `0/2` with what
it would take written underneath, because knowing what you are *not*
building is half of knowing what to send next. As you climb, the tile lights
in its own colour, the count becomes `2/3`, and the picture changes to that
breakpoint's own `Icon`.

Hovering a card no longer reads out abilities. It reads out what that player
would do **to the pile**: `Fire 2 → 3  ⟶  Blaze: +4 on every shot`. That is
the actual decision, so it is the thing the card says.

## The enemies use the same table

Their Element and their Pool are the icons they carry, out of the same two
spreadsheets. One table governs the whole of Adventure. **Only `attack`
applies to them** — they do not revive, spawn or heal, because that would
make a wave unkillable rather than dangerous. `adventure_enemy_combos = false`
turns it off.

---

# I ran the game this time

I have Godot 4.7 running here now, so this is not a lint any more.

1. **Imported the project and parse-checked all 96 scripts** under real Godot
   4.7. Zero errors.
2. **A soak test**: 100 complete Adventure fights, drafting a card for every
   tier of every round — half of them deliberately unfair so the revive, the
   stand-in and the everybody-is-down paths all get run. 67 cleared, 33 lost,
   **no errors and no broken tier ladders.** It is in the zip as
   `tools/adventure_soak.gd`, and you can run it yourself:

   ```
   godot --headless --script res://tools/adventure_soak.gd
   ```

3. **Screenshots of the real game**, which is the only way a cut-off window
   can actually be checked. `tools/adventure_shot.gd` opens the Adventure
   scene, hurries the first wave along, drafts through the tiers and saves
   the screen at each step. That is how I found the card window filling the
   screen and the log running off the right-hand edge — neither of which a
   parse check can see.

Both tools are in `tools/` with the rest of your workbench. Nothing in the
game loads them.

---

# New Tuning.csv rows

```
adventure_bar_height          104   the COMBAT bar's starting height
adventure_bar_inset            16   how far it sits above the bottom
adventure_choice_top          130   ceiling on the card window
adventure_choice_bottom       140   its bottom edge, which never moves
adventure_log_top             150   where the log hangs from
adventure_trait_bar          true   the row of icons across the top
adventure_trait_bar_top        22   how far down it starts
adventure_trait_bar_left      260   clear of the biome name
adventure_trait_bar_right     240   clear of the `carrying` line
adventure_trait_tile_width    158   eight fit on one line at this width
adventure_revive_stamina        3   what a revive gets you up with
```

plus everything from last round that never arrived: `adventure_enemy_buildup`,
`adventure_enemy_combos`, `adventure_turn_over_seconds`, `adventure_stretcher`,
`adventure_stretcher_seconds`, `juice_scale`, `juice_slowmo`,
`juice_average_hit`.

`adventure_choice_y` is gone. The card window's bottom edge no longer moves,
so there is nothing left to nudge.

---

# Two things worth your attention

**The old Combos.csv is now season-only.** Adventure does not read it any
more. It is untouched and the league still uses it — but if you were writing
combos expecting them to apply everywhere, they no longer do. That is the
split you asked for.

**Your starter team had no icons.** BasicTeam.csv is `Unit Type = Normal`,
`Element = None`, so before I added the Journeyman row those twelve players
put nothing on the pile at all and the bar never moved. Worth remembering as
you add cards: **a player whose element and class match no row in
AdventureTraits.csv contributes nothing.** That is a legal thing to want, but
it should be on purpose.
