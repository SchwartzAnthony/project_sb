# FRIENDLIES, THE BUILD-UP, AND SEVEN FIXES

All seven things from your list are done. This file is the drop-in list, then
what each one actually does, then the two things I found while testing that
you should know about.

---

## 1. WHERE THE FILES GO

**NEW — `res://src/core/`**

| File | |
|---|---|
| `team_level.gd` | what a side is worth |
| `scratch_team.gd` | builds the friendly opponent |
| `combo_db.gd` | reads `Combos.csv` |

**NEW — `res://src/adventure/`**

| File | |
|---|---|
| `enemy_pick_layer.gd` | the enemies-as-buttons layer and its hover window |
| `adventure_buildup.gd` | the two build-up windows |

**NEW — `res://data/`**

`Combos.csv`, `ScratchNames.csv`

**REPLACES**

`res://src/core/` — `card_database.gd`, `player_data.gd`, `match_mode.gd`,
`adventure_db.gd`, `game_settings.gd`
`res://src/ui/` — `base_screen.gd`, `class_select.gd`, `season_screen.gd`,
`bounty_board.gd`, `settings_screen.gd`
`res://src/adventure/` — `adventure_encounter.gd`, `adventure_walker.gd`
`res://src/formations/` — `main_scene.gd`
`res://data/` — `Tuning.csv`, `MatchModes.csv`, `ClassInfo.csv`,
`AdventureEnemies.csv`, and **all four unit CSVs** (they have a new `Level`
column — see §3)

---

## 2. PLAY A MATCH IS A FRIENDLY NOW

The base's **Play a match** no longer opens a league fixture. It plays the
`friendly` row of `MatchModes.csv`, and that row's **Opponent** column says
`scratch` — which means the opposition does not exist until you press the
button. The league moved to the season screen's own Play button, which is
where it belonged.

**How the opponent is built**, in order:

1. Your side's level is worked out — `team_level.gd`
2. A band is taken around it — `friendly_level_spread` in `Tuning.csv`
3. Every card in the game whose own Level is inside that band is a candidate
4. Each tier is filled with **one card per rung** — `tier_ladder.gd`
5. It gets a name from `ScratchNames.csv`

Step 4 is the one that matters. **A scratch side obeys the tier ladder
exactly like yours does.** Levelling the opposition changes *which* cards
turn up, never how big their numbers are. A high-level friendly is harder
because the cards are cleverer, not because they are bigger.

It **mixes classes on purpose** — it is a pick-up team, so Tier II can be
Lorelei and Tier III Brandteufel. Its three Stars still come from one class,
because a Star bundle holds a whole tier between them. Set
`friendly_single_class` to `true` if you would rather they were proper clubs.

**What you get for playing one** is the two new columns of `MatchModes.csv`:

```
Rewards          applied whatever the score
Rewards On Win   applied as well, only if you won
```

Both written in the language you already use for a dialogue Effects column —
`count:scrap+3`, `unlock:The Cup`, `set:last_friendly=won`, joined with `;`.
So what a friendly pays is a spreadsheet edit. The `friendly` row ships
paying 2 scrap to play and 3 more plus a `friendly_wins` tick for winning.

### Testing it

I built **2000 scratch sides** against the real CSVs:

- **0** came out with an empty rung (which would have been a free tier for you)
- **0** had to widen their level band to find enough cards
- they averaged **3 to 4 different classes per side**

---

## 3. THE LEVEL COLUMN — READ THIS BIT

You asked to dictate level in the units CSV. There is now a **`Level`**
column in all four unit CSVs, sitting right after `Tier`. It is **not** the
`Stufe` column, which is card text.

**Why it has to exist, and it is not a small point.** I tried working level
out from tier and power instead, so you would not have to fill anything in.
It cannot work, and the reason is the tier ladder: *every legal team has the
same powers*. One 0, one 1, one 2 in Tier I, and so on up. So every legal
side came out at exactly level 29 and every friendly was identical.

That is the ladder doing its job. Power is spoken for — it cannot also mean
"this is a late-game card". **Level is the column that can say that.** It is
the one number in the game that is free to describe progression.

Leave it blank and a card's level is guessed from its tier and power, which
keeps everything running but makes every side match every other. The Output
panel says so once when that happens:

```
[friendly] No card anywhere has a Level yet, so every side matches every other.
           Fill the Level column in your unit CSVs and friendlies start scaling.
```

I have filled it in with starting values so you can see the system alive:
Lorelei sit four levels above Brandteufel, the enemy set two above. **Those
are placeholders for you to overwrite** — that is the whole point of the
column.

**Two numbers, and they are not the same number.** A *team* level is a
headline in the tens (a full side is about 29). A *card* level is in the
ones. A friendly bands on card level, because it is shopping for cards.
Mixing them up asks for cards at level 29 when your collection tops out at
12. `team_level.gd` has a long note about it.

---

## 4. THE CARDS ARE CENTRED

Both in a match and in an Adventure fight, and both from `Tuning.csv`:

```
card_row_x        0.5     0 = hard left, 0.5 = middle, 1 = hard right
card_row_y        0.5     0 = the top,  0.5 = middle, 1 = the bottom
card_row_gap      18
adventure_choice_y 0.5    the Adventure card window
```

The match row used to be wherever `CardContainer` happened to be anchored in
your `main_scene.tscn` — along the bottom edge. It is positioned from code
now, as a fraction of the window, so it lands in the same place at any
resolution and there is nothing to drag in the editor.

---

## 5. ADVENTURE PLAYERS ARE ACTUALLY BIGGER NOW

You were right that something was fighting the CSV. Here is what it was.

The art was being fitted into a **square** box of `RADIUS × 2.4`. A player
frame is tall and narrow — about 128 wide by 208 high — so fitting it into a
square meant the height filled the box and the width shrank to about 60% of
it. Raising `adventure_player_size` made the *square* bigger and the player
still came out a sliver. The spreadsheet was being read correctly; the box
was wrong.

The box is worked out from the frame's own shape now. You say how **tall** a
player should be and the width follows from the artwork:

```
adventure_player_size       34    the radius everything else scales off
adventure_player_art_scale  3.4   how tall, as a multiple of that
```

That is about 115 pixels tall out of the box. Players also stand *on* their
position now rather than being centred over it, so a group reads as a crowd
on the grass instead of floating heads.

---

## 6. ADVENTURE USES THE TEAM SHELF

The Bounty Board goes to **CHOOSE YOUR TEAM**, the same screen a league match
uses. Pick a side you own, edit it, or build a new one. Nothing in the bounty
board names a screen — the `adventure` row of `MatchModes.csv` has a `Scene`
of `adventure`, and the shelf reads that column, so LOCK IN goes to the
scroll instead of the pitch.

### Classes can be locked or removed

Two new optional columns in `ClassInfo.csv`:

```
Requires   unlocked:Rival Scouting    the usual condition language
Hidden     yes                        never offered, whatever else the row says
```

A class with neither is always available, so you can ignore both. A locked or
hidden class is **still perfectly real everywhere else** — its cards load, the
opposition can field it, a saved team of that class still plays. This is only
about what you may *start a new team* from. `Hidden` is how you take a class
out without deleting its rows.

There is an example locked class (`Rivals`) in the shipped file.

---

## 7. THE ADVENTURE FIGHT, REBUILT

Three things changed and they are best read together.

### The enemies are the buttons

There is no list of enemies in a panel any more. Each living enemy gets a
**real, invisible Button** sitting on top of it and following it — so Godot
does the hovering, the clicking and the keyboard focus, rather than the old
code guessing from mouse distance. Hovering one opens a window beside it with
its picture, what it hits for, its armour layer by layer, its element, its
ability in that ability's own words, and your description.

Picking is only live while the fight is *waiting* for a target, so a stray
click during the animation cannot re-aim a shot that is already going in.

### The cards have their own window

Centred, up only while a tier is being drafted, gone the moment the fourth
card is in — which is what leaves the middle of the screen clear for what
happens next. The big 300-pixel combat panel is now a slim strip at the
bottom holding the prompt and the three buttons.

### The build-up

When your four tiers are in, you watch the move:

- **LEFT** — your players arrive one at a time, weakest tier first, each
  adding its power to a running total. Any **combo** it completes flashes up
  the moment it completes.
- **RIGHT** — the enemies, gaining whatever their new **Buff** column says
  with every pass. The longer your move, the harder the reply.

Then both windows go, and that last player is left standing on the pitch to
take the shot at the enemy you chose. If it kills, the enemy goes down.

```
adventure_buildup        true    false skips it entirely
adventure_buildup_step   0.55    seconds per player
adventure_buildup_hold   0.9     seconds the finished move is held
adventure_death_seconds  0.55
adventure_death_animation lose   which Animations.csv row a dying enemy plays
```

It decides nothing — everything is worked out before it runs — so turning it
off changes only what you watch.

### Combos — `res://data/Combos.csv`

What the *move* was worth, on top of the four powers. Six shapes:

| When | fires on |
|---|---|
| `same_element` | `Needs` players sharing one element |
| `same_class` | `Needs` players of one class |
| `all_different_class` | nobody shares a club |
| `rising_power` | every player stronger than the one before |
| `all_four` | all four tiers had somebody |
| `star_last` | a Star Player takes the shot |

A combo adds to the **shot**, never to a card — the same rule the season's
Difficulty obeys, and for the same reason.

**I retuned this table twice against your real CSVs.** My first version was
badly wrong: four combos fired 100% of the time and they added **79%** to
every shot. Two causes — every one of your classes is a single element, and
your own team is always one class, so "same element" and "same class" were
free. I found it by simulating 5000 moves.

The shipped table now reads:

| your side | on top of the shot |
|---|---|
| Brandteufel (all one element) | **+25%** |
| Lorelei (two elements) | **+23%** |
| Normal (no element) | **+16%** |
| a scratch opponent (mixed) | **+13%** |

Which is a real difference between classes rather than a free bonus. One
detail worth knowing: an Element column reading **`None`** now counts as *no
element*, not as an element everybody shares. Without that, the `Normal`
class got the element combo on every move it ever made.

### Enemy buffs — the new `Buff` column

In `AdventureEnemies.csv`, right after `Ability`. How much an enemy gains
**per pass** while you build your move, for that round only. Blank or 0 means
it does not build up, which is what most of them should be — give it to the
ones that should feel like a clock ticking. The bosses ship with 1.

---

## 8. THE SETTINGS COLOUR BUG

Both halves fixed.

**The window resized** because changing *any* setting re-applied *all* of
them, and re-applying the screen settings resizes and repositions the window.
Now only the part that changed is applied: a colour repaints, a volume
touches the audio buses, and neither goes near the window.

**It jumped back to the first tab** because a palette change reloaded the
whole scene. It repaints in place now, and which tab you are on is remembered
anyway, so you stay where you were.

---

## 9. TWO THINGS I FOUND THAT YOU SHOULD KNOW

**The level guess cannot work, and that is the ladder's fault in a good way.**
Covered in §3. The short version: fill the `Level` column in, or every
friendly is the same. There is no way around this that does not involve
breaking the ladder, and the ladder is worth more than the convenience.

**Your classes are mono-element.** Brandteufel is twelve `Wand`, Normal and
Rivals are twelve `None`, only Lorelei is split (six Water, six Fire). That
is fine, but it means element-based combos either always fire or never do,
with nothing in between. If you want element combos to be a *choice* rather
than a class trait, give each class two or three elements the way Lorelei
already has. I have tuned the current table around what you actually have, so
nothing is broken either way — it is a design question, not a bug.

---

## 10. FIRST RUN CHECKLIST

1. Copy the files in. **The unit CSVs are replaced** — they have the new
   `Level` column. If you have edited yours since the last drop, add a
   `Level` column after `Tier` to your own copies instead.
2. Press F5. The Output panel should print:
   - `[combos] 5 combo(s) loaded.`
   - `[adventure] Lane ... player radius 34 ...`
   - `[cards] Card row centred at 0.50, 0.50 of the window.`
3. Base → **Play a match** → pick a team → LOCK IN. The Output panel says
   your level, the opponent's level, and the whole opposing line-up.
4. Base → **Adventure** → a bounty → you land on CHOOSE YOUR TEAM.
5. In an Adventure fight: hover an enemy on the pitch — a window opens beside
   it. Click it. Draft four tiers in the centred window. Watch the two
   build-up windows, then the kick.
6. Settings → Colour → pick a palette. The window should not move and you
   should still be on the Colour tab.
