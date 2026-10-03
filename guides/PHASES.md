# The plan — the order I would go through what is left

You asked for a lot in one message and said to split it if it was too much.
It was. This is the split, in the order I would do it and with the reason for
that order. You can reorder it at any point — the phases are mostly
independent, and where they are not, it says so.

> **Round O renumbered the back half of this plan**, because you added nine
> systems and a foul system to it. Nothing was dropped. The crosswalk is at
> the bottom of this file: **old Phase 5 is now Phase 6, and old Phase 6 is
> now Phase 10 with not one line removed.**

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

## Phase 3 — The skin  ✅ DONE (round M), and dressed in round N

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

## Phase 4 — Out of bounds, and the new PLAY MAKER  ✅ IN THIS ZIP

Replacing the 1–10 coin with the sequence you described. One phase on its own
because it is a chain of moments that all have to work together:

| | |
|---|---|
| ✅ | a **hidden roll** decides who gives the ball away — the man nearest the ball, so nobody is blamed for a ball he never touched |
| ✅ | that player **kicks it out**, over the nearest touchline |
| ✅ | **an animation window**, with a template: an image if you drew one, that player's own `lose` animation if you did not, and the caption alone if neither |
| ✅ | the closest player from the other side **walks to where it went out and stands outside the line** |
| ✅ | **then** the PLAY MAKER starts, and both sides pick their tiers |
| ✅ | **whoever throws in chooses attack or defend** — the same choice the coin used to give, earned rather than guessed |
| ✅ | the throw goes to a **team-mate**, and that player starts the relay to the Tier I attacker |

**It is `data/OutOfBounds.csv`** — the same shape as Celebration.csv, one row
per beat, and an empty file opens a round instantly the way it always could.
`out_of_bounds` = `false` brings the coin back; it is still in the project
and still works.

**Also in this zip, and not a phase:**

* **The scoring, retuned.** I had calibrated the keeper's curve against a
  shot power of 0 to 8 and the game produces 10 to 22 — so matches were 3–3
  and 0–4. It is 1.5 a side now, and there is a tool that measures it.
* **The skin, worn.** Phase 3 built the system; this round drew a Bavarian
  set for it and put three fonts in. `assets/ui/beerhall_*`.

## Phase 5 — The roots: achievements, the referee, the chain  ✅ IN THIS ZIP

Three things that nothing else can be built on top of until they exist.

| | |
|---|---|
| ✅ | **Achievements.** `data/Achievements.csv`, 21 rows. *"Everything needs to be unlocked here first"* — so this is the root of the game and every room, section, emblem, brew and Stadium layer below is handed out by a row of it |
| ✅ | **The foul system.** `data/Fouls.csv`. The more a side sets off in a round, the more likely it is to have given a foul away doing it. Yellows, reds, two-yellows-is-a-red, a man sent off leaving nine — and a stand-in to cover the hole he leaves in the tier |
| ✅ | **The Brewery's chain.** `data/BrewerySections.csv` and `data/BreweryResources.csv` — the six sections as *numbers*, with no map and no mini-games yet. See the note below on why that order |

**Why these three and not the talent tree.** Every one of the nine systems
you listed is gated by an achievement, and six of them are gated by
*something the Brewery makes*. Building the tree first would have meant
writing the gates twice.

> **Why the Brewery's numbers before its map.** A production chain is a thing
> you get wrong in the numbers, not in the pictures. If six bottles from a
> barrel is the wrong number, no amount of drawing the Bottler fixes it — and
> you will have drawn him twice. `tools/brewery_check.gd` walks the whole
> chain from a new game and tells you what the starting stock is worth (24
> bottles) and **what ran out first** (germs, at the Malthouse). Now the map
> can be built on top of something already known to work.

---

## Phase 6 — The Talent Tree, and the classes  ✅ IN THIS ZIP

**This is the old Phase 5, grown.** The talent tree and the class system
turned out to be the same thing described twice — the tree's three starting
nodes *are* the three Stars of a class — so they are one phase.

| | |
|---|---|
| ✅ | The tree itself: nodes, costs, what a node needs, what it hands over — **`data/ClassTree.csv`** and the **Star Hall** screen |
| ✅ | **Brew recipes** — `unlock:Fire Brew`. Already a talent row, and always was |
| ✅ | **Unit-type limits** — `count:class_set_limit+1` for every set, `count:limit_lorelei_sitri+1` for one. Worked example: **Depth of Squad** |
| ✅ | **Resources** — `count:res_hops+6`, straight into the counters the Brewery reads. Worked examples: **Hop Garden**, **Good Water** |
| ✅ | **Adventure maps** — `unlock:Marshlands`. Worked example: **The Marsh Map** |
| ✅ | **Switches on Star Players** — a Star goes into a node, and that node's nine units become yours |
| ✅ | **Three Stars of one class → Emblems.** `flag:three_of_a_kind` is set by the Star Hall, so the `star_collector` achievement is earnable |
| ✅ | An emblem is a **two-sided card**: Basic Side, a Condition in prose, a **`Turns On`** in the condition language, an Ultimate Side |
| ✅ | The **Team Spirit** drink — an ordinary row of Brews.csv, unlocked by name |

**Four of the six were spreadsheet rows and needed no code at all.** The two
that needed code were the Stars and the Emblems, and they are a different
shape from the talent grid — three plinths and a choice — so they are a
second screen sharing one pool of points.

**What it still needs from you:** `Lorelei Emblems.csv` says `Gremory` where
the unit sheet says `Sitri`. `tools/class_tree_check.gd` names both rows, and
it is the only thing standing between that class and a working tree.

---

## Phase 7 — The Brewery, built  ✅ IN THIS ZIP

The map, on top of the chain that is already in the zip.

| | |
|---|---|
| ✅ | The **map** with the six sections on it, placed by an `X` and a `Y` in the spreadsheet, with the chain drawn between them |
| ✅ | The **resources window** and the **brewery-materials window**, at the top — split by the `Kind` column, not by the screen |
| ✅ | Each section **locked until its achievement**, and the locked tile **names that achievement and what to do** |
| ✅ | The **Maltster, Miller, Lauterer, Brewer, Cellarman and Bottler** named on their sections |
| ✅ | The **cellar**: a barrel lagering for one to three turns, with the turns counting down at every fixture |
| ✅ | **Where raw materials come from** — two Progression rows, so a fixture pays the Brewery and a win pays it better |

**What is still to come here:** the six figures as drawn workers rather than
names, and the five brewing mini-games (Phase 9). A mini-game decides how
*well* a section runs; nothing on this screen changes when they arrive.

---

## Phase 8 — The Pub, and the Traveling Brewer  ✅ IN THIS ZIP

Where the bottles go, and where the money is.

| | |
|---|---|
| ✅ | **The Pub.** Right-click seats a player; ten seats, and anyone not in the room plays as a basic unit. Off out of the box (`pub_ten`) because ten seats is only a choice once you have more than ten cards |
| ✅ | **The Traveling Brewer.** `data/Shop.csv` — materials, tools and recipes, priced in wins rather than in coins |
| ✅ | **Currency from wins, and a separate currency per mode** — `data/Currencies.csv`, and `Earned In` is the whole of the separation |
| ✅ | **And the cellar's vats are unlockable**, which was your answer to last round's question: the basic foundation free, everything bigger earned |

**Measured, not guessed:** a season pays 225 coins and the whole cart is 790
(twenty wins). One vat makes 24 bottles a season, two make 48, three make 54
— and at three, hops are the limit, which is exactly what the Brewer sells.

---

## Phase 9 — The four rooms, and the base rebuilt  ✅ IN THIS ZIP

The four rooms. One phase because they are four screens against one save
file, and because each of them is small.

| | |
|---|---|
| ✅ | **Club House** — who is resting and for how long. No spreadsheet of its own: it is a view onto `recovery_book.gd`, which already knew |
| ✅ | **Dorms** — `data/Dorms.csv`. Beds is the TOTAL, the first row is free, the rest are bought |
| ✅ | **Trophy Room** — `data/Trophies.csv`. A trophy is a name and a condition, and does not have to come from a competition |
| ✅ | **Training Ground** — `data/Training.csv`. Ausbildung trains a number; a mini-game automates a Brewery section and buys it a vat today |
| ✅ | **An Achievements building**, which was the one root that had no door |
| ✅ | **THE BASE REBUILT.** Nine buildings and no others, and every one of them opens a **window over the base** instead of cutting to a new scene |
| ✅ | **Visitors go in the gaps** — never in the middle, never layered, and not drawn at all if the yard is full |

**Four buildings were removed** — the Forge, the Still, the Reed Press and
the Cold Cellar — plus the Tap Room and the Gate. They were worked examples
of the recipe pattern rather than rooms, and that pattern is still a complete
trade with no code. Iron Boots, the one thing they granted that something
still needed, moved to the Traveling Brewer's cart.

---

## Phase 10 — Around the match  ✅ IN THIS ZIP — THE LAST ONE

**This is the old Phase 6, unchanged — not one line removed.**

| | |
|---|---|
| ✅ | **Adventure's enemy window** shows the enemies on *that run* — the biome's own pool, with how often each turns up and the boss marked |
| ✅ | **A fixed number of pickups** — `data/Pickups.csv`, spaced evenly over the stretch instead of arriving on a random timer |
| ✅ | **Seasons with their own rules** — `data/SeasonRules.csv`. Allowed classes, no brews, no stars, per tier, and any row of Tuning.csv — all of it **lent and handed back** |
| ✅ | **A dialogue before a season** (already there) **and before a fixture** — a new `Story` column on `Season.csv`, played on the way to the team sheet |
| ✅ | **The Stadium screen** — every layer, whether it is showing, and which achievement opens it. On the top bar rather than a tenth building |

**And the Unlocks button is gone** — the Achievements building shows the same
thing from the same file, and two doors to one room is one door too many.

**That is every phase.** From here it is refining, which is what you said
you wanted — and every system now has a tool that measures it, so refining
means changing a number and reading what happened rather than guessing.

**Why it was last:** none of it was broken, and all of it is content-shaped. It
will go faster with a look to hang it on (Phase 3), achievements to unlock it
(Phase 5) and rooms to put it next to (Phase 9). Three of its five items are
already half-built and waiting — `Stadium.csv` has layers that nothing was
switching on until this round, and the `Floodlights`, `Full House`, `The
Crown` and `The Cup` unlocks are now handed out by achievements.

---

## After the phases — the fixes

Every phase is done, so from here a round is whatever you found wrong.

### Round U — the doors, and the line under the base

| | |
|---|---|
| ✅ | **Clicking a building opens a window again.** `window` was missing from the four actions that need a screen, so `window:brewery` was quietly handed to the effects language, which ignores what it does not know. The click showed the building's description and opened nothing, with nothing said anywhere. Section 4 of the manual has the whole story |
| ✅ | **An action nobody handles is now loud.** Any term in a `Do` or `Action` column whose kind is not real is named in the Output panel every time it runs. That was the actual bug — not the missing word, but that a missing word could go unnoticed |
| ✅ | **The line of unlocks under the base is gone.** It was a developer's line. The Achievements building says all of it properly and says what is still missing too. A spreadsheet problem still gets reported — to the Output panel, once, when the base opens |
| ✅ | **`tools/base_shot.gd` now presses the real buttons** and checks a window appeared, instead of opening the windows itself. The old tool produced twelve perfect pictures of a broken game |
| ✅ | **~150 red errors per room, gone.** `room_screen.gd` was adding every row to its list twice — harmless on screen, and loud enough to bury the one Output line that mattered |

**The lesson worth keeping:** a tool that reaches past the button cannot see
a broken button. Both bugs this round were *silent*, and both fixes were
half about the bug and half about making that kind of silence impossible.

---

## After the fixes — the combat abilities (round Y onward)

The next stretch of work has a plan of its own: **`guides/COMBAT_PHASES.md`**.
Eight phases, C1 to C8, each bringing a measured batch of your cards' abilities
to life. C1 shipped in round Y (33 abilities work, up from 1); **C2 — counters,
tokens, Ore, swans and five Emblem Basic sides — in round Z (103 work)**.
**C3 — the keeper and the referee — is next.**

On hold until the combat abilities are done, at your request:

- **Pass 2 of the art** (title, base yard, the pitch) — no PixelLab until then.
- A **recruitment board** in the Club House, so `named_recruits` can be turned on.
- Hiding the **Rivals'** cards from the Pub.
- Which **tier** a plain player can turn into when only Stars hold it (you chose
  option (a): leave it).
- **Rotate the PixelLab API key** that was pasted into a chat (round X).

## The crosswalk — where everything went

| it used to be | it is now |
|---|---|
| Phase 5, the class system | **Phase 6**, joined with the Talent Tree — done |
| Phase 6, around the match | **Phase 10**, word for word |
| *(new)* the foul system | **Phase 5**, done |
| *(new)* Achievements | **Phase 5**, done |
| *(new)* Talent Tree | **Phase 6**, done |
| *(new)* Brewery — the chain | **Phase 5**, done |
| *(new)* Brewery — the six sections on a map | **Phase 7**, done |
| *(new)* Pub | **Phase 8**, done |
| *(new)* Traveling Brewer | **Phase 8**, done |
| *(new)* Club House | **Phase 9**, done |
| *(new)* Dorms | **Phase 9**, done |
| *(new)* Trophy Room | **Phase 9**, done |
| *(new)* Training Ground | **Phase 9**, done |

---

## If you want a different order

Say so. There are only three hard dependencies in the whole plan:

```
   Phase 3 after Phase 2     skinning screens I am about to rebuild is
                             work done twice
   everything after Phase 5  nine of the systems are gated by an
                             achievement, and six by something the
                             Brewery makes
   Phase 8 after Phase 7     a Pub with nothing to pour
```

Everything else can move. **Phases 9 and 10 in particular can be swapped, or
either of them pulled forward**, if you would rather have rooms to walk
around before the tree is finished.
