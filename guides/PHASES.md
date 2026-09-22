# The plan — twenty-three things, six phases

You asked for a lot in one message and said to split it if it was too much.
It was. This is the split, in the order I would do it and with the reason for
that order. **Phase 1 is in the zip.** The rest is a promise you can hold me
to, and you can reorder it at any point — the phases are mostly independent.

The order is not by size. It is:

1. **things that are broken** — you cannot judge the game through them
2. **things you cannot read** — you cannot judge a match you cannot follow
3. **things that block your own work** — art, sizes, structure
4. **new systems** — biggest, and they want the foundations above first

---

## Phase 1 — Sound, and the way in and out  ✅ DONE (round K)

Everything here was broken rather than missing. Broken things come first
because every other judgement you make about the game is made through them.

| | |
|---|---|
| ✅ | Main menu music never started until you went to the tutorial and back |
| ✅ | The base theme played over every screen for the rest of the session |
| ✅ | The pitch had no music at all |
| ✅ | The win sound played on half of your losses |
| ✅ | The kick-off whistle blew over the loading screen |
| ✅ | Escape at the base could not get you back to the main menu |
| ✅ | Escape twice quit the game instead of closing the menu |
| ✅ | Delete Profile was a main button; it is behind a cog and a Yes/No now |
| ✅ | Item icons were too small to read |
| ✅ | **The size to draw the pitch and the stadium at** |
| ✅ | The enemy's revealed card stayed on screen all match; it has an OK now |
| ✅ | A long announcement ran off the right-hand edge of the screen |
| ✅ | Your four new CSVs were being turned into 32 junk translation files |

Plus the structure under your new spreadsheets — see *Phase 5* — read,
checked and written down, because you asked me to understand it now.

---

## Phase 2 — Reading the match  ✅ DONE (round L)

You cannot tell whether the football is good if you cannot follow it. All of
this is about the same thing: making the state of play obvious.

| | |
|---|---|
| ✅ | **ATTACKING or DEFENDING, big.** The word lands across the pitch on the clash result, and then a strip stays pinned above the card row for every tier pick — with the tier, and with the reason it matters in small letters underneath |
| ✅ | **The line-ups walk out.** Between the team sheet and the countdown: your side a player at a time, then theirs. Click, space or escape skips the lot |
| ✅ | **The goal celebration.** `data/Celebration.csv` — one row per beat, seven things it can do, your order and your seconds. The scorer slides, the team rings him, confetti, a window with his own animation or your own picture in it |
| ✅ | **A Star's abilities once, not twice.** The hover is gone. The printed pair is tagged **ATK** and **DEF** in the same two colours as the strip above the cards, so the draft teaches the team sheet |

**What made it worth doing in this order:** it is all presentation of things
that already work, so it is low risk — and the two colours turned out to be
one idea rather than two, which is why the banner and the team sheet ended up
sharing a palette entry.

**One thing that was not on the list and is in the zip anyway.** The confetti,
written the obvious way, took the game from 22 frames a second to 2 — at the
exact moment it is supposed to feel best. It is one draw call now. The
measurement is in `src/ui/goal_celebration.gd`, in the comment above
`_draw_paper()`, because it is the kind of thing that is invisible until
somebody measures it.

---

## Phase 3 — The skin  ✅ IN THIS ZIP

> *"Right now people can tell it is an AI game. I need to be able to
> customise the windows."*

| | |
|---|---|
| ✅ | Panels, buttons and windows drawn from **images** — 9-slice, so one 48×48 PNG stretches to any window without distorting its corners |
| ✅ | Borders, corners and dividers, as numbers or as part of the image |
| ✅ | Fonts: the file, the size, per element |
| ✅ | Colours: the palette in one spreadsheet instead of constants in the code |
| ✅ | A state per element — normal, hover, pressed, disabled, focus, selected |
| ✅ | Every number that is a size or a margin |

**It is one file, `data/Theme.csv`, and it reaches everything.** Every box in
the game is drawn by one function, and the spreadsheet sits in front of it —
so the `panel` row changes card faces, tiles, dialogs, the strip above the
card row and the keeper's number all at once. A real Godot theme is built
from the same rows and set on the root window, which catches the buttons laid
out by hand in `.tscn` files that never call that function at all.

**Three images ship in `assets/ui/`** so you can see it work before drawing
anything: put `panel_soft` in one cell and the whole game changes.
`tools/theme_shot.gd` photographs the same screen both ways.

**Also in this zip, and not a phase:** the keeper. `data/ShotOdds.csv` turns
his stamina into a percentage that is printed on the screen before the shot,
and an empty keeper is now a certain goal rather than a 90% one. See the
round notes.

## Phase 4 — Out of bounds, and the new PLAY MAKER  ⬅ NEXT

Replacing the 1–10 coin with the sequence you described. One phase on its
own because it is a chain of moments that all have to work together:

1. a hidden roll decides who gives the ball away
2. that player kicks it out — **an animation window**, with a template so it
   runs before any art exists
3. the closest player from the other side walks to where it went out and
   stands outside the line
4. **then** the PLAY MAKER starts, and both sides pick their tiers
5. whoever throws in chooses attack or defend
6. the throw goes to a **team-mate**, and that player starts the relay to the
   Tier I attacker

**Why fourth:** it changes the shape of a match, so everything in Phases 1–3
should be settled first — otherwise I am fixing the presentation of a thing
that is about to be replaced.

---

## Phase 5 — The class system: emblems, the tree, Team Spirit

The biggest one, and the one I have already read and written down —
see section 7c of the Designer Manual and `tools/class_check.gd`.

**What your spreadsheets already say.** A class is **one Star set plus three
emblem sets**:

```
Rauhnacht-Feuergeister
  Set "Star"        3 cards, all Tier IV      the three Star Players
  Set "Belphegor"   9 cards, Tiers I/II/III   an emblem set
  Set "Flauros"     9 cards, Tiers I/II/III   an emblem set
  Set "Buer"        9 cards, Tiers I/II/III   an emblem set
```

and `Rauhnacht-Feuergeister Emblems.csv` names Belphegor, Flauros and Buer —
the same three words. **That file set is exactly right and is the model.**

| | |
|---|---|
| | The **talent tree becomes the class system**: three starting nodes, one per Star |
| | A Star in a node **unlocks its emblem's nine units** — the recipe the Brewery works from |
| | **Three Stars of one class** opens that section and lets you choose one **Emblem** |
| | An emblem is a **two-sided card**: Basic Side, a Condition, an Ultimate Side that turns over when the condition is met |
| | The **Team Spirit** drink, forged when all three match, and the quest that changes it mid-match |
| | Achievements unlock units; the tree makes them usable |

**Why fifth:** it is the deepest system in the game and it needs the
achievements to exist, which they do not yet. Everything above is
independent of it.

---

## Phase 6 — Around the match

The things that live outside ninety minutes.

| | |
|---|---|
| | **Adventure's enemy window** shows the enemies on *that run*, not a league squad |
| | **A fixed number of pickups** before each wave and the boss, from a CSV, instead of however many happen to spawn |
| | **Seasons with their own rules**: what is allowed, what is on the field, what is different — per season, in a CSV |
| | **A dialogue before a season** and **before a fixture** |
| | **The Stadium screen** in the base: colours, background, lights, unlocked through achievements |

**Why last:** none of it is broken, and all of it is content-shaped — it will
go faster once Phase 3 has given it a look and Phase 5 has given achievements
something to unlock.

---

## If you want a different order

Say so. The only hard dependency is **Phase 3 after Phase 2** — skinning
screens I am about to rebuild is work done twice. Everything else can move.

The one I pulled forward was the **goal celebration**, and it was the right
call: it is the moment the game is *for* and it used to pass in about a second
and a half.

**Phase 4 is next unless you say otherwise** — the out-of-bounds sequence and
the new PLAY MAKER. It changes the shape of a match, which is why it waited
for the three phases that settle what a match looks like.

Phase 5 (the class system) still wants achievements to exist first, and
Phase 6 is content-shaped and will go faster now that Phase 3 has given it a
look.
