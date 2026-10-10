# Sturmball — the designer's manual

**Everything in this game that is content lives in a spreadsheet.** This
document is the complete list of those spreadsheets, what every column does,
and how the systems that read them fit together. It is written for somebody
who is designing the game, not somebody who is writing the code.

You do not need to read it in order. Section 2 is the one rule you cannot
break. Section 4 is the language that appears in fifteen different
spreadsheets. Section 16 is a cookbook of "I want to change X, which file do
I open".

*Engine: Godot 4.7. Repository: github.com/SchwartzAnthony/project_sb*

---

## 1. What the game is, in one page

Sturmball is a football autobattler with two completely separate combat
systems.

**THE LEAGUE MATCH** is the main game and the one progression runs through.
Ninety in-game minutes, three cycles of three rounds. Each round opens with
**PLAY MAKER!** and you draft one player from each of your four tiers. Those
four fight the opposition's four in a series of duels, and the winner takes a
shot at goal. Between cycles there is a **STAR PLAYER SWITCH**: the Star who
has been playing steps off and you pick another. Players have **abilities**
here, out of `Abilities.csv`, and combos out of `Combos.csv`.

**ADVENTURE MODE** is a side mode and plays nothing like it. Your party runs
along a scrolling pitch collecting things until a wave of enemies blocks the
way. You pick which enemy to go after, then draft one player per tier — and
in Adventure a player brings **icons**, not abilities. Every player you send
in drops their icons on a pile, and `AdventureCombos.csv` says what holding
three of one is worth. The pile does not reset each round; it resets when the
**cycle** comes round, meaning every tier has fielded everybody it has.

Both modes use the same cards, the same tiers, and the same four-slot draft.
Everything else about them is different on purpose.

---

## 2. THE TIER LADDER — the one rule nothing may break

**`data/TierPowers.csv`**

| Tier | Min Attack | Max Attack |
|---|---|---|
| I | 0 | 2 |
| II | 1 | 3 |
| III | 2 | 4 |
| IV | 3 | 5 |

Read it as a list of **slots**. Tier I holds one 0, one 1 and one 2 — three
cards, three different powers, never two the same. Tier II holds one 1, one 2
and one 3. And so on.

This has three consequences that decide how the whole game is balanced:

1. **A card's power is its tier slot.** It is not a stat you tune; it is a
   position on a ladder. Changing a card's Base Power Left moves it to a
   different slot, and possibly a different tier.
2. **Every legal team has the same total power.** That is the point. Teams
   differ by *what their players do*, never by how big their numbers are.
3. **A bonus is never added to a card.** Combos, difficulty scaling, talents
   and trait breakpoints all add to the **shot** instead. If anything ever
   adds power to a card, the ladder breaks and two cards end up on the same
   rung.

The span must stay three wide. Widen it to four and every tier holds four
cards, which changes squad size everywhere.

`tier_ladder.gd` enforces this. `tools/adventure_soak.gd` checks it after
every test fight, including on stand-ins brought on by a combo.

---

## 3. Where everything lives

```
res://
  data/           EVERY SPREADSHEET. This is your folder
  data/tutorial/  a second set of Dialogue / Buildings / Visitors, used by
                  the tutorial only. Same columns, different content
  assets/         art, audio, icons
  src/core/       loaders, rules and shared helpers (60 scripts)
  src/ui/         screens (38)
  src/adventure/  Adventure mode (12)
  src/units/      things that stand on the pitch (4)
  src/formations/ the league match itself (1, and it is a big one)
  tools/          test and inspection tools. Nothing in the game loads these
  guides/         this document and the older round notes
```

`data/FileManifest.csv` is a list of every file and the folder it belongs in.
The title screen checks it on startup and prints, in words, anything that is
missing, in the wrong folder, **or duplicated**. Add a file to the project,
add a row, and the check guards it too.

### Where art and audio go

**The rule for all of them:** a column holds the file **name**, without the
folder and usually without the extension — a column reading `mill` finds
`assets/icons/mill.png`. A column starting `res://` is used exactly as
written. **Nothing breaks while a file is missing**: an icon draws as a
coloured pip, a sound is silent, a card falls back to a plain disc. Each list
is tried in order, so the first folder is the tidy home and the rest are
fallbacks.

| Folder | What goes in it | Format | Fed by |
|---|---|---|---|
| `assets/ui/` | **the skin**: 9-slice panels, windows, buttons, bars | `.png` with transparency. Small — 48×48 is plenty, because it stretches. Draw it **light and desaturated** unless the row says `Tint` = `no` | Theme.csv `Image` |
| `assets/fonts/` | the game's typefaces | `.ttf` or `.otf` | Theme.csv `Font` |
| `assets/audio/` | every sound and every piece of music | `.ogg` for music (it loops properly and is a tenth of the size), `.wav` for short effects | Audio.csv `Sound`, Juice.csv `Sound`, Biomes.csv `Music`, Dialogue.csv `Music` |
| `assets/icons/` | small square pictures — trait icons, item icons, menu glyphs | `.png` with transparency, 64×64 or 128×128, the same size across a set | AdventureTraits `Icon`, AdventureCombos `Icon`, Items `Art`, MenuConfig `Art Path`, AdventureSpawns `Art` |
| `assets/players/` | card spritesheets, one per card | `.png`. Default grid is **12 × 39** — write an Animations.csv row for anything else or the card shows as a sliver | any unit CSV's `Artwork`, Brews `Artwork` |
| `assets/goalies/` | keeper art | `.png` | Goalies `Artwork` |
| `assets/base/` | the base and its buildings. A file called `background` here is the backdrop (the town map, made by `tools/make_base_town.py`) | `.png` / `.jpg`. Buildings are placed by X and Y (0–1 across the screen), so draw them to stand alone | Buildings `Art` |
| `assets/portraits/` | faces for dialogue and base visitors | `.png` with transparency | Visitors `Portrait`, Dialogue `Portrait` |
| `assets/story/` | **round AN:** the conversation faces (`portraits/`, 512×512) and rooms (`backgrounds/`, 688×384, in layers) | `.png` with transparency | StoryArt.csv `Image` |
| `assets/backgrounds/` | full-screen scenery | `.jpg` / `.png` at 1920×1080. A biome background **tiles and scrolls**, so match its left and right edges | Biomes `Background`, Dialogue `Background` |
| `assets/menu/` | menu and class banners | `.png` / `.jpg`. A class banner is roughly 3:1 | ClassInfo `Banner Art`, Seasons `Art`, Bounties `Art` |
| `assets/talents/` | talent tree icons | `.png`, square, 64×64 | Talents `Art` |

Fallback folders, tried after the ones above: `assets/sound/`,
`assets/music/`, `assets/buildings/`, `assets/brews/`, `assets/scenes/`,
`assets/` itself. A file dropped straight into `assets/` is always found — it
is just harder to live with once there are two hundred of them.

**The workbench turns this into a live shopping list.** Open
`sturmball_workbench.html`, load your `data` folder, and the *Where things
go* tab lists every file your spreadsheets are currently asking for, grouped
by folder, with a tick box each.

---

## 4. The condition language

Two columns appear over and over: **Requires** (is this allowed / visible?)
and **Effects** or **On Win** or **Do** (make this happen). They both speak
the same small language, and learning it once covers fifteen spreadsheets.

**Terms are joined with a semicolon, and ALL of them must be true.**

### Asking a question — `Requires`

```
flag:brave                the flag is set
!flag:brave               the flag is not set
unlocked:Lorelei          you have unlocked it
!unlocked:Lorelei         you have not
count:gold>=10            a number comparison. >= > <= < = != all work
count:gold                shorthand for "more than zero"
is:winter                 a state check
```

`unlocked:Marsh King;count:coins>=200` means *both*.

### Making something happen — `Effects` / `Do` / `On Win`

```
unlock:Water Brew         unlock something
flag:beat_the_keeper      set a flag
flag:brave=false          clear a flag
count:gold+10             add to a number
count:gold-25             take some away
count:gold=0              set it outright
story:prologue            play a dialogue scene
announce:First win!       put a banner on the screen
sign:Müller               a card joins your squad (read once squad_ownership is on)
recruit:I0                a NEW plain player, Tier I Power 0, with a name of his own
recruit:I0=Johannes       ...and call him Johannes, if nobody else is
release:Johannes          he leaves the base for good; his name is free again
```

`recruit:` is round X — see section 6b. Its tier and power are written
together: `I0`, `II3`, `IV5`. A typo (`recruit:V9`) is refused out loud in
the Output panel, like every other word this language does not know.

**`count:` and `flag:` are the escape hatches.** A shop price is
`count:gold-25`. An achievement is `flag:beat_the_keeper`. Base building is
`count:wood+10`. None of that needs new code — you write it in a cell.

### The four that need a screen

Everything above is written into the save on the spot. **Four cannot be**,
because they *open* something, and only the screen that asked knows where to
open it:

```
story:prologue            play a dialogue scene
goto:brewery              leave this screen, open that one full-screen
announce:First win!       put a banner on the screen
window:brewery            open that screen OVER this one, in a window
```

These are the **deferred** actions. `Progression.run_actions()` hands them
back to whoever called it instead of applying them, and that caller does the
opening. The list lives in exactly one place — `DEFERRED`, at the top of
`src/core/progression.gd` — so if a fifth is ever added, that constant is the
only thing to edit.

> **This is where a real bug lived, and it is worth reading once.** `window`
> was missing from that list. So a building whose `Action` said
> `window:brewery` had the term quietly handed to the condition language
> instead — which does not know the word `window`, and ignores what it does
> not know. Clicking a building showed its description and **did nothing
> else**: no error, no warning, nothing in the Output panel.
>
> It is fixed, and so is the *shape* of the mistake. **A term whose kind is
> neither deferred nor part of the condition language is now said out loud**,
> by name, in the Output panel, every time it runs. Any typo you ever make in
> a `Do` or `Action` column will now complain instead of going quiet. An
> action nobody handles is the hardest kind of bug there is, because there is
> nowhere to look.

A special case worth knowing: **`count:tune_<row>+<n>` edits a row of
Tuning.csv.** That is how talents work. `count:tune_press_speed+12` adds 12
to the `press_speed` row for as long as the talent is held. Any Tuning row
can be driven this way.

The rules are in `src/core/dialogue_grammar.gd`, and a malformed term is
reported by name on load rather than silently ignored.

---

## 4b. Achievements — where everything comes from

> *"Achievements = for new content, systems, players, resources, etc.
> EVERYTHING NEEDS TO BE UNLOCKED HERE FIRST."*

So `data/Achievements.csv` is the root of the game. A room in the base is not
there until an achievement says so; a Brewery section cannot be worked in; a
Stadium layer is off; an emblem does not exist. Nothing else is allowed to be
the first gate.

### A row

| column | |
|---|---|
| `ID` | yours. It is how the game remembers you earned it, so it may not change once a save exists |
| `Name` | what it is called on the board |
| `Description` | what you did to get it |
| `Needs` | **the condition language of section 4** — `count:goals>=10`, `flag:x`, `unlocked:y`, joined with semicolons |
| `Unlocks` | what it hands over. Semicolons for more than one |
| `Reward` | anything else, in the Do language — `give:coins+50`, `flag:x`, `announce:Text`, `story:chapter2` |
| `Art` | an icon in `assets/icons/` |
| `Hidden` | `yes` keeps it off the board until it is earned. For endings and surprises |

A row needs **either** an Unlocks **or** a Reward. One with neither is
earned and then does nothing, and the loader says so.

### It is not a new vocabulary, and that is the whole point

The game already had one way to say "you have this": `unlock:Brewery` grants
it, `unlocked:Brewery` tests it, `GameState` remembers it. A second, parallel
system for achievements would mean two answers to "is the Brewery open", and
one day they would disagree.

So the `Unlocks` column is turned into exactly those words. Everything
downstream — buildings, talents, classes, Stadium layers, Brewery sections,
brews — keeps testing `unlocked:` and never knows this file exists. **Which
means you can move where something is granted from without touching the thing
that is granted.**

> **Unlock names are matched loosely** — lowercase, letters and digits only.
> `Master Brewer`, `master_brewer` and `master brewer` are one unlock, not
> three. Your spreadsheets spell it all three ways and that is fine.

### When it is checked

`AchievementBook.review()` runs **when a screen opens** and **at the final
whistle**, walks every row, and grants anything that has just come true. It
is idempotent: an achievement already earned is skipped, so calling it a
hundred times grants nothing twice.

The whistle one runs *after* the match has reported its counters, so an
achievement asking for `count:goals>=10` sees today's number, not yesterday's.

### The question only a tool can answer

```
godot --headless --script res://tools/achievement_check.gd
```

Two directions, and both of them matter:

* **an achievement that waits on a counter nothing counts** is an achievement
  nobody will ever earn. It names the counter
* **something tested but nobody grants** — a room whose door no achievement
  opens. This one is a real problem and it is printed as one
* something granted that nothing tests yet is printed as a dot, not a
  problem. That is a room waiting for its door, which is the normal state of
  a game you are still building

---

## 5. How the game reads a spreadsheet

Five things worth knowing before you edit anything.

**1. Files are identified by their COLUMNS, not their names.** A units file is
anything with a `Unit Type` column and a power column — either `Base Power`
or `Base Power Left`. You can call it `Units Set FO2 - Whatever.csv`, drop it
in `data/`, and it loads. The same is true of brews, enemies, biomes and the
rest. **Adding content usually means adding a file, not editing one.**

> **And if it cannot read one, it now says so by name.** A file with a
> `Unit Type` column and no power column used to fall through every test and
> be **silently skipped** — the whole team simply was not in the game, with
> nothing printed anywhere. That is the single most expensive kind of mistake
> a CSV-driven game has, and it cost this project a team: `BasicTeam.csv` had
> been simplified to one `Base Power` column and had not loaded since.

**2. Column names are normalised.** `Base Power Left`, `base power left` and
`BasePowerLeft` are the same column. Spaces, underscores, hyphens and case are
all ignored. You cannot break a file by capitalising a header differently.

**3. A blank cell means "the sensible default", never a crash.** Every loader
has a fallback for every column. A half-filled row still loads.

**4. Every `.csv` needs a `.csv.import` file beside it.** It contains exactly:

```
[remap]

importer="keep"
```

Without it, Godot decides your spreadsheet is a **translation table** and
generates one `.translation` file per column — which is where the 148 junk
files in `data/` came from. When you add a new CSV, copy any existing
`.csv.import` next to it and rename it. If you forget, delete the
`.translation` files it made, add the import file, and reopen the project.

**5. A bad row is reported by name.** Loaders collect complaints and print
them once, as a list, naming the file and the row number. If something is not
appearing in the game, the Output panel almost always says why.

---

## 6. Your cards — the unit spreadsheets

**`data/BasicTeam.csv`, `data/Units Set FO1 - Lorelei.csv`, and any file you
add with the same columns.**

| Column | What it does |
|---|---|
| `Unit Type` | the class / club. Must match a `Class` in ClassInfo.csv |
| `Name` | the card's name. Used as its identity everywhere — **renaming a card breaks old saves**. Every card needs its own: since round X the workbench flags two cards with one name, and flags `Unit Name` as a placeholder |
| `Player Type` | `Normal` or `Star` |
| `Base Power` | **power. This is the tier slot.** See section 2. One column is enough — it is read as both attack and defence |
| `Base Power Left` / `Base Power Right` | or write the two faces separately. Left is attack, right is defence. A file with both is read as both |
| `Tier` | `I` / `II` / `III` / `IV` |
| `Element` | Fire / Water / Wand / None. Drives Adventure icons and some targeting |
| `Attack` / `Defend` | the printed card text. Flavour, not rules |
| `Artwork` | a file in `assets/`. The whole spritesheet; `Animations.csv` says how to slice it |
| `Level`, `Stufe`, `Tool`, `Card Number`, `Card Date`, `Set Name`, `Created by` | card-collection metadata |
| `Attack Ability` / `Defend Ability` | **optional.** An ID from Abilities.csv. See `example_unit_csv_with_ability_columns.csv` |

**`data/ClassInfo.csv`** declares which classes exist:

| Column | |
|---|---|
| `Class` | must match the `Unit Type` column of your cards |
| `Display Name`, `Description`, `Banner Art`, `Formation Art` | presentation |
| `Requires` | a locked class is not on the team-builder screen until this passes |
| `Hidden` | `yes` removes a class outright without deleting its cards |

**`data/Goalies.csv`** is one keeper per team: `Team`, `Name`, `Max Stamina`,
`Passive / Ability`, `Artwork`. A keeper is not part of the tier ladder.

**`data/Animations.csv`** slices spritesheets:
`Animation`, `Unit Type`, `Sheet Columns`, `Sheet Rows`, `Row`, `First
Frame`, `Frames`, `FPS`, `Loop`. Leave `Unit Type` blank for a rule that
covers every class. If a card has no matching row it falls back to a 12 × 39
grid, which is why an unsliced sheet shows as a sliver rather than nothing.

---

## 6b. Names — every player has his own (round X)

> *"The Goetia names are for the star players. For the other names it would
> be German names that are common... they all have to have unique names, and
> when they are on a team, on the field or in the player's database they keep
> that name until they are removed from the base entirely."*

### The 108 set cards are named

Every `Unit Name` in the four `Unit_Set_*.csv` files is now a common German
first name — Tobias, Erich, Karl, Kerstin, Matthias… — no two alike, and none
shared with BasicTeam's surnames or the Goetia Stars. **Change any of them;
just keep them unique.** (Your own example, Johannes, is deliberately left
free for a recruit.)

### `data/Names.csv`

| column | |
|---|---|
| `First Name` | the list a new player's name is drawn from |
| `Surname` | used only when every first name is taken: *Johannes Bauer* |
| `Notes` | yours |

The two columns are independent lists — they need not be the same length.
**Taken** means: any card in any unit file has that name, or any player at
your base does. So a recruit is never Gremory, never Müller, never a second
Johannes. 180 first names and 110 surnames ship; 72 first names are still
free after the set cards, and then there are 19,800 pairs.

### Recruits — plain players with names of their own

A recruit is **not a new row in a spreadsheet**. He is a copy of a plain card
— BasicTeam's Tier I Power 0, say — wearing his own name. Recruit three
Tier I Power 0s and you have three men, one card underneath, three names.

```
   recruit:I0              a Tier I, Power 0 plain player, any free name
   recruit:III3            Tier III, Power 3
   recruit:I0=Johannes     and call him Johannes, if nobody else is
   release:Johannes        gone from the base; the name is free again
```

Those go in any `Effects` / `Do` / `Action` / `Reward` column. A recruit is
**signed into the squad** at the same time, so `squad_ownership` sees him.

### It is behind a switch, like squad ownership

`named_recruits` in Tuning.csv is **true since round AH** — the recruitment
board is the building that recruits. (False: a `recruit:` is still written
into the save, but nobody new appears on any screen.) Recruits appear in
the card list as plain players; the Pub brews them into a class.

**`squad_ownership` stays false.** Turned on, your card list would be ONLY
the players a `sign:` gave you — and nothing signs the set cards, because
the Star Hall already decides which sets are yours. It is for a future
opening where you start with nobody.

### The recruitment board — `data/RecruitBoard.csv` (round AH, phase P3)

In the **Club House**, above the resting list. Your Q123.

| column | |
|---|---|
| `Slot` | a number, to keep the rows in order. One row = one place on the board |
| `Tier` | I, II, III or IV |
| `Powers` | the powers he may have, drawn at random: `0 1 2`. Each needs a plain card at that tier and power (BasicTeam.csv) |
| `Cost` / `Currency` | what signing costs, from which purse (`data/Currencies.csv`) |
| `Requires` | the condition language. Not met = the place shows LOCKED with what it needs |

- **New faces after every match** (`matches_played` went up). A man you did
  not sign leaves; his name is free again.
- **Sign** = pay, and he joins under his own name. **Release** (under *Your
  recruits*) = he leaves, his bed and name are free.
- **Beds:** you may hold `beds − recruit_beds_kept` recruits (`9` kept for
  your team's regulars; the Old Hut's 12 beds = 3 recruits). The Dorms sell
  beds.
- `recruit_board_reroll_cost` (10 coins) puts new men up now; `0` = no
  button. `recruit_board` false hides the board.
- As shipped: two Tier I places (30 coins), one Tier II place (60 coins)
  from your third match.
- `godot --headless --script res://tools/recruit_board_check.gd` tries it all
  on a pretend save.

`recruit_plain_class` (Tuning.csv, `Normal`) says which class a recruit is a
plain copy *of*.

### Where it lives

In the save: `recruits` (`Johannes|Lukas|Theresa`), `recruit_<name>` (his
tier and power), and `names_held` — the list `NameBook` checks before it
hands a name out. Code: `src/core/name_book.gd`, `src/core/recruit_book.gd`.

---

## 7. The league match

`src/formations/main_scene.gd` runs it. Nothing in that file names a card, a
number or a team.

### How a match goes

```
kickoff
  cycle 1   round 1  PLAY MAKER! -> draft 4 -> duels -> shot
            round 2  PLAY MAKER! ...
            round 3  PLAY MAKER! ...
  STAR PLAYER SWITCH — your Star steps off, you pick another
  cycle 2   three more rounds
  STAR PLAYER SWITCH
  cycle 3   three more rounds
full time
```

Three cycles × three rounds = 9 PLAY MAKERs and 2 STAR PLAYER SWITCHes,
eleven pauses in a match. `rounds_per_cycle` and the Cycles column of
MatchModes.csv change that.

> The audio event for the Star switch is still called `hold_up` — that is the
> key your Audio.csv row is written against. The words on screen changed; the
> spreadsheet key deliberately did not.

### Who the ball goes to, and the restarts

**Tier IV is never passed to in ordinary play.** Tier IV stands nearest the
goal, and watching one take the ball on the edge of the box and knock it
sideways raises the obvious question of why they did not simply shoot — the
answer being that shooting is not what waiting play is for. So the ball goes
round the other tiers and the front line waits for the PLAY MAKER.

| Tuning row | |
|---|---|
| `pass_skips_tiers` | which tiers are never passed to. `IV` out of the box. `III;IV` keeps two of them out. **`none`** lets the ball go to anybody |

It is a rule about **who**, not about where they are standing. There is a
second, older rule about the end quarters of the pitch which still applies on
top of it; either one is dropped for a single pass if obeying it would leave
the carrier with nobody at all to pass to, because a rule about what looks
right is never worth freezing the match over.

**At a restart the keeper is left alone and everybody walks home.** The break
is ended the moment the ball is dead rather than when play resumes, and then
the whole pitch goes into a **restart hold**: nothing chases, nothing presses,
nothing marks, and every outfield player walks back to their own starting
position. The keeper stands there with the ball. When they kick it the hold
ends mid-stride and the ordinary rules take over.

That state had to exist on its own. Once the keeper has the ball, the ordinary
rules say *"the ball is in my quarter and the other side has it, go and win
it"* — so the far side's Tier I and Tier IV both set off for the keeper and
stood over him, which is not a thing that happens in football.

| Tuning row | |
|---|---|
| `goal_pause_seconds` | the hold after a goal. `2.0` |
| `save_pause_seconds` | the hold before the keeper kicks. `2.0` |
| `restart_walk_boost` | how briskly they walk home, as a multiple of walk speed. `1.6` is purposeful; `1` is an amble; past `2.5` it looks like a jog |
| `goal_kick_tier` | which tier the keeper aims at. `III` |

> `tools/restart_check.gd` is the test for this. It plays a real match with
> AUTO on and prints, every second, how far everyone moved and how many
> outfield players are standing over a keeper. Six was normal before; two is
> normal now, and two is a side's own defenders in ordinary play.

**Nobody stands still.** Once a player is home during a restart hold they do
not freeze there waiting for the whistle — they are handed a wandering point
inside their own quarter and they potter about it, the same drift they use at
any other quiet moment. A pitch of twenty-two statues reads as a paused game;
a pitch of twenty-two people shifting their weight reads as a game about to
start. **The only things that stop the pitch are the ones the player chose:**
picking a card, swapping a Star, the pause menu, and the START button.

### How a PLAY MAKER starts — `data/PlayMakerStarts.csv` (round AC)

Your Q060: **all five**, picked by where the ball is when play stops.

| Start | when | who restarts | who decides the round |
|---|---|---|---|
| `throw_in` | near a touchline (also from the middle) | the other side, from outside the line | the thrower picks ATTACK / DEFEND (as before) |
| `corner` | a defender near his own goal line gives it away | the attackers, from the corner flag | they attack (Q061) |
| `goal_kick` | an attacker near the goal he attacks puts it over | the defenders, from the six-yard box | they attack |
| `keeper_claim` | an attacker loses it near goal | the keeper, from his hands | his side attacks |
| `drop_ball` | play stops in the middle | the referee drops it | the old clash: the winner attacks |
| `storm_gust` | rare, anywhere | the wind blows the ball somewhere; a random side gets there | its player picks ATTACK / DEFEND |

- **Zone** `wide` (within `play_maker_wide_band` of a touchline), `middle`
  or `any`. **Chance** is a weight; every possible row's weights are added up
  and one is drawn. 0 switches a row off.
- **Restart**: `chooses`, `attacks`, `race`, `coin`.
- **Call** is the big word ("CORNER"), **Caption** the window's line
  (`{loser}`, `{thrower}`, `{keeper}`).
- **The beats are still OutOfBounds.csv**: its `say` row shows `{call}` and
  its `window` row `{caption}`.
- Waiting play keeps the ball in quarters 2 and 3, so it is never near a goal
  when play stops - which is why the corner, goal kick and keeper rows say
  `any` and happen where that player is standing (Questions Q081).
- To watch one: `SHOT_START=corner` on tools/combat_shot.gd (or
  `SOAK_START=corner` on tools/match_soak.gd).

### Why they were shaking, and what fixed it

A player is pulled by several things at once — the place they are going, the
other players around them, their own quarter, their formation slot. The old
code picked the strongest one and walked at full speed in that direction,
which is why the left-hand side looked the way it did: two players a hair
apart would each be pushed out, arrive, be pulled back, and do it again sixty
times a second. That is not movement, it is an argument.

Now every pull is **added up first** and the player moves once, along the sum,
and:

- **they ease off as they arrive** (`unit_arrive_radius`) instead of running
  into the spot and overshooting it,
- **a weak sum means standing** (`unit_still_threshold`) — a player tugged two
  ways equally stops, which is what a person does,
- **inside `unit_personal_space` the shove is at full strength** whatever else
  is going on, so two players fighting for the ball still cannot occupy the
  same pixel,
- **turning to face the ball has a dead band** (`unit_face_deadzone`), so a
  player with the ball dead ahead no longer flips left-right every frame.

| Tuning row | |
|---|---|
| `unit_personal_space` | how close is too close, in pixels. `34`, about how wide a player is drawn |
| `unit_arrive_radius` | where easing-off starts. `14`. **The row that stops the shaking** — raise it if a group still fidgets |
| `unit_still_threshold` | how weak a pull has to be before they simply stand. `0.12` |
| `unit_face_deadzone` | how far to one side the ball must be before they turn. `18` |
| `unit_contest_crowding` | how much giving-way survives near the ball. `0.55`. `1` = they never crowd it; `0` = a scrum |

> `tools/movement_check.gd` is the test. It plays ninety seconds with AUTO on
> and prints **reversals per second** (how often somebody turns more than
> 120°, which is what shaking actually is) and **the pile-up**, meaning pairs
> closer together than a player is drawn wide, at the worst moment and on
> average. It went from **11 reversals a second to 3**, and the pile-up now
> averages **0.4 pairs** across twenty-two players — the worst moment is three,
> and three for a tenth of a second is a scramble for a loose ball, which is
> football.
>
> It counts reversals rather than "distance walked ÷ distance gained" on
> purpose: the second number calls a wandering player a shaking one, and the
> wandering is wanted.

### Eyes on the ball, and only sprint when it is in range (round AN)

Anthony: *"All players should be facing towards the ball, but they shouldn't
be sprinting towards it unless they are within the ball's range."*

Every player has a **job** each frame. Five jobs are *going for the ball*
(BALL, PRESS, RECEIVE, DRIBBLE, SURGE) and four are *watching it* (HOLD, MARK,
OPEN, RECOVER).

- **Watching it**: he faces the ball the whole time, even while he shuffles
  across or drops back, and his legs go at a jog (his speed ÷ his sprint speed
  of the run animation). Slower than `unit_stand_below_speed` he just stands.
- **Going for it**: he faces where he runs, at full animation speed.
- **The ball's range** is the press reach (`press_radius_fraction` of the
  pitch height). Outside it nobody goes faster than `far_from_ball_pace` × his
  walk. That is what had the back rows (Tier I and the far Tier IV) tearing
  about at the far end of the pitch.
- After turning, a player keeps his facing for `unit_face_turn_hold` seconds,
  unless the ball goes round behind him.

| Tuning row | |
|---|---|
| `far_from_ball_pace` | top speed outside the ball's range, × walk. `1.2`. `0` = off |
| `unit_face_turn_hold` | seconds a facing is held before the next turn. `0.3` |
| `unit_stand_below_speed` | px/s under which a watcher is drawn standing. `16` |
| `unit_walk_anim_floor` | slowest the legs go for a watcher, share of the run rate. `0.4` |

**Only a few go for it.** Anthony: *"a few people piling up is great but
when it is player units not protecting their zone it is also a little too
much."* Every rule that sends a player at the ball (a loose ball in his claim
band, the press, the run to a goal kick) now sends at most
`ball_chasers_per_side` of each side, the nearest to where the ball is going.
Everyone else marks or holds in his own quarter. Before: about **7** players
went for the ball on average and **19** at a goal kick. After: about **2**, and
**4** at most.

| Tuning row | |
|---|---|
| `ball_chasers_per_side` | how many of a side may go for the ball at once. `2`. `0` = no limit |

**Nobody runs away from the ball to get open.** Anthony: *"why would they
turn away from the ball and run towards the edge of the field for no
reason?"* The probe showed it was mostly players **showing for a pass**
(OPEN): the spot was their home slot plus 230 px off their marker, 120
forward and 150 toward their touchline, so a man on the far side of the play
walked further away to "get open". Markers following their man did the rest.

Now both keep to a **ring round the ball**: no closer than `open_support_min`
(a marker: `mark_keep_off`), **never further than they already are** (up to
`open_support_max`), and inside their own quarter (`open_zone_margin`). A
"don't stand still" fresh spot also prefers space near the ball
(`fresh_spot_ball_weight`). Away-from-the-ball running went from about **390**
player-seconds a minute to about **65**.

| Tuning row | |
|---|---|
| `open_support_min` | closest a player showing for a pass comes to the ball. `190` px |
| `open_support_max` | furthest he may be sent from it. `340` px. `0` = off |
| `open_zone_margin` | how far past his own quarter that spot may be, share of a quarter. `0` |
| `mark_keep_off` | closest a marker comes to the ball under the same rule. `120` px |
| `fresh_spot_ball_weight` | how much a fresh spot prefers being near the ball. `1.2` |
| `open_spread` / `open_break` / `open_width` | now `90` / `70` / `50` (were 230 / 120 / 150) |

**Moving for an opening, and cutting the lane (9 Oct).** Anthony: *"1 or 2
people on the person that has the ball, but the rest are waiting for a pass
... not standing there, but trying to move for an opening ... and trying to
defend ... a back and forth that looks natural."*

- The ring above used to say "never further than you already are", which
  ratcheted the whole pitch in on the ball. Now the cap is the further of
  *where he is* and *his own place in the shape* (the drift point, which
  slides with the ball). He never goes past his place; he can go back to it.
- **Showing for the pass:** every `open_rethink_seconds` (a little different
  for each player) he looks at spots up to `open_search_radius` round his
  place and goes to the most open one: away from defenders, a clear lane for
  the ball, not on a team-mate, not too near the ball.
- **Marking:** the marker leans `mark_lane_cut` off his man toward the ball,
  into the lane, which sends the attacker off to find another opening.
- **Seeing the ball:** an arrow in his side's colour floats over the man on
  the ball (`ball_carrier_marker_height` / `_size`), his ring pulses, the
  name plates of players not involved fade (`bystander_plate_alpha`), and
  during play only players going for the ball get a line
  (`intent_lines_chasers_only`). Z still shows everything.

| Tuning row | |
|---|---|
| `open_search_radius` | how far round his place he looks for an opening. `220` px (doubled 9 Oct) |
| `open_rethink_seconds` | how long he goes for one before looking again. `0.7` (twice as often, 9 Oct) |
| `mark_lane_cut` | how far a marker leans into the passing lane. `100` px (doubled 9 Oct) |
| `open_support_min` / `mark_keep_off` | now `270` / `200` px from the ball (the 9 Oct step, doubled) |
| `bystander_plate_alpha` | name plates of players not involved, in open play. `0.18` (twice as faded, 9 Oct). `1` = off |
| `intent_lines_chasers_only` | `true` = lines only for players going for the ball |
| `ball_carrier_marker_height` / `ball_carrier_marker_size` | the arrow over the carrier. `74` / `20` |

**The back rows: half the range, shadowing, breathers (9 Oct).** Anthony:
*"Tier IV / Tier I ... still grouping too much and ... running into an
invisible wall ... If they are outside of the ball range (maybe make it
smaller by half) have them chase the person they should be watching."*

- **The ball's range is half what it was** (`press_radius_fraction` 0.55 →
  0.275). Inside it, pressing and sprinting as before.
- **Outside it a marker shadows his man**: `mark_shadow_commitment` of the
  way to goal-side of him, and not held to his quarter. Holding him to the
  quarter is what had him leaning on an invisible line while his man walked
  off.
- **Breathers**: off the ball a player runs for `unit_run_burst_min`–`_max`
  seconds, then stands watching the ball for `unit_rest_min`–`_max`.
- **No running into walls**: if he makes under `unit_stuck_progress` px in
  `unit_stuck_window` seconds while his target is still away, he stops and
  takes a breather instead.
- **Committing to a run**: a player getting open looks again only when he
  has got there (or after twice `open_rethink_seconds`), and only switches
  for a spot that beats his by `open_switch_margin`.

| Tuning row | |
|---|---|
| `press_radius_fraction` | the ball's range, share of pitch height. `0.275` (halved) |
| `mark_shadow_commitment` | how close a marker outside the range stays on his man. `0.85` |
| `unit_run_burst_min` / `_max` | seconds of running before a breather. `2.5` / `4.5` |
| `unit_rest_min` / `_max` | seconds a breather lasts. `1` / `2`. `_max` 0 = off |
| `unit_stuck_window` / `unit_stuck_progress` | the wall check. `0.8` s / `18` px |
| `unit_rest_skip_distance` | no breather while his target is further than this. `220` px |
| `open_switch_margin` | how much better a new opening must be. `60` |
| `open_zone_margin` | back to `0.25` of a quarter |

**See it in the game:** press **Z** in a match. On top of the zone map you get
the gold **ball range** circle, a gold cross where the ball will land, every
player's **job word** (gold = the ball is in his range, `sprint` = going
faster than a jog), a short **arrow for where he looks**, and a thin line to
the man he marks.

> `tools/movement_probe.gd` measures it per Tier and side. Before: players
> off the ball had it behind them **55-96%** of the time, and the Tier I and
> Tier IV back rows sprinted with the ball out of range **55-71%** of the time.
> After: **0-1%** and **0%**.

### The shape — why they were standing in pairs

**A zone is a centre of gravity. It is not a fence.** That sentence is the
whole of `pitch_zones.gd` and it is worth reading twice, because the zones
were built to stop twenty-two players hovering around the ball in one heap and
nothing else. Reaching a touchline, running into the box, chasing a ball three
quarters of the pitch away — all of that is supposed to happen.

There are **three bands**, from the inside out:

| Band | | |
|---|---|---|
| **home** | a quarter of the pitch | where a Tier stands with nothing to do, and the point it is drawn back toward |
| **roam** | `zone_roam`, **60%** of the pitch | where it moves about with **no pull at all**. The bands overlap enormously on purpose |
| **chasing** | the whole pitch | a player going for the ball is never pulled back by anything |

And a **fourth question that is not a band**: `zone_claim` — how much of the
pitch a Tier treats a loose ball as *its job*. That is a third of the pitch,
not sixty per cent, and running the two together is what made the midfield
heap: if every Tier claims everything inside its roam band, a ball on the
centre spot belongs to four Tiers at once and six players set off for it.

#### The three things that put them in pairs

**One: the lanes were mirrored.** Each lane is pushed a little forward or back
from its neighbours so a back three is a stagger rather than a column — and
the sign of that push used to **flip for the away side**. Work it through with
a wave of 0.22 and an inset of 0.34:

```
lane 0   home 0.34 + 0.22 = 0.56      away 0.66 - 0.22 = 0.44
lane 1   home 0.34 - 0.22 = 0.12      away 0.66 + 0.22 = 0.88
lane 2   home 0.34 + 0.22 = 0.56      away 0.66 - 0.22 = 0.44
```

On every even lane the flip walks the two sides *toward* each other until they
are about fifty pixels apart, while the odd lanes fly apart. That is the
screenshot: some pairs glued, the rest nowhere near anybody. Both sides now
read the **same** smooth wave at **different phases**, so the gap between them
never closes and is never the same twice either.

**Two: the defence snapped into pairs the instant a break started.** Ordinary
marking is zonal and offset — goal-side, off one shoulder, only
`mark_commitment` of the way there. The *recovery* rule that ran during a
break ignored all of that and sent every defender to a point dead level with
his man. It was the glued look at its very worst, at the one moment you are
certain to be watching. It now uses the same zonal rule, and the nearest
`recover_closers` go for the ball instead.

**Three: every rule can average back to nought.** Commit half way toward a man
who is a shoulder above you and you are half a shoulder above him; add a drift
that happens to be pointing down and you are level again. So there is a floor
under all of it — `mark_level_floor`, the smallest gap a marker may end up at
from his man's exact height. It costs nothing when the offsets did their job.

| Tuning row | |
|---|---|
| `zone_roam` | how much of the pitch a Tier moves in freely. `0.60`. **Not a fence** — raise it toward 1 and the shape loosens, drop it to 0.3 and you are back to four cages |
| `zone_claim` | how much of it a Tier treats a loose ball as its job. `0.34`. Raise it and more players converge on every ball |
| `zone_lane_stagger` | how far the away side's lanes sit against yours. `0.5` = exactly between them. `0` puts the pairs back |
| `zone_lane_depth` | how far each lane sits forward or back of its neighbours. `0.22` |
| `mark_level_floor` | the smallest gap from a man's exact height, as a share of `mark_shoulder`. `0.55`. **The last word against a parallel pair** |
| `leash_band_fraction` | how far a player may stray from their slot, as a fraction of their roam band. `0.45`. A flat pixel count was the cage nobody was blaming |

### Nobody is bobbing — the block follows the ball

**"Why are they moving up and down when they don't have the ball?"** Because
the only thing moving them was a sine wave. A player with no job walked a slow
circle round their slot, and twenty-two slow circles is a pitch of people
fidgeting — motion with no reason behind it, which is exactly what it looks
like from above.

A real side off the ball is not still and is not fidgeting either. It moves as
**one shape**, and it moves **because the ball moved**: the block slides across
when the ball goes wide and steps up when it goes forward. Every player is
walking somewhere for a reason and it is the same reason for all ten of them.

| Tuning row | |
|---|---|
| `block_follow` | how much of the way toward the ball the whole shape slides. `0.34`. **This is why a player off the ball is moving at all.** `0` holds the shape rigid and puts the aimless wandering back; past `0.6` the whole side chases the ball |
| `block_depth_share` | how much of that slide is forward and back rather than across. `0.45` — a line shifts sideways far more readily than it changes its depth |
| `drift_updown` | how much of a player's own sway is up and down. `0.22`. **The row that stopped the bobbing for good** |
| `drift_reach` / `drift_pace` | how far and how quickly they wander on top of all that |

### The shot, and the huddle that is not there any more

**"Don't clump everyone together when the Tier IV is about to shoot."** The
break had one rule for all ten: every player on the scoring side closed the
same fraction of the distance to the same goal mouth. Ten people converging on
one point is a heap however much you fan it out afterwards.

A real side breaking has two jobs going at once:

- **the runners** — the `surge_runners` nearest the goal attack the box, and
  they attack **different parts** of it: near post, far post, the penalty
  spot, the edge for the cut-back. Each has a station of its own and no two
  share one.
- **the rest** push up to support and hold their shape. They do not follow the
  ball into the area; they are the reason there is somebody to pass back to.

| Tuning row | |
|---|---|
| `surge_runners` | how many actually run into the box. `3` — a striker and two arriving. `10` puts the heap back |
| `surge_rest_share` | how much of the runners' advance everybody else makes. `0.30` |
| `recover_closers` | how many defenders go and close the ball down. `2`. The rest drop off and keep their spacing |
| `surge_advance` / `surge_centring` / `surge_spread` | how far forward, how far in, and how wide the runners' arc is |

> `tools/shape_check.gd` is the test, and it reports **per phase** — ordinary
> play, the break, and the restart — because one average over a whole match
> hides the two moments that were actually complained about. It also prints
> how many squares of the pitch anybody stood in and how close anyone came to
> each touchline and each goal.
>
> Measured over the same match: glued pairs went from **2.1–2.9 on average
> (10 at the worst moment)** to **0.5–1.4 (3–7)**; the width of the pitch used
> at any one moment from **72–76%** to **79–85%**; and somebody now gets
> within 20 pixels of both touchlines and 17 of a goal.
>
> `tools/formation_shot.gd` photographs the same thing from the stand. Use
> both: the numbers say whether it got better, the pictures say whether it
> looks right.

### The way into a match — black, then the ball rolls into the goal

Starting a match used to freeze the screen while the match loaded, flash the
pitch and its village, and only then show the team sheet. Now:

1. **The screen goes black at once** (`match_loader_fade_in`).
2. **The Alps come up**, with a goal on the right. A ball rolls along the
   bottom of the screen towards it while the match loads in the background.
3. **The ball goes in** only when the match is really ready (the team sheet
   is up behind it), and the picture fades away onto the team sheet.

The ball takes at least `match_loader_seconds`, and longer on a slow machine,
so it never scores before the match is there.

| Tuning row | |
|---|---|
| `match_loader` | `false` puts back the old way: the screen freezes while the match loads |
| `match_loader_fade_in` | seconds to go black. `0.12` |
| `match_loader_seconds` | the shortest roll into the goal. `1.6` |
| `match_loader_fade_out` | seconds for the picture to fade onto the team sheet. `0.35` |
| `match_loader_background` / `_goal` / `_ball` | the three pictures, in `assets/loading/` |
| `match_loader_ground` | how far down the ball rolls and the goal stands. `0.93` |
| `match_loader_ball_size` / `_goal_size` | sizes, as a share of the screen height |

**The art** was made in PixelLab with the Stammtisch places board as the style
image. Its layers are in `art_source/aseprite/match_loading.aseprite`
(rebuild it with `tools/make_loading_aseprite.py`) and the PixelLab originals
in `art_source/pixellab/match_loader/`. `tools/loading_shot.gd` records the
whole thing frame by frame.

### Before the whistle — the team sheet and START

A match no longer begins the instant the screen changes. There is a beat:

1. **The team sheet (the VS screen).** Since round AN it is two **beer menus
   in a beer tent**: your side on the left, theirs on the right, two steins
   clinking under a big **VS** between them. Each board has the crest and team
   name over it, and the three Stars written on the chalk like beers on a
   menu: the figure the Star plays as **on the pitch** (same look, standing in
   idle), its name, its tier and power where a price would be, and its two
   abilities.
2. **The gate.** The sheet lifts, the pitch is there with both teams already
   in position, the two crests stay at the top and a **START** button sits
   between them. Nothing runs until it is pressed: the pitch is frozen and the
   clock is at 00:00. Enter and space press it too.
3. **Then** the 3 · 2 · 1 · START countdown, and the match.

**Both sides field three Stars and swap them during the match**, so the sheet
names all three a side and, under each one, **what its abilities actually
do** — in words, out of Abilities.csv, not the ability's id. A side you have
never played deserves to be readable before the whistle and not only after
the second goal.

**The sheet waits for you.** It does not time out into the match: it fills its
bar, then holds with a **START** on it and the words *"Read them. Press START
when you are ready."* Reading six Stars' abilities takes longer than 2.6
seconds and always will. `team_sheet_hold` is `false` if you would rather it
ran on by itself.

**Every Star's abilities are printed once, and tagged.** There used to be a
hover panel over each portrait holding both abilities in full, *and* the same
two abilities printed underneath — the same sentence twice, one copy of it
hidden behind a mouse. The hover is gone. What is left is the printed pair,
with the work done on it instead:

```
   ATK   Teufel Mask — When attacking: +1 attack to itself, for this duel.
   DEF   Rhine Veil  — When defending: +1 defence to itself, for this duel.
```

**ATK is the warm colour and DEF is the cool one, and they are the same two
colours as the ATTACKING / DEFENDING strip above the row of cards.** That is
the whole point: the strip teaches them during the draft, the sheet uses them
before kick-off, and after one match you can read a team sheet without reading
a word of it. They live in the palette (`MenuSupport.COLOUR_ATTACK` /
`COLOUR_DEFEND`) rather than in either screen, so they cannot drift apart and
the Colour tab of Settings moves both at once — including for the colour-blind
palettes, where the pair is re-picked to stay distinct.

**Both sides always print, and a Star with nothing gets the word None.** A
blank where an ability should be reads as a bug; *None* reads as information,
and "this one has no tricks" is worth knowing before kick-off.

The two tags are rows of `Language.csv` — `atk_tag`, `def_tag` and
`ability_none` — so they translate. Keep a tag to three or four letters: it
sits in a fixed 30-pixel box so that every sentence beside it starts on the
same line down the column.

**The bar is honest when it can be.** It follows whichever is further along —
the real loading or the clock — so it never stalls on a fast machine and never
lies on a slow one.

**Everyone is already standing where they belong.** The teams are put on their
starting marks while the sheet is up rather than when START is pressed, so the
pitch you look at behind the gate is the pitch you get. They used to be placed
after the button and the whole formation visibly rearranged itself in front of
you, which made the sheet look like a loading screen that had lied.

**The crest comes from `Banner Art` in ClassInfo.csv**, which is where a
class's picture already lives, so a new class gets a crest here the moment it
gets one anywhere else. A class with no banner falls back to
`banner_<class>`, then to `team_crest_fallback`, and a side with no art at all
draws a lettered disc — nothing ever breaks over a missing crest. Put crest
files in `assets/team/`.

| Tuning row | |
|---|---|
| `team_sheet` | `false` skips all of it and a match opens straight into the countdown |
| `team_sheet_seconds` | how long the bar takes to fill. `2.6`. It is the bar, not the wait |
| `team_sheet_bar` | `false` out of the box: no bar on the sheet and START shows at once, because the loading screen's ball already did the waiting. `true` brings the bar back |
| `team_sheet_hold` | `true` and the sheet waits for START instead of running on when the bar is full. **`true` out of the box** |
| `team_sheet_stars` | how many Stars a side. `3`. The one actually playing is always first |
| `team_sheet_abilities` | `false` prints the Stars' names without what they do |
| `kickoff_needs_button` | `false` and the countdown starts by itself — for a demo or a stream |
| `team_crest_fallback` | the crest for a class with no Banner Art. `banner_normal_team` |

**The beer menus** (round AN). The board picture is blown up by a whole number
so its pixels stay sharp. The wooden top (crest, bunting) and bottom stay as
drawn; the rows of chalk in between repeat downward when a side's abilities
need more room, and if the board would grow past `vs_board_max` the ability
sentences shrink a size at a time instead. Layered file:
`art_source/aseprite/vs_screen.aseprite` (layout in
`art_source/aseprite/vs_screen_layers.csv`); PixelLab drafts and the other
options in `art_source/pixellab/vs_menu_draft/`.

| Tuning row | |
|---|---|
| `vs_menu_board` | the board picture. `assets/team/vs/vs_menu_board.png` |
| `vs_board_patch` | the wooden frame round the chalk, in the picture's own pixels: left top right bottom. Measure again if you redraw the board |
| `vs_board_width` | the widest a board may be, share of the screen. `0.44` |
| `vs_board_height` | how tall a board is, share of the screen. `0.62` |
| `vs_board_max` | the tallest it may grow for long abilities. `0.74` |
| `vs_ability_size_min` | the smallest the ability sentences shrink to. `9` |
| `vs_star_size` | how tall a Star's figure is, in pixels. `120` |
| `vs_versus` | the picture under VS. `assets/team/vs/vs_steins.png` |
| `vs_background` | the tent. `assets/team/vs/vs_tent.png` |
| `vs_background_dim` | how much darker the tent is. `0.55` |

### The line-ups on the grass

After START on the VS screen, both sides are introduced **standing on the
pitch** (round AN, Anthony). It is the real pitch, frozen, with everyone on
their own spot, standing in idle and facing the camera. The camera pushes in
and pans along **your side from right to left**, then along **theirs from
left to right**. The side not being shown is faded back, and a sign at the
bottom names whoever is in the middle of the screen: ★ for a Star, the name,
tier, power and defence. The keepers are included.

It uses the same figures and name plates as the match, so nobody can look
different here from how they look in play. The camera follows the best
straight line through the side, because the tilted pitch runs corner to
corner. The HUD and the keepers' save odds are hidden while it runs.

**It can always be skipped.** A click, space, enter or escape ends the whole
thing.

| Tuning row | |
|---|---|
| `line_up_parade` | `false` turns it off for good |
| `line_up_pan_seconds` | how long the pan along one side takes. `5` |
| `line_up_hold` | the pause at each end of a pan. `0.6` |
| `line_up_zoom` | how close, as a multiple of the whole-pitch shot. `2.2` |
| `line_up_fade_other` | how see-through the side not being shown is. `0.3` |
| `line_up_facing` | `south` = everyone faces the camera; any of the 8 directions; `ball` = they keep looking at the ball |
| `line_up_between_sides` | the pause between your side and theirs. `0.9` |

`tools/line_up_shot.gd` films it frame by frame for a GIF.

> If every row on one side reads **"Unit Name"**, that is not the parade — it
> is the `Name` column of that class's unit CSV, which still has the template
> placeholder in it. The parade is simply the first screen big enough to show
> you.

### The kick-off

A match opens with the camera in on two players standing over the ball in the
centre circle, a **3 · 2 · 1 · START**, and then the ball is genuinely loose —
both sides run at it and whoever arrives first comes away with it. It is a real
loose ball, not a scripted one: it can be reached, taken and tackled exactly
like a ball dropped in open play, which is why it is uncertain who gets it.

| Tuning row | |
|---|---|
| `kickoff_countdown` | `false` puts it back the old way — your Star simply starts holding the ball |
| `kickoff_count_seconds` | how long each of 3, 2, 1 is held. `0.7` |
| `kickoff_go_seconds` | how long START is held before they are let go. `0.55` |

**The clock does not run during the countdown.** The match is not marked live
until START, so the first whistle is at 00:00 and not at 00:52.

### ATTACKING or DEFENDING — and it stays on screen

Which way round the round is being played decides **which of the two numbers
on a card is the one that counts**: attacking reads a card's attack, defending
reads its defence. It is the single most important fact in the draft — and it
used to be said once, in a line of small text, on a screen that closed a
second later. From that moment you were choosing four cards with no way to
check.

Two things now, both loud:

1. **The call.** The moment the clash decides, the word lands across the
   middle of the pitch in its own colour for `side_call_seconds`.
2. **The banner.** And then it *stays* — a strip pinned above the row of
   cards for the whole draft, saying which tier you are choosing and which
   way round you are, in the same colour and the same words. Under it, in
   small letters, the reason it matters: *"their defence is what beats you —
   pick on ATTACK."*

It is hidden for the two Star phases, because swapping who is on the pitch is
a different kind of choice and is not answering anybody.

**The two colours are the ones the team sheet tags abilities with** — warm for
attack, cool for defence. Learn them here, read them there.

| Tuning row | |
|---|---|
| `side_call` | `false` drops the big word and keeps only the banner |
| `side_call_seconds` | how long the call is held. `1.3` |
| `side_banner_lift` | how far above the card row the strip sits, in pixels. `150` |

The words themselves are `attacking` and `defending` in `Language.csv`.

### The PLAY MAKER clash — calling a number

The clash used to be rock-paper-scissors. It is now a **number from one to
ten**: two rows of buttons with a coin between them, you call one, the coin
spins and lands on a number, and **whoever called closer chooses** — attack or
defend. There is a *random* button if you would rather not think about it.

Their call is always drawn from the numbers you did **not** pick, so the two can
never be the same and there is no draw to explain. If the two calls are the same
distance from the coin, it goes to **you**.

| Tuning row | |
|---|---|
| `use_coin_clash` | `false` brings back the rock-paper-scissors screen, which is still in the project and still works |
| `coin_faces` | how many numbers are on the coin. `10` |
| `coin_spin_seconds` | the whole spin, which slows as it goes. `1.4` |
| `enemy_attack_chance` | how often they choose to attack when they win the call. `0.5`. Shared with the old screen |
| `rps_reveal_seconds` / `rps_result_seconds` | the two pauses, also shared |
| `use_rps_minigame` | `false` skips the clash screen entirely and decides it behind the scenes. Outranks both of the above |

**Naming the number exactly is its own moment.** There are two ways to win the
call and they are not the same thing: being nearer is arithmetic, naming it is
worth leaning on. An exact call gets its own words and its own animation — the
coin swells and turns gold and the chip that named it pulses — and it is a
**Juice moment**, `coin_exact`, so a row in Juice.csv hangs the sound on it.

| Tuning row | |
|---|---|
| `coin_exact_words` | what it says when **you** name it. `CALLED IT!` |
| `coin_exact_them_words` | the same when they do |
| `coin_exact_seconds` | how long the celebration is held. `0.9` |

### The speed buttons, and AUTO

There are **two sets of speed buttons** — the strip in the top-left corner and
the pause menu behind Escape — and they obey exactly the same rule, because
the rule lives in `game_speed.gd` rather than in either screen. (It used to
live in the HUD, so the corner locked 4x and the pause menu handed it over,
which does not read as a half-finished feature: it reads as the lock being
decoration.)

**1x always works. 2x, 4x and 8x are shown greyed until unlocked, and pressing
a locked one says so** rather than doing nothing. A button you cannot press yet
is a thing to want; a button that is not there is a feature the player never
learns exists. They are deliberately not `disabled` in Godot's sense either —
a disabled button swallows the click and so cannot tell you why nothing
happened.

| Tuning row | |
|---|---|
| `game_speed_buttons` | `true` and 2x / 4x / 8x work |
| `game_speed_buttons_needs` | a `Requires` condition that must pass as well — e.g. `unlocked:Fast Forward`, handed out by a talent or an achievement |
| `game_speed_locked_words` | what a locked one says when pressed. Word it to match whatever you called the unlock |

**Holding the mouse button or the spacebar through a duel still hurries it
along whatever these say.** That is a different thing and it is always on.

**AUTO is in the corner, beside the speed buttons**, and also in the pause
menu. It was tried down beside the cards for one round; a button sitting in
the middle of the pitch for ninety minutes is something you look at every time
the ball goes past it, and it was reachable from Escape the whole time anyway.

### How a player is labelled — the nameplate

A player reads the same in a league match and in Adventure:

```
            ,---.
           ( o o )            <- the artwork
            `-^-'
      +--------------+
      | Silver-Rhine |        <- the name, first line INSIDE the window
      | Tier I   P: 2|        <- Tier left, Power right
      | [=======   ] |        <- Adventure only: the stamina bar
      +--------------+
```

**The name sits inside the same window as the Tier and the Power, on the line
above them.** It used to float over the player's head, and a head is exactly
where the player behind is standing — half the names on a busy pitch were
written across somebody's face. In one window there is one thing to read and
one thing that can be moved out of the way, and the window widens to fit
whichever of the three lines is longest.

A league player has no stamina — only the keeper does — so there is nothing to
draw a bar from and twenty-two of them would say the same thing anyway.

The name has the class taken off the end of it: *Songbound Shore Lorelei*
becomes *Songbound Shore*, because the class is on the end of every card in a
set and is already obvious from who is standing there. The full name is still on
the card, in the log and in the team builder.

| Tuning row | |
|---|---|
| `plate_names` | `false` hides every name in both modes. Tier and Power stay |
| `plate_name_size` | the name, the top line of the window. `13` |
| `plate_stat_size` | the Tier and Power under it. `11` |
| `plate_width_max` | the widest a plate may get, in pixels. `150` |
| `plate_name_width` | how wide a name may be, **as a multiple of the window under it**. `1.0` = never wider, which is what stops eleven names in a crowd writing across each other. Anything longer is cut with a … |
| `plate_gap` | pixels between the body and the first label. `5` |

> **The labels are placed from the drawn character, not from the frame.** A
> spritesheet frame is mostly transparent padding and every sheet has a
> different amount, so anything measured from the frame floats. Each texture is
> measured once, so a label hugs the body whatever the padding is — and it keeps
> working when you replace the art.

### ENEMY TEAM DATA — reading the other side

The ladder makes every legal team the same total power on purpose, so the
interesting question about an opponent is never *how strong are they* — it is
**what do they do**. That question now has an answer you can go and read, from
three places, all of them the same window:

| Where | The button |
|---|---|
| The team shelf, before you pick a side | **ENEMY TEAM DATA**, in the footer. Shows the side the next fixture puts in front of you |
| During a match | **TEAM**, on the HUD, any time |
| The team sheet | the three Stars a side, with their abilities, already on it |

It lists their **whole squad by tier**, in ladder order: every card, its power
and defence, and under it what each ability actually does — in plain English,
built out of Abilities.csv, so an ability you write today explains itself here
today and there is nothing to keep in step. The Stars they will field are
marked. A card whose Attack Ability names a row that is not in Abilities.csv
says so in orange, which is exactly the typo that is invisible in a match.

Escape closes it. It pauses nothing and changes nothing.

### `data/Keywords.csv` — every word the game understands

**The file to open when you want to know what you are allowed to write.**
Every effect, target, scope, condition, tag and juice moment the engine knows,
one per row, each marked `live` or `planned` — and **the place to ask for a new
one**.

| Column | |
|---|---|
| `Keyword` | the word itself, exactly as it goes in a spreadsheet cell |
| `Family` | which column it belongs in: `ability effect`, `ability target`, `ability scope`, `condition`, `effect word`, `adventure effect`, `item tag`, `juice moment` |
| `Status` | **`live`** = built. **`planned`** = designed, waiting to be built |
| `What It Does` | one clear sentence. **This sentence is the specification** — whoever builds the word works from your words, so write it the way you mean it |
| `Example` | a cell that uses it |
| `Notes` | yours |

**To ask for a word, add a row with `Status` = `planned`.** Nothing else is
needed. A card written against a planned effect **still loads** — it is not an
error and it is not a typo, it simply does nothing until the word exists, and
the Output panel says so once by name. So the cards can be written now and the
words caught up with later, which is the same bargain AbilityTriggers.csv
makes for triggers.

Planned out of the box, as examples of the shape: `negate_ability`,
`negate_power`, `swap_sides`, `change_priority`, `score_goal`.

> **The Workbench has a page for this.** *Keywords* in the left rail groups
> every word by family, marks the planned ones, and has two buttons: **+ Ask
> for a keyword**, which writes the row for you, and **Copy the planned list**,
> which hands you every planned word and its sentence as text you can paste
> straight into a message. That list is a finished request — every word in it
> came out of your own file.

### `data/MatchModes.csv` — the kinds of match

| Column | |
|---|---|
| `ID` | `season`, `friendly`, … |
| `Records Season` | `yes` and the result goes in the league table |
| `Timer` | match length in in-game minutes |
| `Cycles` / `Rounds` | the shape above |
| `Star Rotation` | `yes` and the STAR PLAYER SWITCH happens |
| `Opponent` | `team` = a fixture from Season.csv. `scratch` = a side assembled on the spot at roughly your level |
| `Scene` | which scene to open |
| `Rewards` / `Rewards On Win` | condition-language effects, paid out after |

### `data/AbilityTriggers.csv` — WHEN an ability goes off

An ability is five answers: **Trigger** (when), **Target** (who), **Effect**
(what), **Value** (how much) and **Scope** (how long). The trigger list used
to be six words buried in a script; it is a spreadsheet now, and it is also
**where you keep the plan**.

| Column | |
|---|---|
| `ID` | the word you write in the `Trigger` column of Abilities.csv |
| `Name` | what you call it |
| `Status` | **`live`** = the game fires it. **`planned`** = designed, not wired up yet |
| `Phase` | your own note of which batch it belongs to. Not read by the game |
| `Fires When` | one line |
| `What It Needs` | what has to exist before it can be built |

**A `planned` trigger is a legal thing to write.** The card loads, the row is
not an error, and the Output panel says once that it is waiting. When the
trigger goes live the card starts working with no edit. That is the point of
the file: you can write the cards now.

Live today:

```
on_duel_start   either way, when its duel begins
on_attack       this card is the attacker
on_defend       this card is the defender
on_win_duel     after it WINS its duel
on_lose_duel    after it LOSES its duel
passive         once at the start of every round, no condition at all
flip            the two cards turn face up
reveal          YOU press SHOW on it during the draft
```

> **Win and Lose were already built.** `on_win_duel` and `on_lose_duel` have
> been in the engine since the beginning — `BRAND_RALLY` and `BRAND_SCORCH`
> in Abilities.csv both use them. That is one phase you do not have to wait
> for.

#### SHOW — playing a card face up (`reveal`)

Every pick until now has been hidden and simultaneous: you choose, they
choose, the cards meet. **SHOW breaks that on purpose, in one direction.**

A card that has an ability written against `reveal` wears a **SHOW** button in
the draft. Pressing it chooses that card *and names it*:

1. the card is locked in, exactly as clicking it would,
2. **they answer a card they can see** — instead of picking at random in that
   tier they take their best answer, the strongest defence if you are
   attacking this round and the strongest attack if you are not,
3. and the card's `reveal` ability fires, there and then, in the draft.

So the ability is not free. It costs the one thing a hidden draft gives you,
which is that they have to guess — and a card worth showing has to be worth
more than the guess. That trade **is** the trigger.

**The button is only ever on a card that has something to show.** A card with
no `reveal` ability would be handing over a free look for nothing, so it does
not offer the option — which makes the button itself a piece of information:
a card wearing SHOW has a trick on it.

**If both sides show, the lower power resolves first.** That is the ordinary
ability-priority rule doing the work: a shown card is given a priority equal
to its own power, so two shown cards sort weakest-first with nothing special
added to the duel.

| Tuning row | |
|---|---|
| `draft_reveal_button` | `false` takes SHOW off every card, and reveal abilities never go off |
| `draft_reveal_words` | what the button says. `SHOW`. `PLAY IT OPEN` and `CALL IT` both fit |

Two worked examples are in Abilities.csv, and both are on cards in
`example_unit_csv_with_ability_columns.csv` so you can see the button in a
real match:

```
LORE_OPEN_HAND      reveal  self  add_power       2  round
BRAND_CALLED_SHOT   reveal  self  add_shot_power  3  round
```

`Open Hand` pays the card; `Called Shot` pays **the shot**, which is where
section 2 says a bonus belongs. Write your own the same way — any effect, any
scope. There is no opponent yet when a reveal fires, because nobody has
answered, so a `reveal` ability should target its own side.

> `tools/reveal_check.gd` is the test. It says whether the trigger is live,
> which cards carry one, whether the ability actually lands, and — run under
> `xvfb-run` — photographs one card that has a reveal ability beside one that
> does not.

#### The card goes ON THE TABLE

A reveal you cannot see is a rule, not a moment. So whatever has been played
face up sits in a strip **above the row you are choosing from**, theirs on the
left and yours on the right, each with its tier, its power, its defence and
what its abilities do in plain words:

```
  +--------------------------------------------------------------+
  |  THEY PLAYED IT FACE UP      |      YOU PLAYED IT FACE UP     |
  |  Hexflame · Tier IV · P:4 D:4|  Cinderworks · Tier II · P:1   |
  |  Attack — Called Shot. ...   |  Attack — Open Hand. ...       |
  +--------------------------------------------------------------+
        ( the four cards you are choosing from )
```

It shows one side, both sides, or — when nobody has revealed — it is not
there at all. It is cleared at the end of every round.

| Tuning row | |
|---|---|
| `reveal_strip` | `false` and a reveal is only a line in the announcement bar |
| `reveal_strip_height` | how tall it is. `120` — two abilities in plain words need about this much |
| `reveal_strip_inset` | how far in from each side of the window it stops. `220` |

#### And the other side can show one too — `data/EnemyPlay.csv`

**"Is there a simple solution to this without having to build a full AI?"**

Yes, and it is the one board games have used for forty years. A boss in a
board game has no AI; it has a **card with two or three lines on it** — *"if a
hero is adjacent, attack the weakest; otherwise move toward the nearest"* —
and you read the lines in order and do the first one that fits. It is
completely predictable if you study it, and that is the point: the player's
skill is learning to read it.

So the opposition is a spreadsheet. The rows are read **from the lowest
`Order` up, and the first one whose `When` is true is the one they use** —
everything below it is ignored for that tier.

| Column | |
|---|---|
| `Order` | read low to high. **First match wins**, so `always` belongs at the bottom |
| `Style` | blank = every opponent. A word here matches the `Play Style` column of Teams.csv — that is how the side at the top of the pyramid plays differently from the one you open against |
| `When` | `always`, `you_revealed`, `you_hid`, `attacking`, `defending`, `winning`, `losing`, `level`, `has_ability`, `tier:IV`, `round:3`, `flag:name`, `!flag:name` |
| `Pick` | `random`, `strongest`, `weakest`, `counter`, `ability_first`, `no_ability` |
| `Reveal` | `never`, `always`, `if_ability` (only when the card has a reveal ability to fire), `match` (only if you showed one first) |
| `Do` | an effect run when the rule fires, in the same words as everywhere else. **`brew:fire` pours a brew on the card they just took** |

**They reveal as they pick**, while the tier is still open — the whole value
of knowing is that there is still a choice left to make with it.

The last row of the file out of the box is `always / random / never`, which is
exactly what the opposition did before the file existed. **Delete every other
row and the game plays as it used to.**

> `tools/enemy_play_check.gd` puts the same four cards in front of the rules
> in every situation the columns can describe and prints which rule answered
> and what it chose. **A rule that never appears in that list is a rule that
> can never happen** — either its `When` is impossible or a row above it is
> eating the same situations.

#### The flip

**The whole window turns over, not the two cards inside it.** The duel arrives
face down as one card back: the tier it is — `TIER III` — with a crest to
either side, yours and theirs. Then the window is squashed to no width, its
face is swapped at the moment it has none, and it comes back as the duel with
both players on it. Only then are the two compared, one after the other.

That happens **for every tier in a combat**, so a combat reads as four cards
being turned over rather than as a list appearing.

It was two little cards flipping inside a window that was already open, which
is a smaller gesture than the moment deserves: the tier and the two crests are
what you are waiting to see, and a card back that says them is worth turning
over.

It is the moment the duel begins: before it, neither side knows what the other
has. And it is a hook — `flip` fires **before** `on_duel_start`, so a flip
ability can change what the duel starts with.

| Tuning row | |
|---|---|
| `duel_flip` | `false` and the duel is simply there, as before |
| `duel_flip_seconds` | the whole turn, both halves. `0.42` |

The crest on each side of the back is the same `Banner Art` the team sheet
uses, so a class that has a crest anywhere has one here.

### `data/ShotOdds.csv` — will it go in?

The keeper's stamina is a wall, and **the wall gets weaker as you knock it
down**. How much weaker is a curve you draw, and **the number it produces is
printed on the screen before the shot is taken.**

#### What was wrong

The keeper had two numbers and nothing between them:

```
stamina left    a flat 5% chance the shot sneaks in
stamina at 0    a 90% chance
```

So a keeper on 1 stamina was exactly as hard to beat as a keeper on 30 — the
wall did not weaken, it simply fell over at the end. And an empty net still
saved one shot in ten, which reads as the game cheating. None of it was ever
shown, so you watched a bar go down with no idea what it was buying you.

#### The curve

| Column | |
|---|---|
| `Stamina Left` | how much of the keeper's stamina is left, 0 to 100 |
| `Chance` | the % chance of scoring at that stamina, before shot power |
| `Per Power` | how many points each point of shot power adds, at that stamina |
| `Max` | the most this row ever allows, whatever the shot power. Blank = no cap. Since 8 Oct (Anthony) a full keeper is capped at **10%**; it slopes between rows like the others |

Between two rows **both numbers are interpolated**, so six rows draw a smooth
curve rather than six steps. Out of the box, on a keeper with 25 stamina:

```
stamina      P0     P1     P2     P3     P4     P5     P8
  25/25       8%    10%    12%    14%    16%    18%    24%
  15/25      24%    28%    32%    35%    39%    42%    53%
  10/25      39%    43%    48%    52%    56%    61%    74%
   3/25      69%    73%    78%    82%    86%    90%   100%
   0/25     100%   100%   100%   100%   100%   100%   100%
```

**The 0 row is the one the file exists for.** It says 100, so an empty keeper
is a certain goal — not 90, not 99. That is a row, not a rule, so you can
change your mind about it in a spreadsheet.

`Per Power` is highest in the middle of the curve on purpose: a big shot is
worth most against a keeper who is already wobbling.

#### The number you are shown is the number that is rolled

This is the part that matters. The shot is rolled against the stamina the
keeper had **when you were shown the number**, and the stamina is taken off
afterwards. A shot that empties a keeper does not get the empty keeper's
odds — the *next* one does.

Doing it the other way round would be a lie: the cut-away would say 52% and
the game would quietly roll 61%, and no player could ever tell.

#### Where it is shown

**In the shootout cut-away**, as a third readout beside shot power and keeper
stamina — one number, because the shot power is known, and it is the number
about to be rolled. At 0 stamina it reads **100%** and, underneath, *"the
goal is open"*.

**On the pitch**, under each keeper's stamina bar, as a band:

```
8 – 18%
```

because on the pitch nobody knows yet how hard the shot will be. The low end
is a shot of no power and the high end is a shot of `shot_power_shown`. The
two collapse to one number when they agree — which is exactly what happens at
0 stamina, so an empty keeper reads a flat, unambiguous **100%**.

Cool when the keeper is winning, warm when he is losing, on the same two
colours as ATTACKING and DEFENDING — because a low number and a high number
here mean precisely those two things.

| Tuning row | |
|---|---|
| `shot_odds` | `false` goes back to the two flat numbers. They are still in the code and still work |
| `shot_power_shown` | the top end of the band on the pitch. `5` |
| `keeper_chance_on_pitch` | `false` leaves only the bar |
| `keeper_chance_size` | how big the keeper's number is, in points. `12` |

#### The scale — the mistake worth not repeating

The first version of this curve was tuned against a shot power of 0 to 8.
**Shot powers in this game are 10 to 22.** Every number in the `Per Power`
column was doing about ten times the work it looked like it was doing, and
matches came out 3–3 and 0–4.

That was a guess where a measurement belonged, so there is now a tool for it:

```
godot --headless --script res://tools/scoring_balance.gd
```

It plays the *shots* rather than the matches — the real powers, the real
keeper stamina, the real nine rounds, the real curve, two thousand times —
and prints goals per side, the spread, the share of shots that go in, and how
often somebody reaches six in a one-sided game. **Run it after touching any
number in this file.** As it ships:

```
1.46 goals a side on average      32% of shots go in
0 goals 12%  ·  1 goal 47%  ·  2 goals 32%  ·  3 goals 7%  ·  4+ 2%
a one-sided game: the stronger side averages 2.7 and reaches six 0.2% of the time
```

and three real soaked matches went 2–3, 1–2 and 0–5.

#### `shot_stamina_bite` — the second dial

A shot used to take its **whole** power off the keeper's stamina. With shots
worth 10 to 22 against a keeper who has 25 to 30, that emptied him on the
*second* shot of the match and made the third a certainty — so the wall the
stamina bar exists to describe never actually eroded; he was fine, and then
he was gone.

A shot now takes a **fraction** of its power. At `0.55` a keeper survives
about three shots, which is a whole cycle, and the bar has time to tell its
story. After `Chance`, this is the biggest dial on the scoreline.

### `data/Celebration.csv` — the goal celebration

A goal used to be the word GOAL and then a restart. It is the moment the whole
game is *for*, and it passed in about a second and a half.

**Nothing about a celebration is a rule.** It is a sequence of moments, and
which moments and how long each lasts is a thing you will change fifty times.
So the code knows how to do seven things and **the spreadsheet decides which
of them happen, in what order, and for how long.**

#### One row is one beat

The rows run **top to bottom, in the order you wrote them**. Move a row up and
it happens earlier. Delete every row and a goal is exactly what it was before
this existed.

| Column | |
|---|---|
| `Step` | yours. A name so you can find the row again |
| `Who` | `you` / `them` / `both` — whose goal this beat plays for |
| `Do` | what happens. The seven are below |
| `Seconds` | **how long before the next row starts** |
| `Text` | the words, for `say` and `window` |
| `Art` | an image file, for `window` |
| `Animation` | a row of Animations.csv, for `window` |
| `Sound` | a row of Audio.csv, or a file in `assets/audio/` |
| `Notes` | yours |

#### The seven things it can do

| `Do` | |
|---|---|
| `slide` | the scorer drops and skids along the grass, away from the goal he has just scored in and out toward the nearer touchline |
| `swarm` | everyone on his side runs in and rings him |
| `confetti` | starts the confetti. It keeps falling until the whole celebration ends, whatever comes after this row |
| `window` | opens the celebration window with your `Text` / `Art` / `Animation` in it |
| `say` | the big word across the middle of the pitch |
| `sound` | plays a cue. Usually with `Seconds` 0 |
| `wait` | nothing but time |

#### Seconds is a wait, not a length

This is the one thing worth reading twice. **`Seconds` is how long the game
waits before running the next row** — not how long the effect lasts.

So `confetti` with `Seconds` 0 starts the confetti and immediately moves on,
and the paper carries on falling under everything that follows. A `sound` with
`Seconds` 0 starts playing and the list carries on over the top of it. A
`wait` row is the only one whose whole job is the number.

Two exceptions, and both are things you are meant to *look* at: a `window`
holds for its Seconds, and a `say` clears itself when its Seconds are up.
**Two rows of the same kind in a row replace each other without a gap** — so
consecutive `window` rows are a slideshow inside one panel rather than a panel
opening and shutting twice, and two `say` rows swap with no blank frame
between them.

#### What goes in the window

One of two things, and `Art` wins if you fill in both, because an image is the
more deliberate of the two — you went and drew it.

- **an Animation** — a row of `Animations.csv`, played on **the scorer's own
  spritesheet**. `win` is one you have already drawn. This is the default and
  it already works for every card in the game.
- **an Image** — whatever you name in `Art`, shown whole. This is how you give
  one Star his own celebration: name a file, and that card's goals look
  different from everybody else's.

A row asking for an animation the scorer has no art for still opens the window
with the caption and an empty stage. **A celebration is never allowed to be
the thing that stops a match.**

#### Words you can put in Text

`{scorer}` · `{team}` · `{class}` · `{tier}` · `{score}` (always your goals
first). A placeholder nothing fills in is left on screen exactly as written,
so a mistyped one shows up instead of silently disappearing —
`celebration_check.gd` names it as well.

#### The numbers that are not per-beat

How far the slide goes, how wide the ring is, how much paper there is: those
are shape rather than sequence, so they are rows of `Tuning.csv`.

| Tuning row | |
|---|---|
| `goal_celebration` | `false` is the old behaviour: GOAL for `verdict_seconds`, then the restart |
| `celebration_slide_distance` | how far the skid carries him. `180` |
| `celebration_swarm_radius` | how close the ring stands. `110`. Under about 70 they are drawn on top of each other; over about 200 it stops reading as a huddle |
| `celebration_confetti_pieces` | how many. `260`. They are drawn in **one call**, so this number is cheap — 500 costs about the same as 140. `0` turns the confetti off without touching the spreadsheet |
| `celebration_confetti_size` | how thick a piece is. `6`. Its length varies per piece |
| `celebration_confetti_speed` | how fast it falls. `220` |
| `celebration_confetti_colours` | the palette, hex separated by spaces. **Put your two club colours in here** |
| `celebration_hide_names` | during a celebration every name plate comes off except the scorer's. `true` |
| `celebration_skippable` | click or space cuts it short. `true` |

#### Three things it is careful about

**The name tags come off.** Nine plates inside a hundred-pixel huddle is a
black smear with letters in it. One name in the middle of a ring of bodies is
a photograph. They all come back at the end.

**It can always be cut short**, and cutting it short still stands everybody
up, still puts the plates back and still hands the ball to the keeper.

**The confetti is drawn in one call.** Two hundred and sixty `draw_rect()`
calls took the game from 22 frames a second to 2 — at the exact moment it is
supposed to feel best. One `draw_multiline_colors()` does the same picture.
This is why `celebration_confetti_size` is one number for every piece: a
single call has a single width.

> **How long is too long?** `tools/celebration_check.gd` adds it up for you and
> says so past twelve seconds. Out of the box a goal of yours costs 7.3
> seconds of celebration and then the 2 seconds of `goal_pause_seconds`
> walking back; theirs costs 1.2 and the same 2.

### `data/OutOfBounds.csv` — how a round begins

A round used to open by asking you to call a number between one and ten, and
whoever called closer chose attack or defend. It worked, and it was a
fairground game bolted onto a football match: you were guessing a coin, not
playing football.

It opens with football now.

```
   1  a HIDDEN ROLL decides who gave the ball away
   2  he puts it over the nearest touchline
   3  an ANIMATION WINDOW: who it was, and what he did
   4  the nearest opponent WALKS OVER and stands OUTSIDE the line
   5  then the PLAY MAKER, and both sides pick their tiers
   6  THE THROWER CHOOSES attack or defend
   7  the throw goes to a TEAM-MATE, who starts the relay to Tier I
```

**The choice is the same choice.** What changed is that you earn it by not
being the one who put the ball out, rather than by guessing a number.

#### It is the same shape as Celebration.csv

On purpose — you have already learned this file. One row is one beat, read
top to bottom; `Seconds` is **how long before the next row starts**; delete
every row and a round opens instantly, which is what it did before any of
this existed.

| `Do` | |
|---|---|
| `roll` | decides, out of sight, who gave the ball away |
| `kick_out` | he strikes it over the nearest touchline |
| `walk_up` | the nearest opponent walks to the spot and stands outside the line |
| `window` | the animation window: a caption and a picture |
| `say` | the big word across the middle of the pitch |
| `sound` | plays a cue. Usually with `Seconds` 0 |
| `wait` | nothing but time |

`{loser}` `{thrower}` `{side}` `{tier}` all work in `Text`.

**Write `roll` first.** The beats that follow are about the player it picks,
and the game will do the roll first anyway rather than kicking a ball nobody
gave away — but a list with an invisible step in it is a list that gets
edited wrongly. `tools/out_of_bounds_check.gd` says so if you do not.

#### The animation window is a template

> *"An animation window, with a template so it runs before any art exists."*

That is the whole reason the `window` row is not simply a place to put a
video. It shows, in order of preference:

1. **an image** — whatever you name in `Art`, shown whole;
2. **an animation** — a row of Animations.csv, played on **that player's own
   spritesheet**, so `lose` works today with art you already have;
3. **nothing** — the caption alone. Which is not a failure: a window with a
   caption is still a beat, and the match keeps going.

It is `AnimWindow`, and the goal celebration uses the same one — two copies
of a window is two windows that drift apart.

#### How long it takes, and why that matters more here

**This sequence happens nine times a match.** A second added to it is nine
seconds of match. The checker prints the total and the multiplication:

```
godot --headless --script res://tools/out_of_bounds_check.gd
```

As it ships: **4.6 seconds**, so 41 seconds of every match.

| Tuning row | |
|---|---|
| `out_of_bounds` | `false` brings back the 1–10 coin, which is still in the project and still works |
| `out_of_bounds_player_chance` | how often it is **your** side that gives it away. `0.5` is even. Lower it and you get the ball back more often — the dial to reach for if the game feels unfair before you touch the cards |
| `throw_in_inset` | how far outside the line the thrower stands, in pixels |
| `throw_in_screen_margin` | and how close to the edge of the **picture** he may get. He is pushed out by the inset and then clamped back to here, because the camera never shows past the grass — 26 pixels outside the line turned out to be 18 pixels off the top of the screen. Visible and slightly wrong beats correct and invisible |
| `throw_in_read_seconds` | how long **their** decision is held on screen. It is shown even when the choice is not yours, because watching the opposition decide is information |
| `throw_in_settle_seconds` | a breath after the ball reaches the team-mate |

#### The throw goes to a team-mate

Not to whoever is duelling first. The thrower picks out the **nearest**
team-mate on the pitch — a throw-in is a short ball — and the ordinary relay
carries it from him to the Tier I attacker. That is what makes the throw-in a
restart rather than a menu that hands the ball over.

### Combat abilities — round Y, phase C1

**The plan for making every card's ability work is `guides/COMBAT_PHASES.md`**
— the timing chart of a round, the zones, the audit and the phases C1–C8.
What C1 added to this file:

| | |
|---|---|
| **`If` column** | conditions that must all be true: `defending`, `attacking`, `won`, `lost`, `last_ally_won`, `last_ally_lost`, `enemy_element:air`, `enemy_not_element:air`, `own_goalie_lower`, `enemy_below_base`, `in_exhaust`, `in_field`, `in_combat`, `has_tag:swan`. `!` in front means NOT; semicolons join |
| **new targets** | `next_ally`, `next_ally:fire`, `next_ally:water+II`, `next_ally*2:unkengeister`, `next_enemy`, `next_self` — these **wait** and land when that card next duels. `ally:water+I` is your card in that tier *this* round |
| **new moments** | `match_start`, `round_end`, `end_of_cycle`, `while_in_exhaust`, `after_duel`, `on_shot`, `goalie_save`, `on_goal`, `on_concede`, and your `contemplation` / `rejuvenation` (entering / leaving the exhaust zone) are live |
| **`Max`** | also `1/cycle` and `2/cycle` |
| **one side per duel** | a card attacking uses its **Attack** ability, defending its **Defend** ability; outside a duel, the side it played last. `ability_uses_role_side` in Tuning.csv |
| **several rows in one cell** | `C_Fritz_A1;C_Fritz_A2` — a sentence with two halves |

**Your cards' own abilities** are made from their text, not written by hand:

```
python3 tools/ability_audit.py     reads all 276 texts -> data/AbilityAudit.csv
                                   and the open questions -> data/AbilityRulings.csv
python3 tools/ability_rows.py      every reading the engine can run -> data/CardAbilities.csv,
                                   and its ID onto the card
godot --headless --script res://tools/ability_coverage.gd    how many work
godot --headless --script res://tools/ability_check.gd       and that each one fires right
```

**33 of 228 class abilities work in a match after C1**, up from 1. Change a
card's text and run the first two again.

### Combat abilities — round Z, phase C2: counters, Ore, tokens, swans

**103 of 228 class abilities work in a match now** (45%). Your rulings are in
and they changed the cards themselves: **"Exile" is the exhaust zone** (every
text that said exile says exhaust), Nils's intoxication is "+5% foul chance for
the match (once per game)", Konstantin's foul is "by 5%", Lennart gives "-1
priority", and Tobias's mine is "(Max 1)".

| new in Abilities.csv | what it does |
|---|---|
| **`Cost` column** | `ore:3` - pay 3 Ore from your side's pool first. Not enough Ore and the ability **does not happen** (not counted, not spent against its Max) |
| `add_counter:burn` | Value counters of that kind on the target, for the whole match, whatever zone it is in. `add_counter:power` with **-1** is a **power counter**: the card is 1 weaker in every duel after |
| `remove_counter` | takes Value counters off (`remove_counter:burn` for one kind) |
| `gain_ore` | Value Ore into **your side's pool** (ruling R12: one pool per side) |
| `create_token:rose` | a **Rose Unit token** takes a card's place: same tier, same power, no text. The card waits in the exhaust - where its *While in exhaust* side works - and comes back at full time. Target `self` (after its round) or `replace:water+I` |
| `make_swan` | the target is a **Swan** for the match |
| target `side` | your side, not a card - `gain_ore`, Belphegor's victory counters |
| target `next_tier_ally:fire` | **the very next card you play** (ruling R03). If it is not fire, the effect is lost. (`next_ally:fire` waits for the next FIRE card instead) |
| If words | `has_counter`, `has_counter:burn`, `enemy_has_counter`, `has_token`, `tokens_at_least:4`, `is_swan`, `is_token`, `ore_this_round`, `ore_at_least:3`, `element:water`, `exhausted_this_round:2:water` |
| `Max` | also `1/round`, and `/side` to share the count across the side: `2/cycle/side` |
| new moments | `on_counter` (it received a counter), `after_combat` (once a round after the Tier IV duel, every card in any zone) |

**What a sentence turns into.** "While in exhaust: deal 1 damage to the enemy
goalie *at the end of a cycle*" is **once**, at the end of the cycle, if it is
in the exhaust (`end_of_cycle` + `in_exhaust`) - not at every duel. "Give this
unit +1 power during combat. *If this wins:* give this unit -1 power counter"
is two rows with two moments (`on_attack`, then `on_win_duel`).

**The Emblems' Basic sides play** (five of them). See section 7f: the new
**Basic Ability** column.

**On the pitch you can now see:**

- **The match tracker**, top left: each side's Ore, tokens and victory
  counters, and **every "next" effect still waiting** - "2 x next swan ally: 1
  off their keeper" (ruling F3). `match_tracker_on` / `match_tracker_top`.
- **A strip on the draft card**: `burn 1  power -1  SWAN` - what it carries
  this match.
- **The duel window**: `3 (+1)` when the number it fights with is not the
  number printed on it, and "priority 2" when its priority is not its power
  (ruling F4).

### Combat abilities — round AB, phase C4: bending the duel

**156 of 228 class abilities work in a match now** (68%).

| new in Abilities.csv | what it does |
|---|---|
| `switch_to_defender` | the abilities go off, **then** the card defends (with its Defend side) and the other card attacks; the winner attacks next as always |
| `always_defending` | every "If Defending" is true for it, all match (Sallos) |
| `swap_power` | it and the target swap **printed** power for the duel. Target `token`: it takes the power of a token you own (Ignaz) |
| `set_power_from_token` | the target fights with the power of a token you own - you pick which when you have several (Sven) |
| `use_enemy_power` | it fights with the power of the enemy it duels (Nicole) |
| `force_ability:attack` / `:defend` / `:other` | the target must use that side this duel |
| `negate_ability` | the side the target is using does nothing more this duel; buffs it gave itself are taken back |
| `negate_buff` | the target loses its power buffs this duel |
| `change_priority` / `give_priority` | +/- its place in the order abilities resolve / it resolves first |
| `uncounterable` | it cannot be negated or forced this duel |
| `power_from_count:victory` | its power IS that number this duel (also `enemy_exhaust_II`, `field_objects`) |
| `remove_condition` | its If is ignored this duel |

**The stack re-sorts as it goes**, so a priority change that lands before a
card resolves really moves it. **From the exhaust**, "give a Tier IV water
unit +1" now waits for that card - before, it ran out at the Tier I duel.

**Card texts changed by your answers:** every "attack power" now says **"base
power"** (Q001); Sven: "Change the enemy's base power to the power of a token
you own during combat" (Q002); Kerstin: "...by 50% this turn (once per round)"
(Q030).

### Combat abilities — round AC, phase C5: the zones in action

**168 of 228 class abilities work in a match now** (74%).

**The Reveal is asked AFTER you pick** (your Q043 and Q044). You pick a card,
hidden, like every pick. If it has a Reveal (its own, or an Emblem's - Zepar's
Swan) a window asks **REVEAL IT? / KEEP IT HIDDEN**. They pick blind. Then
both reveals are shown and go off together, the lower power first (the
attacker on a tie). The REVEAL on a card is only a tag now: it tells you the
card has one. `reveal_after_pick` false puts the old SHOW button back.
AUTO reveals (`auto_reveal`); tell it to ask you in the AUTO menu.

**The exhaust lights up** (ruling R17). Before a duel, a card in your exhaust
that says "While in Exhaust: Swap this Unit with another Tier I" lights up the
**exhaust zone panel** (left of the screen) and you are asked: swap it in, or
not. It fights the duel; the card it replaced goes to the exhaust. Once per
cycle. Only asked when there is such a card (`exhaust_swaps`,
`auto_exhaust_swap`, `ai_exhaust_swap`).

| new in Abilities.csv | what it does |
|---|---|
| trigger `exhaust_swap` | the moment a card swaps in from the exhaust, just before its duel |
| `swap_in_tier` | the marker on an `exhaust_swap` row: this card CAN swap in. Its Max (`1/cycle`) is what limits the swap. Every other row on that side with the same trigger is what it does once it is in (Ralf +1, Peter -1 to the enemy or 1 off their keeper) |
| `send_to_exhaust` | the target goes to the exhaust now |
| `swap_from_exhaust` | after the target's next duel it goes to the exhaust and a card of its tier comes back (Lothar's token) |
| `exhaust_other_return` | another of your cards of its tier still on the field goes to the exhaust, and this one comes back to be played again (Jan, Silke) - you pick which if there are two |
| `reveal_another` | the next card you pick this round is revealed too (Ingrid) |
| `reveal_from_exhaust` | a card from your exhaust is revealed - a fire one if you have one (Flauros) |
| `double_attack` | the target fights its next duel with its PRINTED power doubled (max 5), buffs after (Q051) |
| If words | `swapped_was:air` (what it swapped with), `revealed_was:fire` (what it revealed) |

Jakob ("Reveal: if this unit is a swan, send it to the exhaust and create a
Swan unit token with this unit's power") works too: the Swan token plays his
duel in his place.

### Combat abilities — round AD, phase C6: the class engines

**All 228 class abilities work in a match now** (100%). What is left is the
Emblems' Basic sides (C7) and the Stars' Ultimates (C8).

**Who touched the ball (Unkengeister).** Every unit that had the ball in open
play since the last PLAY MAKER (ruling R13) counts as having touched it - its
draft card says **TOUCHED**, so you can pick it on purpose. "Apply cold touch
on the ball" turns the ball **icy blue** until the next PLAY MAKER and counts
for Glasya-Labolas.

**Gravestones (Unkengeister).** A grey stone appears where the unit stands and
stays for the match (Q058). They count for Caim and for "objects on the
field". `gravestone_max`.

**Mines (Bergmännlein) - `data/Mines.csv`.** Four mines per side along its own
touchline, one per quarter (your Q091; yours along the bottom, theirs along
the top). A side gets them only if it has an earth unit (`mines_need_earth`).
An earth unit that comes within `mine_reach` of one of its mines during
waiting play is **MINING** (its card says so, and "If another unit is
mining" is true). At every PLAY MAKER each mine that was worked gives +1 Ore
(`mine_ore_per_round`, your Q055). Earth units with nothing to do drift to
their mines (`mine_pull`). Tobias: every unit mining gives +1 Ore.

| Mines.csv | |
|---|---|
| `Mine` | a name for you |
| `Side` | `you`, `them` or `both` |
| `Across` | 0 = your goal line, 1 = theirs |
| `Down` | 0 = the top touchline, 1 = the bottom one |

**Fusing (Feuergeister) - the bench.** "From outside of the game" is your
**bench**: up to `bench_size` (3) cards of your class that are not in the
team. If one of your cards can fuse you choose them at the first PLAY MAKER
(ruling R08); the AI takes its strongest. "This unit fuses itself with a Tier
III fire unit": a matching bench card joins it for the match - it keeps its
name, fights with the **higher** printed power (Q056), carries both cards'
abilities, and its card says **FUSED**.

**The void (Marie, Susanne, Sophie).** "Swap this unit with another of same
tier from the void": it leaves its duel for one of your cards of that tier
not played yet this cycle (ruling R07); that card fights the duel. Nicole
does the same from the exhaust (same power and tier).

| new in Abilities.csv | what it does |
|---|---|
| `cold_touch` (target `ball`) | a cold touch on the ball |
| `gravestone` (target `field`) | a gravestone where it stands |
| `mine` | every unit of yours that is mining gives +Value Ore |
| `weapon` | a temporary weapon: +Value power for that combat (Belial) |
| `fuse:fire+iii` | a card of that kind from your bench fuses with it |
| `fused` | "Can be fused." - a word, does nothing itself |
| `swap_from_void` | swap out for a card of its tier not played yet |
| If words | `touched_ball`, `touched_before_playmaker` (the same thing, R13), `mining`, `fused` |

**The tracker** shows Graves, Mining, Cold and Bench counts.

### Round AI: the title screen, sound, and the testing tools

- **The title screen:** new wallpaper and hero (PixelLab), and the
  Oktoberfest menu tune and button sounds. See section 16b.
- **Testing:**
  - 1,000 simulated matches go to `data/combat_telemetry.json`;
  - the analyst writes `guides/BALANCE_ANALYSIS.md`;
  - my review is in `guides/BALANCE_REVIEW.md`;
  - the GUT unit tests live in `tests/unit/`.
  See section 16c.
- **The one mechanical flaw found:** a card that switches to defender wins
  every tie. The new dial `switch_loses_ties` is off; Q131 is yours.

### Round AH: the recruitment board (P3), the Pub (P4), the art phases, Unkengeister

- **P3, the recruitment board** in the Club House — see section 6b,
  *The recruitment board*.
- **P4:** the Pub no longer lists the Rivals' cards (`pub_hidden_classes`).
- **P5, the art**, is now five phases A1–A5 — see section 8b2. **A1 is
  done:** the pitch, the title wallpaper and the base yard.
- **The pitch is two steps.** PixelLab draws only the grass
  (`art_source/pixellab/11_pitch_grass.png`); `python3 tools/make_pitch.py`
  rules the lines on the player zones (round AN: see section 8b), adds the
  goals, and writes `assets/field/soccerfield.png`.
  Colours and sizes are at the top of that script. The old
  `soccerfield.jpg` (a watermarked stock photo) is no longer used — a `.png`
  of the same name wins — and can be deleted.
- **Your Q124, Unkengeister:** none of its nine Tier IV cards changes combat
  power (exhaust, cold touch, gravestone and force abilities), while the
  other classes' Tier IV cards give +1 / −1. A new dial,
  **`tier_power_<class>_<tier>`** — every card of that class in that tier is
  that much stronger in combat — shipped as `tier_power_unkengeister_IV` 1.
  16 matches each:

| `tier_power_unkengeister_IV` | won / drawn / lost | goals | Tier IV duels won |
|---|---|---|---|
| 0 | 0 / 3 / 13 | 9–30 | 27% |
| **1 (shipped)** | **6 / 5 / 5** | **17–15** | **53%** |

The class name in the key is in small letters with no spaces or hyphens:
`tier_power_rauhnachtfeuergeister_IV`, `tier_power_bergmännlein_I`.

### Round AG: the pinned phases, free kicks (P2) and balance (P1)

Combat is complete, so the pinned list became five phases — **P1** mass
testing and balance, **P2** free kicks, **P3** the recruitment board, **P4**
hiding the Rivals' cards, **P5** art pass 2 (no PixelLab until you say so).
They are in `guides/PHASES.md`.

**P2, free kicks:** `data/FreeKicks.csv` — see section 7d, *What a foul
is worth*.

**Your round AF answers:**

| question | what changed |
|---|---|
| Q112 b | Vassago's Ultimate: with two or more enemy abilities to copy, a window asks you which (AUTO menu: *vassago*) |
| Q113 b | Glasya-Labolas possesses more: mines, ore counters, one touch on the ball, Caim's gravestones — once each per PLAY MAKER (`glasya_objects`) |
| Q115 a | `counter_power_burn` **1** |
| Q116 a | `haures_rock_shift` **0** |
| Q118 | the balance dials below |

**P1, the balance dials (Q118 — "try to balance based on what we have"):**

| Tuning.csv | what it does | as shipped |
|---|---|---|
| `count_power_floor` | a card whose power is "equal to" a count (Buer, Vassago, Glasya-Labolas) never fights below its printed power | **1** |
| `star_power_tier_<tier>` | a Star in that tier is this much stronger in every combat (`star_power_tier_IV` …) | 0 |
| `counter_power_<kind>` | each counter of that kind on a card is worth this in combat (round AF) | burn 1 |

Measured, 8 Rauhnacht matches each:

| dials | won / drawn / lost | goals | Tier IV duels won |
|---|---|---|---|
| neither | 1 / 2 / 5 | 5–11 | 38% |
| `star_power_tier_IV` 1 | 3 / 2 / 3 | 6–9 | 39% |
| **`count_power_floor` 1** | **4 / 2 / 2** | **7–6** | **54%** |
| both | 1 / 5 / 2 | 6–7 | 61% |

Then the two that mattered, **16 matches each**:

| `count_power_floor` | won / drawn / lost | goals | Tier IV duels won |
|---|---|---|---|
| 0 | 0 / 4 / 12 | 6–23 | 30% |
| **1 (shipped)** | **8 / 2 / 6** | **19–16** | **54%** |

**Eight matches is not enough to trust a small difference** — the same
settings gave Rauhnacht 4 wins in one run of 8 and 0 in a run of 5. Use 16 or
more before you change a card because of a number.

**`tools/balance_report.py`** now also counts **duels won per tier** and
**free kicks per range**, so a class that is losing in one tier shows up in
the first report.

### Round AF, phase C8: the Stars' Ultimates — combat is complete

**Where an Ultimate is written: the `Ultimate Side` column of
`data/Star Players.csv`** (your Q101 - it is the Star's second side). The
game reads it from there. `python3 tools/sync_ultimates.py` copies it onto the
Emblem files so both say the same; forgetting to run it breaks nothing.

An Ultimate is **up** while its Star's Emblem has turned over and was not
BLOCKED (one per game). Then:

| Star | the Ultimate, as built | dials |
|---|---|---|
| **Gremory** | Rose tokens can replace a water unit of ANY tier; every Rose Unit in your exhaust adds 1 to your shot | — |
| **Zepar** | a Swan that attacks turns the enemy into a Swan too, and it is -2 | — |
| **Sallos** | an enemy with 2 song counters is -1 in combat; with 3, 3 damage to its own keeper and the songs are gone | — |
| **Belphegor** | Rauhnacht-Feuergeister +1 per victory counter; after a goal the counters go and the Emblem flips back to its Basic side | — |
| **Flauros** | a permanent weapon on Flauros as strong as your strongest fused unit (WEAPON on the card); all fusions break up into the exhaust | — |
| **Buer** | the Teufel Mask on your strongest field card: +1 per counter in combat, -1 counter after each combat (MASK on the card) | `buer_mask_counters` |
| **Belial** | +1 bonus Ore per unit mining; **the ore shop** before a Bergmännlein duels - buying is its ability that duel | **`data/OreShop.csv`** |
| **Valefor** | Bergmännlein in the exhaust mine (+1 Ore each); last round's miners +1 in their next combat | — |
| **Haures** | the keeper eats 1 Ore a round (max 3 a cycle): +1 shield, 5% harder to beat | `haures_armour_per_cycle`, `haures_armour_shift` |
| **Vassago** | each Unkengeister copies an enemy ability of its tier from their exhaust; that card is held there for the cycle. **Round AG (Q112 b): with more than one to copy, YOU pick** | AUTO menu: *vassago* |
| **Glasya-Labolas** | once per PLAY MAKER the first of each kind of object the enemy uses is possessed - they get nothing from it. **Round AG (Q113 b): mines, ore counters, touches on the ball, Caim's gravestones** | `glasya_objects` |
| **Caim** | 3 gravestones rise; the ball knocking one over puts a ghost on the ball; the next Unkengeister +1 per ghost | `caim_stones`, `caim_knock_reach` |

**`data/OreShop.csv`:** `Item`, `Cost` (Ore), `Effect` (`power` = +Value this
combat, `shield` = +Value on your keeper, `keeper` = Value% harder to beat
until the next shot, `stamina` = +Value to your keeper), `Value`, `Words`
(what the window says).

**Your round AE answers:** Valefor's crater drops its ore counters **once**,
when Valefor comes on (Q103, `valefor_refill`). Haures's rock keeper is drawn
**bigger** (Q104, `haures_rock_scale` 1.35).

**The balance dial (Q107):** `counter_power_<kind>` in Tuning.csv - for
example `counter_power_burn` 1 makes every burn counter on a card +1 in its
combat. 0 (the default) = a counter does only what the cards say about it.

### Round AE, phase C7: the Emblems' Basic sides — all twelve play

Every Emblem's Basic side now works while its Star is on the pitch. The five
from before (Gremory, Zepar, Sallos, Belphegor, Buer) plus seven new ones:

| Emblem | its Basic side, as built | how |
|---|---|---|
| **Vassago** | an air unit wins its combat → your next air unit gets -1 priority (resolves earlier) | row `EMB_VASSAGO_WIN` in Abilities.csv |
| **Glasya-Labolas** | an air unit that touched the ball (TOUCHED) is +1 in its combat | row `EMB_GLASYA_TOUCH` |
| **Caim** | an air unit swaps places with another air unit of its tier during combat → the enemy it fights is -1 | row `EMB_CAIM_SWAP`, new trigger `position_swap` |
| **Belial** | a mine in the FIELD zone and one in the EXHAUST zone (your Q054): every earth card of yours there that is not playing this round is MINING, +1 Ore per worked zone | `belial_ore_per_mine` |
| **Valefor** | a crater in the middle of the pitch drops ore counters (gold diamonds) on your half at every PLAY MAKER; an earth unit that runs over one picks it up, +1 Ore | `valefor_nuggets`, `nugget_reach` |
| **Haures** | your keeper becomes a rock (stone coloured, 5% harder to beat); every save gives 2 Ore to your Tier IV earth unit | `haures_rock_shift`, `haures_ore_per_save` |
| **Flauros** | a fire unit's buff on ANOTHER fire unit of yours brings +1 more for that combat | — |

**Their Conditions all count now.** Vassago's ("4 Unkengeister in the exhaust
at once") counts the most Unkengeister ever in your exhaust at once (event
`exhaust_peak` in Stats.csv).

**Six Ultimates proposed** (your Q100), written in the Ultimate Side column of
the Bergmännlein and Unkengeister Emblem files. Change them freely - C8 builds
whatever the column says. Vassago's Token word is "exhaust swap" (Q106).

**Your round AD answers:** a fused card plays with the **stronger** card's
abilities (Q096). Cards that say TOUCHED or MINING **glow** in the draft
(Q098, `card_glow_words`).

### Round AD: your answers

| you said | now |
|---|---|
| Q077 a Dev switch for the zone map | Dev screen: **Zone map at kick-off: ON/OFF** (in this save) |
| Q082 a mix | corner 20, goal kick 20, keeper's ball 12 (were 12, 12, 10) in PlayMakerStarts.csv |
| Q085 b | the enemy only swaps a STRONGER card in from its exhaust (`ai_exhaust_swap_any` false) |
| Q086 b | Flauros: you pick which exhaust card he reveals, when there is a choice |
| Q081, Q076 | kept as they are and pinned - tell me if they bother you again |

### Round AC: your testing notes

| you said | now |
|---|---|
| "output overflow, print less text!" | the CSV check printed every missing drawing (132 lines) at once. Now the first `log_problem_lines` (6) and the full list in **csv_problems.txt** (the path is printed). The Emblem line prints only when it changes. The debugger allows more text per second (project.godot) |
| hovering on the edge instead of getting open | a **"don't stand still" clock**: a unit with no job that stays near one spot for `linger_seconds` (2.5) picks a fresh spot in its own quarter - the one with the most space - for `linger_fresh_seconds`. Nobody is SENT closer than `edge_keep` (10% of the pitch height) to a touchline; they can still chase the ball there |
| draw me the zones | press **Z** in a match (`zones` in Keys.csv): the four quarters named for both sides, the dashed `edge_keep` lines, a line from every unit to where it is heading, a yellow ring on a fresh spot and a white ring that fills up = its clock. The camera shows the whole pitch while it is on. `zone_map_on_start` true starts every match with it |
| the Emblem missing was the plain enemy team | a team with no Star Emblem shows a grey **NO EMBLEM** tile (`emblem_show_none`) |
| a Test Complete Environment | **Dev screen > TEST COMPLETE ENVIRONMENT** - see "The test environment" below |
| more ways to start a PLAY MAKER | **data/PlayMakerStarts.csv** - see section 7, "How a PLAY MAKER starts" |

**Invisible units, found while drawing the zones.** A card whose Artwork file
does not exist was drawn with no body at all - only its name plate. Every
class unit is like that until the art pass. They now **borrow a stand-in**
(`placeholder_art`, `placeholder_art_Lorelei`,
`placeholder_art_Rauhnacht-Feuergeister` in Tuning.csv: files in
assets/players, separated by `;`). The "artwork not found" list still names
every drawing that is missing.

**Their Emblem race (Q063, Q064).** The enemy's Emblems now count, turn over
and get one Ultimate per game, the same as yours (`emblem_ai_races`). Their
THEIRS tile shows their pips, and "THEIR X - ULTIMATE" is announced.

### The test environment (round AC)

**Dev screen (the ⚙ Dev button on the base) > TEST COMPLETE ENVIRONMENT.**

- **It is a different save.** `user://test_environment/` - your real save is
  never opened or written. While you are in it an **orange strip** across the
  top of every screen says TEST ENVIRONMENT.
- **Every press builds it fresh:** every unlock, talent, building, brew and
  achievement; every card signed; `test_env_coins` coins and as many talent
  points; every Star Hall node filled with its own Star; **one ready team per
  class**, called "TEST · Lorelei" and so on. The season is at match 1.
- **Build your own teams on the fly** next to them - Team Build has every
  class, locked or hidden ones too.
- **Leave:** Dev screen > **Back to my real save**. Choosing a slot on the
  title screen also leaves it.
- **Claude tests in it too**: `SOAK_TEST_ENV=1` on tools/match_soak.gd, and
  `tools/test_env_check.gd` checks that it builds and that the real save was
  not touched.

### Round AB: your testing notes

| you said | now |
|---|---|
| the foul text is unreadable | the referee's bar sits on dark see-through glass, no border, bigger white text (`ref_bar_glass`, `ref_bar_text_size`) |
| can't read the hover window | it opens BELOW the card, on its own layer above the banner, and never over the referee's bar (`hover_panel_layer`, `hover_panel_keep_bottom`). If there is not room under the card it goes wide and short instead of covering the card (`hover_panel_wide_width`). It also says the card's text and what the game does with it |
| kicked across the whole field | the ball goes from his own feet over the touchline NEAREST to him (`throw_in_drift`) |
| no Emblem, feels like an old build | a build stamp bottom-left of every match (`build_stamp`) and an `[emblems] the bar shows ...` line in the Output panel. Also fixed: Emblems were never reset between matches |
| variety for PLAY MAKER | a proposal in Questions Q060 |

**Emblems now (your answers Q009-Q012):** an Emblem's Basic side works
whenever its Star is on the pitch. **One Ultimate per game:** a second Emblem
that meets its Condition still turns over - greyed, with a red X - and its
Ultimate does nothing. A goal no longer resets them (`emblem_reset_on_goal`
false); a Star that comes back brings its Emblem back as it was. The other
side's Emblem is shown too, marked THEIRS (`emblem_show_enemy`).

**AUTO menu (Q040):** switching AUTO on asks which questions AUTO should also
answer for you - spend Ore, Swans, the Rose pick, the side that stays up
(`auto_menu`). **One window for all the side choices** of a round (Q037).
**Manfred's coin is shown** (Q034, `coin_toss_seconds`). **The tracker shows
what the other side just did** (Q041) and what its cards do to you (Q035).
**Rose tokens and Swans end when their OWNER scores** (Q005, Q021). **The AI
saves Ore** for its most expensive card (Q018, `ai_saves_ore`). **Shields stop
shots only** (Q029, `shield_blocks_drains`). The draft button says
**REVEAL** (Q043).

### Combat abilities — round AA, phase C3: the keeper, the referee, and being asked

**122 of 228 class abilities work in a match now** (54%).

| new in Abilities.csv | what it does |
|---|---|
| `goalie_chance` | Value **percentage points** on how likely that keeper is to be beaten (ruling R02 - the %, never the stamina). `enemy_goalie` = easier for you to score; `own_goalie` with a minus = harder for them. Scope `round` = until the next shot; `match` = all match |
| `goalie_shield` | Value shields on that keeper: a second bar that empties **before** his stamina (R11). A shot's bite and a drain both come off the shield first |
| `remove_shields` | every shield off that keeper |
| `foul_heat` | Value **segments** of the referee's bar against the other side (R09), at the next fouls |
| `foul_chance` | +Value % that the other side commits a foul (R10, R16). `round` = the next fouls only |
| `foul_coin_flip` | the next foul your side commits is a coin toss - heads, it goes to the other side (Manfred) |
| **`Ask` column** | `yes` = you are asked before it goes off ("you CAN transform"). Rows with a Cost are asked anyway (`ask_before_spending_ore`) |

**You are asked, from now on** - only when there is a real choice, only for
your side, and never in AUTO:

| when | the question |
|---|---|
| before a duel | "SPEND ORE?" for each of your abilities in it that could pay a Cost |
| after a reveal | "BECOME A SWAN?" (Zepar) |
| after a round | "ROSE UNIT TOKEN - which one?" (Gremory) and "WHICH SIDE STAYS UP?" for a card going to the exhaust whose two sides both work out there (ruling F2, once per cycle) |

`choice_window_seconds` makes a question answer itself after a while. The
other side and AUTO take the defaults (yes / the engine's pick / the side it
last played).

**The duel window** now shows the ability that really went off, "(not this
time)" when its If was not met (or you kept your Ore), the If in words, and
"priority N" whenever the power it fights with moved.

**The gold highlights (round AN).** The duel window now walks you through
each check, slowly enough to follow:

1. **ABILITY PRIORITY** comes up and a gold ring circles the lower number.
2. A gold box lights that card's ability, then a **success** sound if it
   went off or an **error** sound if it did not.
3. The same for the other card.
4. **POWER CHECK**: both numbers ringed in gold. A change shows as "+1"
   beside the circle, slides in, and the number becomes the total (3 and +1
   becomes 4), so the circle stays one size for any one- or two-digit
   number. Then WIN / LOSE with a **victory** or **fail** sound for your side.

| Where | What you change |
|---|---|
| `Tuning.csv` `duel_hl` | false turns the highlights off |
| `Tuning.csv` `duel_hl_*_seconds` | how long each step is held, including the +1 sliding in (`duel_hl_bonus_*`) |
| `Tuning.csv` `duel_hl_colour` | the gold |
| `Language.csv` `duel_ability_priority`, `duel_power_check` | the words |
| `Tuning.csv` `duel_hl_ring_art`, `duel_hl_box_art` | the ring art (blank for now: a plain gold circle) and the PixelLab pretzel-corner box |
| `Tuning.csv` `duel_hl_art_scale`, `duel_hl_box_margin` | how big their pixels are; where the box corners end |
| `Audio.csv` `duel_ability_success` / `_fail`, `duel_power_victory` / `_fail` | the four sounds, made with Ludo.ai |

The old `duel_win` / `duel_lose` rows are gone from Audio.csv, so a duel
makes only these sounds. Edit the art in `art_source/aseprite/ui/duel_ring.aseprite`
and `duel_box.aseprite`, then export to `assets/ui/duel/`.

**Rose tokens go home at a goal** (`rose_tokens_end_on_goal`), and the units
they replaced walk back on.

### `data/Abilities.csv` — what a player does in a duel

| Column | |
|---|---|
| `Ability ID` | what a card's Attack Ability column points at |
| `Name` | shown to the player |
| `Trigger` | `on_attack`, `on_win_duel`, … |
| `Target` | `self`, `tag:brandteufel`, … |
| `Effect` | `add_attack`, `add_power`, … |
| `Value` | the number |
| `Scope` | `duel` = this duel only. `round` = the rest of the round |
| `Max` | **round X.** The *(Max 5)* on your cards: how many times it may go off for one card in one match. Blank = no limit. Also `1/cycle`, `1/round`, `2/cycle/side` |
| `If` | **round Y.** Conditions that must all be true - see above |
| `Cost` | **round Z.** `ore:3` - paid from your side's Ore pool before it goes off |
| `Ask` | **round AA.** `yes` - you are asked first |

**`add_card_chance`** (round X) is the first effect that reaches the referee
— see section 7g. **And one honest note:** the 108 set cards' Attack and
Defend columns are *prose*. A card only does something in a match when its
`Attack Ability` / `Defend Ability` column names a row here. Karl is the first
set card wired that way (`BERG_ORE_WHISPER`); every other set card is still
words on a card.

**Abilities do nothing in Adventure mode.** They are not read there at all.

### `data/Combos.csv` — what the passing move is worth

**This is the LEAGUE table only.** Adventure has its own (section 8).

| Column | |
|---|---|
| `When` | `same_element`, `same_class`, `all_different_class`, `rising_power`, `all_four`, `star_last` |
| `Needs` | how many it takes |
| `Bonus` | added to the **shot**, never to a card |

A word of warning from a simulation of 5,000 moves: because a team is
normally all one class and most classes are all one element, `same_element`
rules fire far more often than they look like they will. Keep those bonuses
small; they are a perk, not a plan.

### `data/Season.csv` — the fixture list

`ID`, `Season`, `Match`, `Opponent`, `Team`, `Class`, `Difficulty`, `Final`,
`Requires`, `On Win`, `On Loss`, `Description`.

`Difficulty` scales the opposition. Like every other bonus it goes to the
shot, not to their cards.

### `data/Seasons.csv` — the shelf of competitions

`ID`, `Name`, `Art`, `Colour`, `Requires`, `Row`, `Column`, `After`,
`Matches`. Laid out like a talent tree. `Row` and `Column` decide the
position; **each row is centred on screen**, so `Column` sets the order and
spacing within a row rather than an absolute position. Gaps in your column
numbers are kept, so a branch still looks like a branch. `After` draws the
joining line.

### `data/Teams.csv` — the opposition

`ID`, `Name`, `Class`, `Cards` (pipe-separated, one per tier), `Power`,
`Requires`, `Keeper`, `Description`.

### `data/ScratchNames.csv`

`First` and `Second` columns, combined at random to name a pick-up side for a
friendly.

---

## 7b. The squad — tired players, and players you own

Two systems that did not exist, both **off out of the box**, both one row away
from being on. They are here because the story needs them: *"a new game starts
with three Star Players"* and *"the players used in a match need to recover"*
are both impossible to write while every card in your CSVs is yours forever
and nobody ever needs a week off.

### `data/Recovery.csv` — who is out next week

A player named for a fixture comes out of it tired and sits out a number of
**fixtures** that depends on their power. The better the player, the longer —
so your best eleven cannot play every week, and **that is the whole reason to
have a squad rather than a team**.

**A fixture is anything that uses a squad**: a league match, a friendly, a cup
tie, or a run in Adventure mode. Every one you play knocks one off everybody's
rest — so going off to Adventure with four players is also how the other eight
get their legs back. That is why the two modes want different numbers:

| | |
|---|---|
| a match | a full squad — three of each Tier |
| an Adventure run | **four**, one of each Tier |

which is the `Squad Per Tier` column of MatchModes.csv.

| Column of Recovery.csv | |
|---|---|
| `Power` | 0 to 5 |
| `Plays` | **rounds he plays before he is exhausted** (round AN). Blank = 1 |
| `Turns` | fixtures he then rests in the Dorms |

**Rounds before rest (round AN, Anthony 8 Oct):** a **round** is a match or
an Adventure played to the end. A Quit or exit counts for nothing: no round
used, no rest gained. A player keeps playing until he has played his `Plays`
rounds, then he goes to the Dorms for `Turns` fixtures and comes back fresh.
Out of the box **both are his power** (Q206): power 5 plays five rounds and
rests five; power 0 plays one round at a time and never needs rest. A player
knocked out on an Adventure goes to bed at once. **Fleeing an Adventure counts
as a round** (Q208), like walking home; only a Quit counts for nothing. **A player who is not used** in a
match, an Adventure or the Brewery needs no rest and loses nothing (Q207). The count lives in the save
as `plays_<card>`.

Out of the box Turns equals the power (Anthony, 8 Oct): power 5 rests five
fixtures, power 0 none.

The state lives in the save as ordinary counters (`rest_<card>`), so it
survives a reload for free and you can read it in the save inspector. **A card
is identified by name**, like everything else in the save.

> ### It is OFF, and it should stay off for now
>
> `recovery` in Tuning.csv is `false`. A side is three players per tier and a
> class in your CSVs has about three players per tier — so the moment anybody
> needs a week off you cannot field eleven, and nor can you go to Adventure,
> which needs one fit player per tier. There would then be no way to pass a
> fixture and get anybody back. That is a dead end, not a difficulty curve.
>
> **Turn it on when a class has roughly twice a side in it — about six per
> tier.** `tools/recovery_check.gd` answers that for your actual roster: it
> plays six fixtures in a second and ends with a one-line verdict.

### `sign:` — players you actually own

`squad_ownership` in Tuning.csv, also `false` out of the box. While it is
false every card in your CSVs is yours from the first minute, exactly as the
game has always worked.

Turn it on and only the cards a `sign:` effect has given you can be fielded:

```
sign:Müller;sign:Weber;sign:Koch      in any Effects column
release:Müller
```

**Write the `sign:` rows now and turn the row on later.** While ownership is
off, `sign:` still runs and still records the squad — it is simply not
consulted. So the opening scene can be written, played and watched today, and
the day it is finished you set one row to `true` and a new game starts with
three players instead of everybody.

> Turning it on **before** there is a scene that signs somebody starts a new
> game with a squad of nobody. That is the only way to get this wrong.

### The opening, in four rows

The structure is in place for the story you described. None of it is written —
these are the hooks, with skeletons in the spreadsheets to copy:

| What | Where |
|---|---|
| **A new game gives you three Stars** | a `new_game` row in Progression.csv. `new_game` fires **once per save**, the first time the base is opened on a slot that has never been played |
| **The first match is scripted — they pour a brew at Tier III** | the `tutorial_brew` row of EnemyPlay.csv. Its `When` is `flag:tutorial_match`, which the `new_game` row sets and the match-end row clears, so it happens in that one game and no other |
| **Then the base, and learning to brew** | the ordinary Progression chain — `unlock:Brewery`, then buildings, ingredients and money gate what comes next |
| **A season opens with the head coach** | the `Story` column of Seasons.csv names a Dialogue.csv scene, played **once**, the first time you open that competition. Write the side at the top of the pyramid into it and the last fixture has a face on it from the first |

The scene skeletons are in Dialogue.csv: `after_first_match` and
`season_opening`. (`first_team`, the first draft of the opening, was deleted
in round AN: the Head Coach prologue replaces it, and the new game no longer
names a scene.) They say what belongs in them and nothing else.

## 7c. A class, an emblem, and the Team Spirit

**This is the structure your four new spreadsheets already describe.** None of
it is built yet — the talent tree is Phase 5 — but it is read, checked and
written down here so that what gets built matches what you meant.

### What a class is made of

Read the `Set Name` column of a unit CSV and the shape falls out:

```
Rauhnacht-Feuergeister
  Set "Star"        3 cards, all Tier IV       <- the three Star Players
  Set "Belphegor"   9 cards, Tiers I/II/III    <- an EMBLEM SET
  Set "Flauros"     9 cards, Tiers I/II/III    <- an EMBLEM SET
  Set "Buer"        9 cards, Tiers I/II/III    <- an EMBLEM SET
```

**One Star set plus three emblem sets.** The Star set holds one tier between
its three cards — the tier ladder rule the game has always had — and each
emblem set fills the other three tiers with nine cards, three per tier, one
of each rung. Thirty cards a class.

`Rauhnacht-Feuergeister Emblems.csv` then names Belphegor, Flauros and Buer:
**the same three words**. That is not a coincidence and it is not optional —
a set and its emblem are the same thing seen from two sides. The emblem is
the card you hold; the set is the nine units it unlocks.

### What an emblem is

A **two-sided card**:

| Column | |
|---|---|
| `Name` | must match a `Set Name` in the unit CSV |
| `Unit Type` | the class |
| `Emblem` | the picture |
| `Basic Side` | what it does from the moment you have it |
| `Condition` | what has to happen for it to turn over |
| `Ultimate Side` | what it does afterwards — **and the basic side stays live** |

### How it is meant to come together

```
   a Star Player          is tied to one emblem set
        |
   put into a node        unlocks that emblem's nine units, which are the
   of the talent tree     recipe the Brewery works from
        |
   all three Stars        that section of the tree opens, you choose ONE of
   of the same class      its three Emblems, and you may forge the
                          TEAM SPIRIT drink
```

Which is why the Star set is three cards and there are three emblem sets:
**the tree has three starting nodes and each one wants a Star.**

### The checker

> `tools/class_check.gd` prints what each class's files describe and then
> everything that does not line up. It is the only way to see a mismatch: an
> emblem whose set is missing unlocks nothing, which looks exactly like an
> emblem you have not earned yet.
>
> **Run it before you draw thirty cards for a class.** It has already found
> four things in your own files — see the top of the round notes.

## 7d. The referee — fouls, cards, and the man you lose

> *"If a team has triggered a certain number of triggers (such as combos)
> during the combat, after the combat their % of increase of creating a foul
> is established. Then the normal soccer foul system is in place, and if the
> player gets a red card, they are removed and the team only has 9 players
> left."*

This is the one rule in the game that **prices** something the rest of it
rewards without limit. Firing everything you have every round used to be free.
Now it costs, and what it costs is a man.

### `data/Fouls.csv`

| column | |
|---|---|
| `Triggers` | how many abilities and combos that side set off in the round |
| `Foul Chance` | the % chance it conceded a foul, at that many |
| `Yellow` | **if** a foul was given, the % that it is a booking |
| `Red` | and the % that it is a straight red |

Whatever is left of 100 after Yellow and Red is a free kick and nothing else
— which is most fouls, as it should be. Rows are **interpolated**, exactly
like `ShotOdds.csv`, so five rows draw a smooth curve rather than five steps.

### What a trigger is

**One ability that actually went off.** Not one an ability a card owns, and
not one the game merely looked at. It is counted in a single line of
`ability_engine.gd`, in the one place the game reaches when an effect is
about to change a number.

Every round, the match prints:

```
  Triggers this round: you 2, them 5.
```

**That line is where the answer is** when the cards feel too frequent or too
rare — before touching a row of `Fouls.csv`.

### What a foul is worth

| `Tuning.csv` | |
|---|---|
| `fouls` | `false` turns the whole thing off. No card is ever shown and the game plays exactly as it did before |
| `free_kicks` | **round AG.** `1` (default) = a free kick is a real set piece, worth what `data/FreeKicks.csv` says for where the foul was — see below. `0` = the old flat bonus |
| `foul_free_kick_power` | only when `free_kicks` is `0`: added to the **fouled** side's shot. `3` out of the box |
| `foul_card_gives_possession` | a yellow or a red also hands the ball over — a card stops the game, which is what makes it the moment a side gets the set piece |
| `foul_two_yellows_is_red` | the ordinary rule of football. It is here rather than in code because it is a rule about football, not a rule about this program |
| `foul_stand_ins` | see below |
| `foul_window_seconds` | how long the card is held on screen. `0` shows no window and the match only reports it in the log |

### `data/FreeKicks.csv` — the free kick as a set piece (round AG, phase P2)

Your Q033 / Q075. A foul the referee **sees** happens where the culprit is
standing. How far that spot is from the goal the **fouled** side attacks picks
a row:

| column | |
|---|---|
| `Range` | a name — `close`, `edge`, `far`, or any word you like |
| `Up To` | how far from that goal, as a share of the pitch's length. `0.25` = the quarter nearest it. Rows are read from the smallest; the first the spot fits is used. **The last row should say `1.00`** |
| `Shot Power` | added to the fouled side's shot this round |
| `Takes Ball` | `yes` = the fouled side takes the ball and **shoots this round, from the foul spot**. `no` = only the Shot Power, and only if they were shooting anyway |
| `Call` | the big word in the window (`DIRECT FREE KICK`) |
| `Caption` | the line under it. `{metres}` (the pitch counts as 105 m), `{taker}` |

**Who takes it.** When it is YOUR free kick and it takes the ball, a window
asks which of this round's four takes it — the taker is the shooter, so his
on-shot abilities fire. AUTO (or the AUTO menu's *free kick* line) and the
enemy pick the strongest attacker.

**Cards still work as before:** a yellow or red always gives the fouled side
the ball (`foul_card_gives_possession`), whatever the row says.

As shipped: `close` up to 26 m (+3, takes the ball), `edge` up to 42 m (+2,
takes the ball), `far` (+1). `godot --headless --script
res://tools/free_kick_check.gd` reads the file back in metres.
`tools/balance_report.py` counts how many of each Range a class wins.

### And then the ladder has a hole in it

This is the part worth reading. Sending a man off breaks **the one rule** of
section 2: a tier holds one card of each power. Tier III is a 2, a 3 and a 4;
send the 3 off and the tier can only offer two cards.

Your answer, and it is a good one:

> *"Tier III P:3 has gotten a red card. So now there are Tier III P:2 and P:4
> left. Either P:2 or P:4 at random will be chosen a replacement, keeping
> their Tier III and P:x name but getting the P:3 and having all abilities
> removed."*

So the hole is filled by a **copy of a survivor**: the same name, the missing
power, and no abilities at all — no attack ability, no defend ability, no
brew, and not a Star whoever he was copied from. The ladder is never broken,
the tier still offers three cards, and the replacement is visibly the weaker
option. A man playing out of position, which is exactly what it is.

**A new copy is drawn every draft phase**, so who covers the gap changes from
round to round the way it would in a real match. And a stand-in has no body
of his own — the man who gets tired is the survivor who agreed to play there.

Both sides get stand-ins. An enemy tier that quietly kept fielding three men
while yours was down to two would be the worst kind of unfairness: invisible.

`foul_stand_ins` = `false` leaves the tier one card short instead. That is
harsher and perfectly playable.

### The multiplication, which is the whole reason for the tool

```
godot --headless --script res://tools/foul_check.gd
```

"18% at four triggers" sounds small. It happens **to both sides, nine times a
match** — eighteen rolls. The tool does that arithmetic and simulates two
thousand matches at each level, including the second-yellow reds, which a
back-of-an-envelope count misses by about a third:

```
  triggers  fouls     yellows   reds      matches ending 10 v 11
  0         0.27      0.19      0.01      1%
  2         0.82      0.54      0.08      8%
  4         1.63      1.04      0.28      25%
  9         3.94      1.94      1.41      78%
```

Per side, per match. Find the row nearest the number your matches actually
print and that is the row that is happening in your game.

> **What I measured and you should know.** In a match between `BasicTeam` and
> the Brandteufel, **your side fires zero triggers** — none of the basic cards
> has an ability — so the foul system only ever punishes the opposition. That
> is a content gap, not a bug: the moment your cards have abilities, they will
> start giving fouls away too. It is worth knowing before you tune the curve
> against what you see today.

### What gets counted

`Stats.csv` gained `fouls_given`, `yellow_cards` and `red_cards` — **yours
only**. Every counter in that file is a counter about you, and a row called
"fouls given away" that quietly included the opposition's would be a lie on
the end-of-match screen. The *sound* fires for both sides, because a foul is a
moment on the pitch rather than a thing that happens to you.

---

## 7e. The Star Hall — the class tree, the emblems, the Team Spirit

> *"Talent Tree: brew recipes, unit-type limits, resources, adventure maps,
> switches on Star Players, and if you have three matching Stars you get
> Emblems."*

Four of those six were already a row of `Talents.csv` and always had been:

| what you asked for | the row |
|---|---|
| brew recipes | `unlock:Fire Brew` |
| resources | `count:res_hops+6` — `res_<id>` is where the Brewery keeps a material |
| adventure maps | `unlock:Marshlands` — a Biomes.csv row tests `Requires` like everything else |
| unit-type limits | `count:class_set_limit+1`, or `count:limit_lorelei_sitri+1` for one set |

There are worked examples of all four in `Talents.csv` now — **Hop Garden**,
**Good Water**, **Depth of Squad** and **The Marsh Map**. None of them needed
a line of code, and that is the point: if a thing you want is "give me some
of X" or "let me have Y", it is already a talent.

**The two that needed code are the Stars and the Emblems.** They are a
different shape — three plinths and a choice, not a grid of nodes with lines
between them — so they are a second screen: **the Star Hall**. One pool of
points, which is what makes them one tree.

### The shape, which your spreadsheets already describe

A class is **one Star set plus three emblem sets** (section 7c). So:

```
   THREE NODES, one per set of nine

   Put one of your Star Players into a node
       -> that set's NINE UNITS become yours to field

   All three nodes filled
       -> OPEN YOUR ELEMENT, and field other classes that share it
       -> FORGE THE TEAM SPIRIT
```

> ### THE EMBLEM IS NOT BOUGHT HERE ANY MORE
>
> It arrives with its Star. Field the Star and its Emblem is on the bar along
> the top of the pitch; take the Star out and the Emblem goes with them. The
> whole of it is section **7f** below, and the code is `emblem_book.gd`.
>
> **Why that is better than what it replaced.** The old tree made you fill
> three nodes and then choose ONE emblem — so two of your three Stars were
> carrying nothing, and the choice was made at a menu before you had played a
> minute of the match it decided. Now all three ride on, all three collect,
> and the first to complete its Condition turns over. **The choice is made by
> play.**
>
> So the node that sold you an emblem sells you an **element** instead:
> `Open Water`, `Open Fire`. Buying it lets you field units of other classes
> that share your element — which is the door the next water class walks
> through. `Emblem Cost` in ClassTree.csv became `Element Cost`; the old name
> is still read as a fallback so a sheet you have not updated keeps working.

**The tree is not written down anywhere, and that is deliberate.** Its nodes
are read off the unit spreadsheets. Add a fourth emblem set to a class
tomorrow and its tree has four nodes this afternoon, with no second file to
keep in step — because a tree written twice is a tree that will disagree with
itself.

### `data/ClassTree.csv` — the part the sets cannot tell us

| column | |
|---|---|
| `Class` | the class. **`*` is the fallback row** every class without one of its own uses — keep it |
| `Node Cost` · `Emblem Cost` · `Spirit Cost` | talent points, out of the same pool the ordinary tree spends |
| `Spirit Brew` | the **ID of a row in Brews.csv** |
| `Requires` | |

**One point per match** once the Training Ground is open, so a full
three-node class costs about **eight matches**.

### The Team Spirit is an ordinary brew

Forging unlocks the words **`Team Spirit <Class>`** and does nothing else.
The `Brews.csv` row named in `Spirit Brew` asks for exactly those words in
its `Requires`. The two halves meet on a name, the way every unlock in this
game does — so you can rewrite the drink completely, the element, both
abilities, the price, whether it is permanent, without touching code.

Both are in `Brews.csv` already: `spirit_lorelei` and `spirit_rauhnacht`.

### An emblem is a two-sided card, and it has two condition columns

| column | |
|---|---|
| `Basic Side` | what it does from the moment you choose it |
| `Condition` | **the prose.** What a player reads. It may be a paragraph |
| `Turns On` | **the same thing in the condition language**, so the game can read it |
| `Ultimate Side` | what it does afterwards. The basic side stays live |

Two columns for one idea, on purpose. Your Conditions are paragraphs — *"If
all three Tier I Units that were removed to create Rose Token Units were
Lorelei"* — which is exactly right for a card and impossible for a program.
So the prose stays for the player and `Turns On` is what the game tests.

**One is wired as the worked example.** Belphegor turns over at
`count:duels_won_as_Rauhnacht-Feuergeister>=4`, which needed one new row of
`Stats.csv` (`duels_won_as_{class}`) and nothing else. The other five have a
Condition and no `Turns On`, so they can never turn over yet — the checker
lists them apart from the real problems, because that is prose waiting for a
mechanic, not a mistake.

### The gate, and why it is off

`class_tree_gates_units` in `Tuning.csv` is **false**.

Turn it on and an emblem set's nine units are **not yours** until a Star
stands in its node — the team builder simply does not offer them. It is one
line in `_load_library()`, because "is this card mine" is a question
`class_tree.gd` answers.

It is off for the same reason `squad_ownership` and `recovery` are off: **a
gate switched on before there is a way through it is a game you cannot
start.** With it false the whole Star Hall is additive and not one squad you
have already built changes.

### Where the save keeps it

All ordinary `GameState` entries, so all of it is testable from any
spreadsheet:

```
   text   star_in_<class>_<set>    which Star is in which node
   text   emblem_<class>           the emblem you chose
   flag   spirit_<class>           the Team Spirit is forged
   flag   flipped_<class>          the emblem has turned over
   flag   three_of_a_kind          three Stars of one class are placed
   unlock <Class> <Set>            that set's nine units
   unlock Team Spirit <Class>      the drink
```

`three_of_a_kind` is the one the `star_collector` achievement has been
waiting on since it was written. **It is earnable now.**

> **A Star is remembered by name AND card number.** Every Star in
> `Unit_Set_Lorelei.csv` is currently called "Unit Name", and with names alone
> the first one placed blocked the other two — the tree said "you have no Star
> left" with three sitting there. The card number is the thing your
> spreadsheets already guarantee is unique.

### The four-way check

```
godot --headless --script res://tools/class_tree_check.gd
```

A class is spread over **four** files that have to agree: the unit CSV (`Set
Name`), `<Class> Emblems.csv` (`Name`), `ClassTree.csv` (`Spirit Brew`) and
`Brews.csv` (`Requires`). Nothing but a tool can see that they line up.

It then **walks** the tree on a throwaway save — fills every node, chooses an
emblem, forges the spirit — and prints what the whole thing cost and what the
gate would do:

```
  Lorelei:                   THE WHOLE TREE COSTS 8 POINT(S).
     three of a kind: yes   emblem: Gremory   spirit: forged
     the gate: 0 of 27 set cards before, 27 after.
```

A class with no `<Class> Emblems.csv` at all is listed as *waiting*, not as a
problem. BasicTeam and the Brandteufel are both in that state and neither is
broken.

---

## 7f. The Emblems — three on the pitch, one may ascend

> **ROUND Z: the Basic side PLAYS.** A new column in each Emblems file,
> **`Basic Ability`**, names rows of `Abilities.csv` (the `EMB_` rows at the
> bottom). While the Emblem is on the field, every card of that side that
> feeds the Basic side carries those rows as if they were its own:
>
> | Emblem | Basic Ability | in a match |
> |---|---|---|
> | Gremory | `EMB_GREMORY_ROSE` | the 2nd water unit into the exhaust in a round: a **Rose Unit token** replaces a water Tier I |
> | Zepar | `EMB_ZEPAR_SWAN; EMB_ZEPAR_WINGS` | a water unit revealed becomes a **Swan**; a Swan is +1 in combat. Water cards get a **SHOW** button for it |
> | Sallos | `EMB_SALLOS_SONG` | a water unit that defends and wins puts a **Song** counter on the enemy |
> | Belphegor | `EMB_BELPHEGOR_VICTORY` | a fire win puts a **victory counter** on your side, two per cycle |
> | Buer | `EMB_BUER_MASK` | a fire unit that receives a counter is **+1** in its combat, once a cycle |
>
> **The Conditions now fill from what really happens.** Stats.csv listens for
> the new events - `token_made`, `swan_made`, `counter_placed`, `ore_gained`,
> `ore_spent` - so `lorelei_swans_made` counts Swans, not duels won.
> Belphegor's Turns On is now `count:rauhnacht_victories>=4` (four victory
> counters, which respects the two-per-cycle) and Valefor's is
> `count:bergmann_ore_collected>=4`. The rest (Flauros, Bergmännlein mines,
> Unkengeister) are phase C6/C7.
>
> **ROUND AA: AN EMBLEM IS ON THE FIELD ONLY WHILE ITS STAR IS.** When the
> Star leaves at the STAR PLAYER SWITCH it takes its Emblem with it, and the
> new Star brings its own - so the bar shows ONE Emblem, top right. Once one
> of your Emblems turns over, every other Emblem of yours is **locked and does
> nothing**, not even its Basic side, until a goal resets the race.
> `emblem_follows_star` and `emblem_locked_is_inactive` in Tuning.csv. The
> Conditions that still waited on the "every duel won" placeholder are wired
> to `emblem_basic` / `card_played` / `ore_gained` instead - a placeholder
> could turn an Emblem over by accident, and now that locks the others.
>
> **Each Star only fits its own set's node** in the Star Hall (Gremory into
> Sitri - the Emblem's Set column decides). `star_fits_own_set_only` in
> Tuning.csv turns that off.

> *"Star Units when coming into the field place their emblem, which has the
> conditions on it. Each Star Player has their own Emblem. Star Players have
> their normal ability; the Ultimate form is their other side when their
> Emblem condition is met. When hovered over them, show their ultimate card
> side."*

That is the whole change and it is the biggest one since the tier ladder.

### What a class is, in one picture

```
   A CLASS = 30 CARDS

     3 Star Players     one whole tier between them, one power each
     3 sets of nine     the other three tiers, three cards per tier
     3 Emblems          one per Star, one per set

   Lorelei:    Stars are Tier II.   Each set covers I, III, IV.
   Rauhnacht:  Stars are Tier IV.   Each set covers I, II, III.
```

**You field twelve: three Stars and nine regulars.** To play all three Stars
you take one tier's worth from each of the three sets — *"divided into three
players each"* — which leaves eighteen on the bench to swap around. That
constraint is the deckbuilding, and everything below is built on it rather
than around it.

### The three rules

**1. IT IS A RACE.** All three Emblems ride on and all three collect on their
Basic side all match. The **first** to meet its Condition turns over, and the
other two are held on Basic until the reset. `emblem_race` in Tuning.csv;
FALSE lets all three turn over, which is simpler and much more explosive — a
real choice, not a safety switch.

**2. ELEMENT FEEDS THE BASIC SIDE, CLASS FULFILS THE CONDITION.** A water
unit of *any* class counts toward a Lorelei Emblem's Basic side; only a
Lorelei can complete the Condition that turns it over.

```
   Gremory · Basic side
     "When two or more WATER units enter the exhaust…"
       -> any water unit, any class.              YES

   Gremory · Condition
     "If all three Tier I Units removed were LORELEI…"
       -> Lorelei only.                            no, for anyone else
```

So a mixed water team gets a broader engine and gives up the Ultimate, and a
mono-class team gets the Ultimate and a narrower engine. **That is the whole
reason the next water class is worth writing**, and it costs no code: it is
the `Basic Feeds` column and the `Element` column of ClassInfo.csv.
`emblem_element_feeds_basic` turns it off for everybody; a single Emblem
overrides it with `Basic Feeds: class`.

**3. A GOAL ENDS THE RACE.** Every Emblem turns back to Basic, the counters
their Conditions watch go to zero, and the next race starts level.
`emblem_reset_on_goal` FALSE makes an Ultimate last the rest of the match.

### What flips

**Both, together.** The Emblem turns to its Ultimate Side *and* the Star
turns to its Ultimate Side, at the same moment. One event, two faces of it.

**A Star has ONE ability, not two.** `data/Star Players.csv` writes
`Front Side` where a unit file writes `Attack` and `Defend`, and that is the
design: a Star has one ability and an Ultimate; a normal unit has two
abilities and no Ultimate. The loader fills both faces from `Front Side`.

**Hover a Star and you read its Ultimate Side at any time**, together with
the Condition that would turn it face up and how far along that is.
Deliberately, always: an Ultimate you only see once you have earned it is one
you never aimed at. `star_hover_ultimate` in Tuning.csv.

### `data/<Class> Emblems.csv`

| column | |
|---|---|
| `Name` | the demon — Gremory, Zepar, Sallos, Belphegor, Flauros, Buer |
| `Unit Type` | the class |
| `Emblem` | the picture, in `assets/icons/` |
| `Star` | which Star carries it. **Blank means "the Star with my name"** |
| `Set` | **which set of nine can complete it.** Blank means "the set with my name" |
| `Token` | **the set's own word** — Rose Unit, Swan, Song counter, burn counter, Teufel Mask |
| `Basic Side` | the prose. What it does from kick-off |
| `Condition` | the prose. What a player reads |
| `Turns On` | the same thing the game can read — `count:lorelei_swans_made>=5` |
| `Basic Feeds` | `element` (the default), `class` or `any` |
| `Ultimate Side` | the prose for the other side. The Basic side stays live |
| `Order` | left to right on the bar |

**`Token` is the column that makes nine cards a set.** It is what those nine
make and spend, and it is what the New Class wizard fills `{token}` with when
it rolls their abilities. A set with no token is nine cards that happen to
share a class.

> ### `Set` — the column that closed a complaint the checker made every run
>
> The old code assumed a Star's name and its set's name were the same word.
> **Gremory's nine are the SITRI set**, so `class_check` reported two problems
> — one for the set with "no emblem" and one for the emblem with "no set" —
> and there was nothing to fix. The data was right and the assumption was
> wrong.
>
> A Star and its set may share a name or not, and this column says which.
> **That was the last red mark in any checker.**

### Progress comes out of `Turns On`, not out of a column

A condition is `count:<counter>>=<n>` — a counter and a target, which is
everything a progress bar needs. So there is no second column to keep in
step, and a Condition you rewrite tomorrow moves its own bar this afternoon.
An Emblem whose `Turns On` is a flag test simply has no pips, which is fine.

### Price the race in duels

```
godot --headless --script res://tools/emblem_check.gd

  Lorelei
  emblem       counter it waits on        needs
  Gremory      lorelei_tier_i_traded          3
  Zepar        lorelei_swans_made             5
  Sallos       lorelei_songs_marked           5
      SHORTEST: Gremory at 3. Spread is 2 — close enough that which one
      wins depends on how the match goes, which is what you want.
```

**This is the number that decides which Ultimates exist.** Only the first to
complete turns over, so an Emblem needing eight where another needs three is
written, drawn, and never seen. Keep the three within one or two of each
other. The tool says **SPREAD IS n** and tells you off when it is not.

It also prints the element rule worked through with your real cards, so the
YES/no columns can be read down rather than taken on trust.

### `data/Elements.csv`

Four rows: WATER, FIRE, EARTH, AIR — a display name, a colour, an icon, an
order and an `Opposes`. The plan is **one class per element first, then more
classes inside each element**, and this is the list the New Class wizard
offers. Nothing enforces four; it is just how many there are.

---

## 7g. The referee — his attention, and what he misses

> *"A % of causing fouls and getting yellow cards. A bar with 1-5 sections
> that fill up. Once the yellow is committed, the % is high to be caught when
> causing a foul. So when a foul happens and the bar isn't full, the ref
> won't say anything. I also need a ref on the side that will pop up when a
> foul happens."*

### A foul is now two questions

```
   1. DID A FOUL HAPPEN?    Fouls.csv, exactly as before. The more a side
                            set off in a round, the likelier it gave one away

   2. DID HE SEE IT?        Referee.csv. And if he did not, NOTHING happens
                            — no card, no free kick, no whistle
```

That second question is the whole feature. A foul system where every foul is
called is a tax. A foul system where fouls go unseen **until his patience
runs out** is a decision, because you can watch the bar filling and choose to
keep playing that way or to stop.

### The bar

```
   every trigger you set off      + Fill Per Trigger    (a little)
   every foul he does NOT see     + Fill Per Foul       (a lot)
```

He has `Segments` of them — five out of the box, four for the strict one.
While it fills, the chance he notices is `Caught Per Segment` for each lit
segment. **Full, it is `Caught When Full`** — 95 or 100, so the next foul is
a card near enough every time.

**And once you have been booked he is watching you.** `Caught After Yellow`
replaces all of it, whatever the bar says.

**Red is built from yellows.** `Red Per Yellow` is added to the chance a
*yellow* becomes a *red*, for every booking that side already has. With no
yellows it adds nothing at all.

### `data/Referee.csv`

| column | |
|---|---|
| `ID` · `Name` · `Portrait` | `*` is the fallback every competition uses. The picture goes in `assets/portraits/` |
| `Segments` | how many sections the bar has — your "1 to 5" |
| `Fill Per Trigger` · `Fill Per Foul` | how fast he notices |
| `Caught When Full` | the chance he sees a foul once the bar is full |
| `Caught Per Segment` | and per lit segment before that |
| `Caught After Yellow` | which replaces both, once you are booked |
| `Red Per Yellow` | how much worse a second offence is |
| `Caught Per Own Foul` | **round X.** Added to the chance he notices, for every foul THAT MAN has already committed this match — seen or not |
| `Card Per Own Foul` | **round X.** The chance a foul he sees is a yellow instead of a free kick, per earlier foul by that man |
| `Empties On` | `card` (the default) or `never` |
| `Says Nothing` / `Free Kick` / `Yellow` / `Red` | his lines, in his voice |

**Three referees ship.** `*` for everyday, `lenient` (Old Brauer, five
segments he fills slowly) and `strict` (Der Preusse, four segments and
`Caught When Full` at 100). `referee_id` in Tuning.csv picks, so a cup final
can have a stricter man than a friendly.

### The repeat offender (round X)

> *"Fouls happen naturally too, so when a player commits a number of fouls,
> that increases the % as well to get a card."*

The referee now remembers **the man**, not just the side. Every foul — the
ones he misses included — is counted against the player who committed it,
for the rest of the match. Two columns use that count:

```
   Herr Schiedsrichter        1st foul   2nd     3rd     4th
   extra chance he SEES it        0%     +8%    +16%    +24%
   extra chance it is a YELLOW    0%    +10%    +20%    +30%
```

The foul being judged never counts against itself. `tools/round_x_check.gd`
prints that table for all three referees.

> **Measured, and worth knowing before you tune it:** a side commits about
> 1.4 fouls a match, spread over twelve men, so a man rarely commits a second
> one. As shipped this rule turns about **2 free kicks in 1,000 matches** into
> yellows. It is built and correct; it only *matters* once fouls are commoner
> — raise `Foul Chance` in Fouls.csv (x2 gives about 2.7 fouls and 0.94 cards a
> match per side) or lower the `Yellow` share so there are more free kicks to
> upgrade. Your call.

### Leaning on him — an ability, or a talent (round X)

**An ability.** `add_card_chance` is a new effect in Abilities.csv: Value %
that a foul the **other** side commits, once he has seen it, is a yellow
instead of a free kick. It lasts the match. Pair it with the new **`Max`**
column — the *(Max 5)* on your cards — so it stops stacking:

```
   BERG_ORE_WHISPER   on_attack   all_enemies   add_card_chance   1   match   Max 5
```

That is **Karl's card** (Bergmännlein, Belial set, Tier I Power 2):
*"Consume 3 Ore: Add +1% to enemy Yellow Card chance (Max 5)."* He fires it
each time he attacks; the fifth time is the last.

**The Ore is not charged yet**, because there is no Ore counter in a match to
spend. When there is, change the row's Trigger and nothing else.

**A talent.** Two new Tuning rows, both 0: `foul_card_bonus_enemy` and
`foul_card_bonus_you`. A talent with `count:tune_foul_card_bonus_enemy+1` in
its Effects makes every opponent easier to book for as long as you hold it —
the same door every talent already uses.

> **Measured:** at full stack (+5%), Karl's card turns about 9 of every 1,000
> *seen* enemy fouls from a free kick into a yellow. That is small, because
> 70% of seen fouls are already yellows. If you want the card to be felt,
> make it +3% a step, or make it raise the chance he *sees* the foul instead.

### Price him in fouls

```
godot --headless --script res://tools/referee_check.gd

  === HERR SCHIEDSRICHTER (*) ===
  an average round sets off 3.0 trigger(s), which fills 0.75 of a segment.
  SO THE BAR FILLS IN ABOUT 6.7 ROUNDS if nothing is given away.

  fouls committed                    1520
  HE DID NOT SEE                     823  (54%)
  he blew the whistle                697  (46%)
  yellow cards                       393
  red cards                          131
```

**The miss rate is the number to watch.** Over about 80% and the bar is
decoration — a player never sees a card and never learns the rule. Under
about 20% and it is the system you had before the bar existed. Around half
is the shape you want: getting away with one is common, getting away with
four is not.

> **A bug this tool caught on its first run.** My first wiring rolled the red
> share *again* against a card Fouls.csv had already decided, so a yellow got
> a second chance at being red using the base number. It printed 297 yellows
> against 204 reds — two reds for every three bookings, which is not football,
> it is a riot. It is 393 to 131 now. **The measurement found it; reading the
> code did not.**

### The man himself

`ref_window.gd`. He slides in from the left over about a fifth of a second,
holds the card up at an angle, says his line and goes again — because a
referee who appears instantly reads as a bug and a referee who walks on reads
as a referee. `ref_window_seconds` is how long he is held; 0 turns the window
off and leaves the match reporting it in the log.

**The card is drawn, not loaded.** A yellow rectangle is a yellow card in
every country on earth and it can never be a missing file. The *portrait* is
an image, and until `ref_default.png` exists he is a dark panel with a
whistle on it.

**He does not pop up for a foul he did not see.** That is the point — you got
away with it, and the only sign is the bar creeping up. `ref_shows_uncalled`
TRUE shows him anyway and is a debugging setting.

### League only

An Adventure fight has no referee, no fouls and no cards. That is not a
switch: the bar is only ever created by `main_scene.gd`, and
`adventure_scene.gd` does not know this file exists.

---

## 7h. Dev mode — own everything, or nothing

> *"For the test, add a feature for me the developer to use all or none of
> the units."*

`dev_mode` in Tuning.csv is **FALSE**. Set it true and the pause menu grows a
**DEV** section:

```
   Own EVERY card          signs every card in every unit CSV
   Own NOTHING             clears the lot
   What is in the game?    the roster counted by class, to the Output panel
```

**And a red strip sits across the top of every screen for as long as it is
on.** That strip is not decoration — it is what stops a build going out with
a free roster in it, because you cannot take a screenshot without seeing it.
`dev_banner` FALSE hides it for one clean screenshot. Put it back.

It writes to the **ordinary save**, through the same `SquadBook.sign()` a
`sign:Müller` row in Dialogue.csv calls — a developer switch with its own
private store is a developer switch that tests something other than the game.
And because `squad_ownership` is FALSE out of the box, neither button changes
a single match until you turn ownership on.

**It touches the roster and nothing else.** Not coins, not achievements, not
the tree. One switch that does six things is a switch nobody can reason
about.

---

## 7i. How things move — `data/Motion.csv`

> *"The general animation feel of the buttons, screen move and more."*

Every movement in the game, in one spreadsheet — because **feel is a number
you change and look at**, and a feel buried in fifteen scripts is a feel
nobody ever tunes.

| column | |
|---|---|
| `Moment` | `button_press`, `window_open`, `goal`, `ref_walk_on`… |
| `Seconds` | how long |
| `Move X` / `Move Y` | how far it travels **from where it ends up** |
| `Scale` | how big it starts. **Under 1 grows into place, over 1 shrinks into place** — and those read completely differently: growing is arriving, shrinking is being put away |
| `Ease` | `out` fast-then-settling, `in` slow-then-arriving, `both`, `none` |
| `Shake` | pixels, multiplied by `juice_scale` |

**Every number in here is small and fast.** Two pixels, three per cent, a
tenth of a second. The temptation is to make them bigger and the result is a
game that feels like it is wading: a button that moves two pixels reads as
pressable, one that moves ten reads as broken. `goal` is the one exception,
because it is what the match is for.

A moment with no row simply does not move, so you can delete every row and
the game still works — it just stops feeling like anything.

```gdscript
MotionBook.play(window, "window_open")    # one line, anywhere
MotionBook.press_feel(button)             # hover, press and release at once
```

`MenuSupport.icon_button()` calls `press_feel` for you, so **every button in
the game already has it**.

---

## 7j. A new game: the Tutorial (round AN, 7 Oct)

The old introduction is now **the Tutorial**. It is the Tutorial button on
the title screen, and a brand-new save offers it.

### A brand-new save asks

The first time the base opens on a new save, a window asks: *Would you like
to do the Tutorial? If not, you can find it later on the main menu.*

- **Yes** plays the Tutorial (below), then brings you back to this save's
  base with the starting team, exactly as No would.
- **No** leaves you at the base with **the starting team** and nothing else.

The words are `Language.csv` `tutorial_offer_title`, `_text`, `_yes` and
`_no`. `Tuning.csv tutorial_offer` false turns the question off.

### What the Tutorial is

1. **Pub Dialogue 1**: the `Dialogue.csv` scene named in `Tuning.csv
   tutorial_first_scene` (`prologue`). Rewrite it there. Since 8 Oct Koch
   does not transform here: the Head Coach says the town needs help, that
   Koch is the star, one of the best, and Koch is simply wasted. His
   transformation is now the second TIME OUT.
2. **The tutorial match** starts by itself. It is `MatchModes.csv`
   `tutorial` (`Tuning.csv tutorial_match_mode`). Your side is
   `IntroSquad.csv` (Koch in the Star's place at Tier IV, eleven plain
   players) and theirs is all plain players. The Head Coach stops it again
   and again: every stop is a `MatchTalk.csv` row with Mode `tutorial`.
3. **Full time** starts **the morning after** (below): the Dorms, the Head
   Coach's goodbye and a first Adventure with Koch, still in the Tutorial's
   own save. `Tuning.csv tutorial_morning_after` false skips it.
4. **The end** (the morning's last box, the End tutorial banner, or Quit in
   the match) ends the Tutorial. From a new save you land at that save's
   base, locked, with the starting team. From the title screen you go back
   to the title screen.

**Nothing the Tutorial does reaches your game** (your note, 8 Oct). It always
plays in a save of its own (`user://tutorial_story.json`), which is wiped
when it starts and when it ends: its players, flags and match are thrown
away, and your save comes back exactly as it was.

### The Head Coach's stops (all in `MatchTalk.csv`, lines in `Dialogue.csv`)

All lines are **drafts** for you to rewrite. Every scene starts with `tut-`.
The tutorial match has **three cycles**, 90 minutes (`MatchModes.csv tutorial`;
Anthony, 8 Oct), and is played by `data/TutorialSquad.csv`: Koch is a plain
club player and the Star, Tier IV **Power 4**, with no ability yet. The other
two Tier IV cards are Power 3 and 5. Koch plays to the final whistle; there is
no star swap.

**Koch plays every round** (Anthony, 8 Oct). In the tutorial match the man in
the Star's place is never spent by a Play Maker: his card is offered at every
Play Maker of his cycle and he never goes to the exhaust. `Tuning.csv tutorial_star_never_spent`
false spends him like any other card.

| Play Maker | moment | scene | gold on |
|---|---|---|---|
| | the whistle | tut-kickoff | |
| 1 | Tier I cards | tut-tier1 | the P:0 card, then all three |
| 1 | Tier II cards | tut-tier2 | all three cards |
| 1 | Tier IV: Koch, the Star, no ability yet | tut-tier4 | Koch's card |
| 1 | the Tier I duel: turned over, ABILITY PRIORITY (lower first, the attacker on a tie), first box, second box, POWER CHECK (the defender wins a tie), WIN/LOSE | tut-duel-start ... tut-duel-result | the duel's own gold ring and boxes |
| 1 | the shot window | tut-shot | the shot power, then the keeper's stamina and its bar, then a circle on the % |
| 2 | Tier I cards (two left) | tut-exhaust | the cards, then the EXHAUST ZONE button |
| end of cycle 1 | **TIME OUT**: Koch's inspiration is too low, he drinks, Beer Courage switches on | tut-timeout-call, tut-timeout-inspiration | |
| 4 | Tier I: **the Kleiner Faß**. Only the P:0's bag works and it shows only the keg; he drinks it in the drinking window; his card comes up big with Fass Courage (+1 Power in combat for each other Tier I player of yours not in the exhaust, attack and defend); only he can be picked | tut-fass, tut-fass-after | the cards, then his bag button, then the keg, then his abilities |
| 4 | Tier IV: Koch's card with Beer Courage | tut-koch-ability | Koch's card |
| 5 | Tier I: **the missing beer**. "Where is the rest of the beer?!" TIME OUT at the Brewery; back on the pitch the P:1 drinks a Small Bottle (bottle window) and gets the plain beer's goalie pair: 1 off their keeper when he attacks, 1 off yours when he defends | tut-missing-beer, tut-after-brewery, tut-bottle-after | his bag button, then the bottle |
| end of cycle 2 | **TIME OUT**: the cursed brews; an Earth Brew turns Koch into a Bergmännlein with Earth Courage | tut-timeout2-call, tut-timeout-cursed | |
| 6 | Tier I: **the combo beers**. Koch hid three small beers; each has one good side and one bad side. The player reads the ATTACKING / DEFENDING banner and gives any of the three to the Tier I card | tut-combo, tut-combo-after | his bag button, then the three beers |
| 6 | Tier II: a second beer, so a Pass It On from Tier I lands on it. The third stays in the bag | tut-combo-2, tut-combo-2-after | his bag button, then the beers |
| 7 | Tier IV: Bergmännlein Koch's new ability | tut-koch-earth | Koch's card |

The rest of cycle 3 plays out to the final whistle.

**No clicking through the picks.** A card cannot be taken until it has been
on the table, and the Head Coach has finished talking, for `Tuning.csv
tutorial_pick_guard_seconds` (0.8). A fast clicker's clicks simply do nothing
until then.

**One group of gold per line.** In the Highlight column, `|` separates the
lines: `-|card:first|cards` points at nothing on line 1, the first card on
line 2, all the cards from line 3 on.

**No clicking through him.** From the moment he stops the match nothing
can be clicked, and each line stays up at least `Tuning.csv
match_talk_line_seconds` (1.2) before a click moves it on; "Click to
continue" appears when it can.

**The TIME OUTs.** The match freezes where it is and the whole screen
becomes the pub scene. When it ends, the match carries on from the same
moment, with the same score, clock and exhaust. Then the row's **Do** runs:

| Do | what it does |
|---|---|
| `keep_star:Koch` | at this switch your Star is not swapped; he plays the next cycle too |
| `ability:Koch=TUT_KOCH_BEER` | Beer Courage: +1 power for each normal player of yours who played before him that round |
| `class:Koch=Bergmännlein` | he becomes that class: element, sprite and card |
| `ability:Koch=TUT_KOCH_EARTH/TUT_KOCH_EARTH_DEF` | Earth Courage, attack side / defend side: 5 stamina off the enemy keeper when he attacks, 3 when he defends (Anthony, 8 Oct) |
| `show_card:Koch=tut-koch-new-card@abilities\|-\|-` | the match stays frozen and his field card comes up big over the pub, his attack and defend abilities beside it; then that Dialogue.csv scene plays. After `@`, the gold per line (`card`, `abilities`, `attack`, `defend`, `-`), `\|` between lines. `Tuning.csv show_card_scale` (1.8) and `show_card_backdrop` (bar) |
| `inspire:Koch=75` | his inspiration in % on the drunk meter (`DrunkLevels.csv`): 75 after cycle 1 (past Inspired, so his star ability wakes up), 90 after cycle 2 |
| `drink_lesson:first=keg@barrel@tut-fass-after@abilities\|-\|card` | the drinking lesson. `<card>=<item>@<barrel or bottle>@<scene>@<gold>`. The item goes in the bag if it is missing; only that card's bag button works and his bag shows only that item; gold on the button, then on the item. When he drinks: the drinking window (his own sprite, the barrel or bottle, gulps, spills, arm wipe, burp; `Tuning.csv drink_window_seconds`), then his card comes up big as with show_card and the scene plays. Only he can be picked after |
| `give:anstoss_helles+doppelpass_weisse+abstauber_dunkel` | puts one of each into the bag (`item=3` for more). A drink_lesson can then name several items with `+`: the bag shows those, gold on each, and any one will do |
| `say:tut-after-brewery@-\|-\|flask:first` | plays that Dialogue.csv scene, gold per line after `@` (the Highlight words) |
| `brewery:tut_brewery` | a TIME OUT at the Brewery (round AN): the match freezes, that flag is set and the Brewery opens over it; `Guide.csv` rows that need the flag lead the way, and one whose Then is `goto:back` ends it. See "The tutorial Brewery" |

**Time passes: a fade to black** (Anthony, 9 Oct). A Dialogue.csv line
whose **Background** is `black` fades the screen to black (the words still
show) and it stays black; the next line with any other Background (`bar`)
fades back in on that picture. `Tuning.csv story_fade_seconds` (0.8). The
prologue's "Cheering!" and "After a few more rounds..." use it.

**A drink in a match lasts one cycle** (Anthony, 8 Oct). A brew or beer used
on a card during the draft wears off at the next STAR PLAYER SWITCH
(`Tuning.csv match_drink_lasts_cycle`), and it takes hold at once, however
low his drunk meter is (`match_drink_takes_hold_at`, 0). In the tutorial the
keg (`Items.csv keg`, Use `brew:pool:keg`) always gives the `Brews.csv
kleiner_fass` row, because that is the only keg row whose Requires
(`flag:in_tutorial`) passes. Outside the tutorial the keg is the plain beer
gamble. The barrel and bottle in the drinking window are drawn in code for
now, until PixelLab art exists. The burp is `Audio.csv drink_burp`, silent
until `bav_burp.ogg` is made (`SOUNDS_WANTED.csv`).

**The combo beers** (Anthony, 8 Oct). Three small beers, `Items.csv`
`anstoss_helles`, `doppelpass_weisse`, `abstauber_dunkel`, each with its own
`Brews.csv` row (Pool = its own ID, so it is never poured at the Pub):

| beer | good side | bad side |
|---|---|---|
| Anstoß Helles | attacking: Pass It On, +1 power to your next player who duels | defending: Heavy Legs, -1 power |
| Doppelpass Weiße | defending: One-Two, +1 power to your next player who duels | attacking: Fumbled Pass, -1 power |
| Abstauber Dunkel | attacking: Tap-In, +1 power | defending: Sleepy Keeper, 1 stamina off your own keeper |

The abilities are the `COMBO_` rows of `Abilities.csv`. Tier I duels before
Tier II, so a Pass It On on Tier I pushes Tier II: that is the combo.

**The EXHAUST ZONE button** (bottom right of every match, `Tuning.csv
exhaust_button`) says how many of your cards are spent this cycle. Press it
to see them.

**TOUCHED** on a card now only shows when that card's own ability asks
whether it touched the ball. Plain players never show it.

### The starting team

`data/StartingTeam.csv` (`Tuning.csv starting_team`): twelve plain players,
three per Tier, with random names. The base gets it at the end of the
Tutorial, or when you say No. They are new people, not the ones from the
tutorial match, because nothing from the Tutorial is kept. Nothing else is
unlocked.

### The old introduction (retired)

The `Progression.csv` rows `welcome_at_base`, `sign_your_first_three`,
`kick_off_first_match`, `first_match_is_over`, `kick_off_second_match` and
`second_match_is_over` now wait on `flag:old_introduction`, which nothing
sets. Delete that word from a row's Requires to bring it back. The intro
and intro2 match modes, the star-intro scene and the steps below are kept
for when you continue the Tutorial.

### After match two: the Brewery, an Adventure, the Traveling Merchant

7. **At full time of match two**, `learn_to_brew` opens the Brewery and the
   Malthouse, sets `flag:brewery_tour`, and plays `brewery-intro`.
8. **Back at the base, the Brewery window opens by itself**
   (`open_the_brewery`). The Head Coach's boxes and the lit-up WORK IT
   button come from `data/Guide.csv` (below).
9. **After the first malt**, he says you are short of ingredients.
   `flag:intro_adventure` is set, and the window closes back to the base.
10. **At the base**, he says go on an Adventure, and the Adventure banner
    lights up. Nothing is forced.
11. **The Adventure board** works as usual. While `intro_adventure` is on,
    the only team is your first team (`MatchModes.csv intro_adventure`,
    squad `IntroSquad2.csv`), so the run starts as soon as you press start.
12. **Carry a run home** (`count:adventures_home` goes up by one) and the base
    sends you straight to **the Traveling Merchant** (`meet_the_merchant`).
    His intro is `Guide.csv shop_intro`, and he trades beer for Reed and Bog
    Iron (`Shop.csv trade_fire_brew` / `trade_water_brew`; Reed and Bog Iron
    are currencies in `Currencies.csv`). **The intro stops here for now.**

A story scene that is missing never strands you. The screen says so for a
moment, then carries on to wherever the scene was returning to: the base.

### `data/Guide.csv`: the Head Coach explains a screen

| column | what it does |
|---|---|
| **ID** | A name for the row. A row that has played sets `flag:guide_done_<ID>`, so the next row can wait for it. |
| **Screen** | `base`, `brewery`, `shop`, `bounty` (the Adventure board) or `dorms`. The screen asks when it opens, and again when it redraws. |
| **Requires** | The usual condition language. |
| **Scene** | A `Dialogue.csv` scene, shown in the box over the screen. The lines are placeholders for now. |
| **Highlight** | The words on a button to light up after the box, such as `WORK IT` or `Adventure`. It pulses until it is pressed. |
| **Then** | Progression Do actions after the box. They run **before** the button lights up (round AN), so a key or stock handed over here makes the machine ready to work. `goto:base` closes a window that is open over the base. `goto:back` closes the screen itself, including the Brewery over a match TIME OUT. `goto:dorms` opens the Dorms. `tutorial:end` ends the Tutorial. |
| **Once** | `true` plays it only once. |
| **Only** | `true` (round AN): nothing but the lit button can be used until it is pressed, so the tutorial can't be clicked through. In the Brewery only the lit machine works, and its mini-game can't be lost. |

The pictures come from `StoryArt.csv` IDs named in `Tuning.csv`.
`brewery_background` (`brewery`) sits behind the Brewery screen, the same
picture as the Brewer's scene. `shop_background` (`merchant_shop`) and
`shop_keeper` (`merchant`) are the shop and his face. Until a picture exists,
the screen looks as it always did.

### `MatchModes.csv`: two new columns

| column | what it does |
|---|---|
| **Replaces** | Other modes, such as `friendly;season;quick;cup`. While this row's **Requires** is true, a button that asks for one of them plays this mode instead. That is how the intro happens from the ordinary Play a match button. |
| **Squad** | A CSV in `data/` whose players take the field **instead of your team**. Team Build does not turn you away from such a match. |

### `data/IntroSquad.csv` / `IntroSquad2.csv`, a side written row by row

| column | what it does |
|---|---|
| **ID** | A name for this place in the team. **The same ID is the same player.** A random player is made once per save for each ID and kept, and joins your base as a named player. `release:Name` lets one go. |
| **Tier, Power** | Three per Tier, one of each power on the ladder. |
| **Name** | Blank gives a random first name from `Names.csv` of that Gender. A Name with **Class** blank is that real card, such as the Star Belial. |
| **Class** | Whose plain card it is. `Normal` is the club's own players. |
| **Gender** | `m` or `f`. Blank picks either at random. The sprite comes from `Tuning.csv squad_art_m` / `squad_art_f`, which can list several sheets separated by `\|`. Women have three looks (brown ponytail, blonde plaits, short black bob). Each new player gets one at random and keeps it. |
| **Lead** | `yes` on one row. That Tier stands where the Stars usually do, and that player kicks off. With no Star in the sheet, nobody wears a Star badge or carries an Emblem. |

`Names.csv` has a new **Gender** column for its first names (m / f).

### The opposition in the first two matches

Your answer: early in a new game the other side is all plain players, with no
brew and nobody special.

- **Match one, `data/EnemyIntroSquad.csv`:** twelve plain Rivals players, no
  Stars.
- **Match two, `data/EnemyIntroSquad2.csv`:** plain players, plus the plain
  Stars Bauer, Richter and Klein. Their only ability is `PLAIN_STAR_PUSH` in
  `Abilities.csv`, which gives +1 to the next normal, non-elemental player on
  their side.
- `MatchModes.csv` has an **Enemy Squad** column. When it names a squad CSV,
  set **Opponent** to `squad`.
- Squad sheets have two more columns: **Star** (`yes` makes a player a Star)
  and **Ability** (an `Abilities.csv` ID, used on both sides of the card).
  An opposition is made fresh every match. It is not saved and does not join
  your base.
- **The scripted brew is switched off.** `EnemyPlay.csv tutorial_brew` now
  waits on `flag:enemy_brews_in_intro`, which nothing sets.
- In a side with no Stars, the plain player standing in the Stars' place is
  swapped at the STAR PLAYER SWITCH just as a Star would be.

### `data/MatchTalk.csv`: the Head Coach stops the match

One row is one interruption. **Mode** is a `MatchModes.csv` row (`tutorial`),
or blank for any match. **When** is the moment: kick_off, duel_won, duel_lost, shot_taken,
goal_scored, goal_conceded, save_made, keeper_emptied, foul_given,
card_yellow, card_red, free_kick_won, star_switch or play_maker. **Requires**
is the usual condition language. **Scene** is a `Dialogue.csv` scene. Its
lines play in a box along the bottom of the screen, with the speaker's face,
while the game waits. **Once** `true` plays it only the first time ever. The
size of the words is `Tuning.csv match_talk_text_size`.

Four more columns (round AN, the Tutorial), all optional:

| column | what it does |
|---|---|
| **Round** | Only at this Play Maker of the match. 1 is the first; the 4th is the first of cycle 2. |
| **Tier** | Only for this Tier: `I`, `II`, `III`, `IV`, or `STAR` for the star swap cards. |
| **Highlight** | What he points at with a gold box: `card:first`, `card:last`, `card:Koch`, `cards`, `exhaust`, `keeper_chance`, `keeper_stamina`, `shot_power`. `ring:` in front draws a gold circle instead. Several with `;`. |
| **Do** | After his lines: `pub:<scene>` (TIME OUT), `star:<name>`, `ability:<name>=<Abilities ID>`, `announce:<words>`. |

More moments for **When**: `cards_shown` (a Tier's cards are on the table),
`duel_start`, `duel_priority`, `duel_ability_1`, `duel_ability_2`,
`duel_power_check`, `duel_result`, `shot_odds` (the shot window shows the %)
and `shot_done` (after the goal or the miss).

### The morning after: rest and the first Adventure (round AN, 8 Oct)

Your pick from the plan: after the final whistle the story carries on, in
the Tutorial's own save, so nothing here is kept either.

| step | where | what happens | rows |
|---|---|---|---|
| 1 | full time | The side's round counts like any match (`Recovery.csv`, `Resting.csv`), their drunk meters drop, and the Dorms are unlocked with their key (`Tuning.csv tutorial_morning_effects`). Then the full-time scene in the bar | `tutorial_morning_scene` |
| 2 | the base | The Head Coach: this is our town. Then straight to the Dorms | Guide.csv `tut_morning_base` |
| 3 | the Dorms | Rounds = power, rest = power, power 0 never needs a bed, a fixture wakes everybody a step, the drunk meter wears off. Back to the base | `tut_morning_beds` |
| 4 | the base | The Brewery is dry, the Adventure Team, and the Head Coach leaves for Beuterdorf. The Adventure banner lights up | `tut_morning_handover` |
| 5 | the Bounty Board | Koch: the Marshlands, the Brewer's Errand (`Bounties.csv tut_brewers_errand`, two waves, the Reed Warden; only on the board in the Tutorial) | `tut_morning_board` |
| 6 | the run | `MatchModes.csv tutorial_adventure` stands in for the Adventure: the party is `data/TutorialAdventureSquad.csv` (four Adventure Players, one per Tier). Koch stops it at each first | MatchTalk.csv, Mode `tutorial_adventure` |
| 7 | the base | However the run ended (home, fled or fallen), Koch takes you back to the Dorms | `tut_morning_home` |
| 8 | the Dorms | The party in bed, the match side a fixture nearer fit. Its Then is `tutorial:end` | `tut_morning_beds_2` |

**All the lines are drafts** in `data/TutorialMorningDialogue.csv` (any CSV
in `data/` with Node ID and Text columns is a dialogue file). Rewrite them
there. From step 4 on Koch is the guide, with his Bergmännlein face.

**Koch's Adventure stops** are ordinary `MatchTalk.csv` rows whose Mode is
an Adventure mode. The moments (**When**) are `adv_start`, `adv_pickup`,
`adv_wave`, `adv_boss`, `adv_focus`, `adv_draft` (Tier column I to IV),
`adv_hit`, `adv_down` (one of yours out of stamina) and `adv_loot`.
**Round** is the wave. **Highlight** is the words on a button to light up
after the box, such as `Continue forward`. **Once** true plays a row only the
first time. The game is paused under the box and nothing can be clicked
until it closes. Any Adventure mode can have rows like these.

**Two new Guide.csv words.** Screen `dorms` plays over the Dorms, and Then
`goto:dorms` opens them. Then `tutorial:end` ends the Tutorial.

**Every run that ends** (home, fled or fallen) now adds one to
`count:adventures_played`. `count:adventures_home` still counts only the ones
carried home.

**A way out.** While the Tutorial is on, the base has an **End tutorial**
banner. It ends the Tutorial straight away, exactly as the last box does.

`godot --headless --path . --script res://tools/morning_after_check.gd`
plays the morning through the real screens and checks every step. Without
`--headless` it saves a picture of every box in `user://morning_check/frames/`.

### Checking it

`tools/tutorial_check.gd` checks the match part only (it turns the morning
off). `godot --headless --path . --script res://tools/tutorial_check.gd` plays the
Tutorial through the real screens: No on one new save, Yes on another, every
Head Coach stop, the TIME OUT and Koch the Star, and the base at the end.
Without `--headless` it saves frames of every stop in
`user://tutorial_check/frames/`.

`tools/intro_check.gd` checks the old introduction, so it fails now that it
is retired. It plays all of
this through the real screens, in its own save (`user://intro_check/`), and
prints PASS or FAIL for each step. Run it without `--headless` and it also
saves screenshots there.

## 8. Adventure mode

`src/adventure/` — eleven scripts. The run is a scrolling pitch; the fight is
a separate object that can be run with no graphics at all, which is what makes
it testable.

### How a run goes

```
pick a bounty  ->  the party runs right, collecting things off the ground
               ->  a wave blocks the way, both sides walk into place
               ->  THE FIGHT (below)
               ->  loot, then Continue Forward or Return to Base
               ->  the last wave is the boss
```

Returning to base banks the haul. Fleeing keeps `adventure_flee_keep` of it.
Everybody being knocked out loses all of it — which is what makes Return to
Base a real decision.

### The board and the look (adventure-look, 10 Oct)

**The soccer & training board.** The Bounty Board is now a board in a beer
cave. Biomes are tabs across the top; that biome's jobs hang on the board as
scrolls. Click a scroll and it unrolls: the quest, what you need, what it
pays, **Back** (roll it up, read another) and **Accept Contract** (sets off,
same as START EXPLORING did). A locked scroll still opens and says what it
needs; Accept is greyed.

| To change | Where |
|---|---|
| Scroll label (Match, Training ...) | `Bounties.csv` **Kind** |
| What the scroll says | `Bounties.csv` **Quest Text** (blank = Description) |
| Where it hangs | `Bounties.csv` **Pin X**, **Pin Y** (0-1, blank = rows) |
| Cave, board, pinned scroll, open scroll art | `Tuning.csv` `adventure_board_background`, `adventure_board_art`, `adventure_board_pin_art`, `adventure_scroll_art` (blank = plain colours) |
| Board and scroll size, unroll speed | `adventure_board_width/height/inset`, `adventure_scroll_width/height`, `adventure_scroll_unroll_seconds` |
| Words | `Language.csv` `adventure_board_title`, `accept_contract`, `scroll_requirements`, `scroll_rewards` |

**Isometric players.** The squad on the run is the squad you picked, drawn
with the same isometric sheet each player wears in a match
(`PitchSprites.csv`), with run, idle and fall. Name, tier, power and the
stamina bar sit on the same plate as before. `adventure_iso_players` = false
goes back to the old card sheet; `adventure_iso_player_scale` sizes them.

Art drafts for the board, cave, scroll, isometric Marsh and map style are in
`art_source/drafts/adventure_look/` and wait for your pick before finals.

### How a fight goes

```
1  FOCUS    point at an enemy and click it. Everything this round lands on it
2  ITEMS    optional, and only before the drafting starts
3  DRAFT    Tier I, then II, then III, then IV — one card each
4  YOUR HIT the four powers are added up, plus what the pile is carrying,
            and go into the focused enemy's outermost layer minus its soak
5  THEIR HIT every living enemy strikes back
```

**The choice window is the same height for every tier.** It shows
`adventure_choice_rows` rows of cards — one out of the box — and scrolls past
that. Tier II offering six cards (three ready, three resting) no longer grows
the window up over the top of the screen the way it did. Raise it to `2` if you
would rather see more at once and can spare the room.

**The icons along the top have three looks, not two.** Grey is an icon you
have none of. Full colour is one where you have reached a breakpoint. And
while the mouse is over a card, every icon that card would move takes a
coloured edge and blinks — *whether or not it is lit*.

That third look is why pointing at a **Tier I** card now lights something.
Tier I is the first card of a cycle, so its icon goes 0 → 1 and one is never
enough to reach a breakpoint; the bar was answering "have you reached
something" when the question the mouse is asking is "does this card touch this
icon". Both are worth seeing and they now look different from each other.

**Hovering a card does not open a grey box any more.** The card's league
ability wording belongs to a league duel; it is not read in an Adventure fight
and putting it under the mouse was telling the player something untrue. The
icons the card would put on the pile are what matters here, and those are shown
along the top.

Two rules keep it fair:

* **A tier with nobody left is a walkover.** Not a thin tier — a completely
  empty one. It adds nothing to your hit and doubles everything they do.
* **Enemies spread their damage.** Each one hits the weakest player in
  whichever tier currently has the most standing. That stops any one tier
  being quietly wiped out, which is what would cause the walkover above. An
  enemy whose `Targeting` says otherwise is breaking that rule on purpose.

### THE PILE — Adventure's combat system

This is the part that makes Adventure a different game from the league.

Every player you draft drops their **icons** on a pile. Three Fire on the pile
and every shot is worth four more. Four Wand and a Treant walks on. **The
pile does not empty each round** — it empties at the end of the round in which
the **cycle** comes round, meaning every tier has fielded everybody it has.
So a fight is one long build with a reset in the middle, and "do I spend my
last Fire now or hold the tier open" is the decision you are actually making.

#### `data/AdventureTraits.csv` — what the icons are

| Column | |
|---|---|
| `ID` | what AdventureCombos.csv points at |
| `Name` | written under the icon |
| `From` | **where the icon comes from**: `element`, `class`, `star` or `tier` |
| `Value` | which value in that column counts. Blank for `star` |
| `Icon` | a file in `assets/icons/`. Missing = a coloured pip, which plays fine |
| `Colour` | `#rrggbb` |
| `Order` | left to right along the top of the screen |
| `Max` | how far the bar counts |
| `Requires` | **whether this icon is on the shelf at all**, in the condition language. Blank = from the first run. `unlocked:Frost Study` = once something hands that out |

**A RUN CARRIES EIGHT ICONS.** `adventure_trait_slots` in Tuning.csv says how
many; this file is the shelf they are chosen from. Write forty if you like — an
icon outside the eight does nothing at all: no bar along the top, nothing on the
pile, no breakpoints. Reading eight bars every round is already near the limit
of what anybody takes in at a glance, which is why there is a cap at all.

`Requires` is how you write more than eight honestly: leave your starting set
blank, put an `unlocked:` on the rest, and hand those unlocks out with talents
and season rewards. The workbench warns you if more icons are free from the
first run than there are slots to carry them, because the ones that do not fit
are chosen by load order, which is to say by accident.

**The player chooses which eight**, on the **Edit Element Bonus** screen —
the button beside Inventory at the bottom of the Bounty Board. Everything
unlocked is on the shelf, the carried ones are lit and numbered in the order
they appear along the top of a fight, and once eight are carried the rest say
so rather than doing nothing. *Start again* puts back the first eight, the way
a new save has them.

The choice is kept in the **save**, not in a CSV, because it is the player's
decision rather than yours. What you decide is which icons exist, what they
do, and what has to be unlocked before one can be chosen at all — and those
three are this file, AdventureCombos.csv and the `Requires` column.

A save that has never opened the screen carries the first eight in `Order`
order, so a new game always has a full bar without anybody visiting a screen.

**A player carries several icons.** A Lorelei whose Element is Water stacks
*Water* and *Lorelei*, from two different rows, and both bars move. That is
what makes a squad a decision rather than a sum.

**What they drank counts.** `From = element` reads the `Element` column of
`Brews.csv`, and `From = class` reads the brewed class. So a Lorelei who
drinks a Fire Brew genuinely brings a Fire icon and a Brandteufel icon.

**A player matching no row contributes nothing.** That is legal, but it should
be on purpose — it is why `BasicTeam.csv` needed a `Journeyman` row.

#### `data/AdventureCombos.csv` — what reaching one does

| Column | |
|---|---|
| `Trait` | which row of AdventureTraits.csv |
| `At` | **how many it takes.** 2 means two of that icon on the pile |
| `Name` | what flashes up |
| `Effect` | see the table below |
| `Value` | the number. What it means is per effect |
| `Target` | who or what. Per effect |
| `Lasts` | `held` = true while you hold it. `once` = fires when you reach it. Blank = the sensible default, printed on load |
| `Icon` | **the icon at this breakpoint**, so the picture changes as you climb |
| `Description` | the line a player reads |

```
attack    Value is added to the SHOT.        Target: —
strike    Value damage into enemies.         Target: all / focus
heal      Value stamina back.                Target: lowest / all / last
stamina   the same, under a friendlier name. Target: lowest / all / last
revive    Value players get up.              Target: how much stamina each
shield    Value off every hit against you.   Target: —
spawn     Value stand-ins walk on.           Target: a row of AdventureSpawns.csv
```

**Only the highest breakpoint you have reached is active**, for `held`
effects. Three Fire gives you Blaze, not Kindling *and* Blaze — that is what
makes 3/4 worth chasing. `once` effects all fire as you pass them.

An `Effect` the game has never heard of is reported by name on load, with the
list of ones it knows, and that row is skipped.

#### `data/AdventureSpawns.csv` — the stand-ins

`ID`, `Name`, `Power`, `Tier`, `Element`, `Class`, `Stamina`, `Art`.

A spawn walks on to replace somebody who is out and takes **that player's
tier** — leave `Tier` blank for that, or fill it in to pin a spawn to one
tier. **Its power is clamped into that tier's legal rungs**; the ladder is not
broken even by a spawn, and the log says so if a number had to move. It is
then a real member of the party: draftable, hittable, and it puts its own
icons on the pile.

**A stand-in is on loan, not a signing.** It walks on beside the party, kicks
and receives the ball like everybody else for as long as the fight lasts, and
**leaves when the fight ends** — it is taken off the squad, off the stamina
list and off the screen, and the party that walks on to the next encounter is
the party you started the run with. That is what keeps `spawn` a rescue rather
than a way to quietly grow a squad of fourteen over an afternoon.

#### The enemies use the same table

An enemy's `Element` and its `Pool` are the icons it carries, out of the same
two spreadsheets. **Only `attack` applies to them** — they do not revive,
spawn or heal, because that would make a wave unkillable rather than
dangerous. `adventure_enemy_combos = false` turns it off.

### `data/AdventureEnemies.csv`

| Column | |
|---|---|
| `Pool` | which biome pool it belongs to |
| `Attack` | what it hits for |
| `Layers` | `Hide:4|Body:6` — outer first. `Name:amount` or `Name:amount:soak` |
| `Targeting` | `weakest` (the default), `strongest`, `lowest_stamina`, `aoe` |
| `Element` | its Adventure icon |
| `Buff` | **what it gains per pass while you build your move.** Blank/0 for most of them; give it to the ones that should feel like a clock ticking |
| `Drops` | a table in Drops.csv |
| `Weight` | how often it turns up in its pool |
| `Boss` | `yes` — counts as the Star for their icons |

An enemy has **no tier**. Your whole line-up hits the one enemy you focused,
and then every enemy hits back. An enemy is two numbers and a list of layers.

### `data/Biomes.csv` and `data/Bounties.csv`

Biomes: `Waves`, `Enemy Pool`, `Drops`, `Difficulty`, and six presentation
columns (`Background`, `Parallax`, `Sky`, `Grass`, `Grass Stripe`, `Edge`) so
an ice biome is blues and a desert is yellows with no code.

Bounties: `Biome`, `Boss`, `Reward` (condition language), `Repeatable`,
`Waves`, `Recommended Power`.

`Difficulty` × how many times you have cleared the biome scales the enemies,
so a repeat run is genuinely tougher rather than just longer.

### `data/Items.csv` and `data/Drops.csv`

Items: `ID`, `Name`, `Kind`, **`Tab`**, `Stack`, `Art`, `Use`, **`Tags`**,
`Target`, `Requires`, `Description`. Every item is a counter in the save, so
anything that can test a counter can test an item.

`Use` is **what it does**: `revive`, `heal:6`, `heal:3;all`, `hit:4`, or
`brew:fire` to lay that row of `Brews.csv` over one player. Blank means it is
not usable at all.

`Tags` is **where you are allowed to do it** — a semicolon list:

| Tag | |
|---|---|
| `adventure_consume` | may be used during an Adventure fight |
| `match_consume` | may be used on a player during the match draft |
| *no tag* | **the normal case.** Taken at the bar before the team sets off |
| anything else | yours. The game ignores it; test it with a `Requires` |

A `Use` with no tag is not broken — it is simply not something you pull out
mid-wave. The Inventory shows it greyed with a line saying where it *can* be
used, rather than hiding it or letting it do nothing.

Drops: `Table`, `Item`, `Amount`, `Chance` (0–1), `Requires`. One table is
several rows sharing a `Table` name.

### THE INVENTORY — one bag, three tabs

The same window opens from the base, the Bounty Board, an Adventure fight and
the match draft. A grid of square buttons: the thing's picture with how many
you have in the corner, and pointing at one writes what it is in the panel
underneath. Nothing is labelled, because forty labelled tiles is a wall of
words and forty pictures is a bag.

| Tab | What goes on it |
|---|---|
| **Items** | things you **use** — brews, bandages, smelling salts. **The only clickable tab** |
| **Resources** | things you **spend** — reed, bog iron, coins |
| **Keys** | things you **hold** and never spend — a key, a token, a letter |

The `Tab` column of Items.csv decides. **Leave it blank and it is worked out
from `Kind`:**

```
kind = key / token / quest     ->  keys
kind = material / currency     ->  resources
anything with a Use            ->  items
anything else                  ->  resources
```

A `Kind` you invent tomorrow lands in Resources unless you say otherwise,
which is the safe place for it — nothing in Resources is clickable, so an
unknown thing can never be used by accident. The workbench warns you about an
item filed under Items with no `Use` (a tile that does nothing when pressed)
and about one on Keys that has a `Use` (something that can never happen).

> There used to be a separate screen called **YOUR KIT** that listed usable
> items as lines of text. It showed a third of what you were carrying and it
> was the only thing in the game that looked like that. It is gone; everything
> it did, this does.

#### A brew is an ordinary item — a building makes it

**Nothing is made inside the inventory.** A brew is bottled at a building and
carried; the bag holds the bottle. That is the difference between an inventory
and a workshop, and it is why the whole thing is three cells:

```
Buildings.csv   brewery
  Requires      unlocked:Brewery;count:reed>=6
  Action        count:reed-6;count:brew_fire+1;announce:A Fire Brew is bottled.

Items.csv       brew_fire
  Use           brew:fire          <- names a row of Brews.csv
  Tags          match_consume      <- used on a player, during the draft
```

`The Cold Cellar` is the second worked example: a different unlock, two
materials instead of one, and a different bottle out of the other end. A new
building making a new consumable is nine cells and no code.

#### Using one on a card mid-draft

Every card in the match draft has a small **flask in its top-left corner**
(the Star badge is top right). Pressing the card chooses that player; pressing
the flask opens the Inventory showing what you are carrying that is tagged
`match_consume`, and using one **spends the bottle** and changes the card's
class, art and abilities while you are still deciding.

The `For Class` rule still applies — a Fire Brew written `For Class: Lorelei`
is refused on a Brandteufel, out loud, and **the bottle is not spent**. It is
always a **one-match** brew, so the final whistle takes it off again, which is
the same line that has always cleared them.

| Tuning row | |
|---|---|
| `draft_brew_button` | `false` takes the flask off the cards |

---

## 8b. `data/Stadium.csv` — the pitch and the village round it

**Round AN (your ask, 6 Oct): the white lines are the edge of the player
zones, and outside them is the village.**

```
the pitch        2560 x 1440      assets/field/soccerfield.png   (see-through outside the grass)
the village      2560 x 1440      assets/field/stadium_back.png
the Full House   2560 x 1440      assets/field/stadium_crowd.png
```

All three are the same size and sit exactly on top of each other, so a house
at X 300 in the village is always 136 pixels left of the goal line.

### Where the white lines are, and why

```
     2560 wide
  +--------------------------------------------------+
  |   houses, church, fans          288 px           |
  |       +------------------------------------+     |   1440
  | farm  |  THE LINES = THE ZONES  1688 x 864 | tent|   tall
  |  436  |   x 436-2124, y 288-1152           |  436|
  |       +------------------------------------+     |
  |   fans, clubhouse, locals       288 px           |
  +--------------------------------------------------+
```

The four Tier zones, both goal mouths and the throw-in spots are measured
against one rectangle: the **first camera view** (the 1920 × 1080 window,
centred on the picture) pulled in by `pitch_inset_x` (6%) and
`pitch_inset_y` (10%) in Tuning.csv. Until round AN the lines were drawn 6%
and 10% in from the edge of the **whole picture** instead, which put them
far outside the zones — the goals were nowhere near the goal mouths. Now:

- `tools/make_pitch.py` works the rectangle out the same way the game does
  and rules the lines on it. **Change either inset row, run it again**, and
  the lines follow the zones.
- `tools/field_shot.gd` opens a match, prints where the zones land in the
  picture, and saves a picture with the zone map on so you can see the two
  agree (`-- full-house` adds the fans).

### The village — `data/VillageGround.csv`

One row per PixelLab part (`art_source/pixellab/village/`): the meadow, the
houses and church, the farm, the beer tent, trees, the clubhouse, the
locals, the fans. `X`, `Y` are the top-left corner in pitch pixels; `Scale`
is a whole number (2 for buildings, 1 for people — the players' size);
`Flip h` mirrors a part; `Layer` is `background` (always there) or `crowd`
(only with **Full House** unlocked). Then:

```
~/.venvs/sturmball/bin/python tools/make_village.py
```

writes both pictures and `art_source/aseprite/stadium.aseprite`, with every
part (and the pitch, on top) on its own layer. The round AN top-down stadium
and the old pitch are kept in `art_source/legacy/field/`.

### How much of it you see — `camera_wide_ground`

The camera used to be fenced to the old play area, so nothing outside the
zones but a thin strip ever showed. It now has two rectangles: the zones
(where players stand, unchanged) and the ground (what it may show). The
wide shot — the draft, the whistle, full time — shows the whole village at
`camera_wide_ground` 1; 0 is the old framing. During play the camera is as
close as before, so the players are the same size.

### Words over the village — a see-through black plate

With the village round the pitch, words straight on the art could not be
read. **Every word in the match now sits on a see-through black plate**: the
score, the clock, the keeper's name and odds, the build stamp, the
announcements and the zone map (Z). Words already on a panel or a button,
and the players' name plates, keep their own backdrop. Two rows in
Tuning.csv: `text_backdrop_alpha` (how dark, 0 = off) and
`text_backdrop_pad` (how far it reaches past the words). The code is one
rule, `src/ui/text_backdrop.gd`, so a label added later gets it too.

### The base town map — `data/BaseTown.csv`

The base is the valley the town stands in, seen from a hill like a 1990s
comic album panorama (round AN, take 2, after Anthony's two example maps):
sky and far fields, the river with its stone bridge and jetty, cobbled lanes,
open meadow and **the football pitch in the middle**. There are **no
buildings and no plots**: the buildings come later, large, and each building
picture will itself be the button.

One row per PixelLab part (`art_source/pixellab/base_town/`): the ground,
the pitch (cut from the ground with `Crop`), two clouds, two boats, the
maypole, firs and two big front trees. `X`, `Y` are the top-left corner in
screen pixels (1920 x 1080); `Scale` is a whole number (the ground is
640 x 360 drawn x3; far things x1, near things x2 or x3); `Flip h` mirrors;
`Crop` (`x,y,width,height`) cuts a piece out of a bigger picture onto its own
layer. Then:

```
~/.venvs/sturmball/bin/python tools/make_base_town.py
```

fuses the layers into `assets/base/background.png` and writes
`art_source/aseprite/base_town.aseprite` with **every part on its own layer**,
for editing in Aseprite.

**The buildings are pictures on the map, and the picture is the button.**
Buildings.csv `Map Art` names a picture in `assets/base/map/` (PixelLab, the
same bird's-eye view as the map); `Map Size` is how big it is drawn,
`WIDTHxHEIGHT` (blank = its own size x2). Hovering brightens it, a locked
building is drawn dark, and its name sits under it on a see-through plate.
`X`, `Y` are still the centre. **Only the drawn pixels take a click**
(`src/ui/map_building.gd`): the see-through corners of a picture let the
click through, so two buildings side by side never open each other. A building with no `Map Art` keeps the old
plaque until its picture is made. The Brewery, the Pub, the Club House and
the Training Ground are the large ones; the Dorms (320 x 192), the Trophy
Room (a Garmisch hut, 192 x 160) and the Traveling Tavern (a wagon pub,
256 x 192, renamed from the Traveling Brewer) are small (round AN, 160 x 128 PixelLab pictures drawn at 640 x 512). A building with
its own picture may reach the very edges of the screen; the plaques still
keep clear of the top buttons and the bottom line. Each building's source is in `art_source/pixellab/base_town/buildings/`. `base_map_shade` in
Tuning.csv darkens the map (0 = full colour). Team Build and Achievements are
not on the map (Anthony, round AN): Team Build opens from **Your teams**, and
Achievements is a button in the top row. The first, top-down try is in
`art_source/legacy/base/round_an_try1/`; the old yard in `art_source/legacy/base/`.

**Every building is on a path.** The ground's own roads reach the Pub, the
Training Ground, the Dorms and the Club House; the `path_trophy` and
`footbridge` rows of BaseTown.csv add a cobbled path past the Trophy Room and
a stone footbridge over the river to the road with the Brewery and the
Traveling Tavern.

**The top-row doors are flag banners, and every banner is the same banner**
(round AN): one blank PixelLab cloth (`art_source/pixellab/banners/cloth.png`)
on one wooden rod (`rod.png`); only the emblem
(`art_source/pixellab/banners/emblems/<name>.png`) and the name differ.
`tools/make_banners.py` puts them together into `assets/ui/banners/<name>.png`
(drawn 1:1) and an `.aseprite` with cloth, emblem and rod as three layers in
`art_source/aseprite/banners/`. The name is stitched on by the game
(`MenuSupport.banner_button`) in cream thread inside the border; the thread
shrinks until the longest word fits, and every banner then uses the smallest
size, so all seven names are the same size. A door whose banner is missing
falls back to the old button. The seven banners are laid out as the released
game shows them; **Dev is not a banner** - it is a small button in the
bottom-left corner while we test, and `show_dev_tools` in Tuning.csv hides it.
The first banners (each its own cloth) are in `art_source/legacy/banners_first/`.

**Sounds** (round AN): pointing at a banner plays `banner_flutter` (a flag
folding in the wind). **Clicking** a building plays its Buildings.csv `Sound`
and then its `Door Sound` (`door_open`, a wooden door creaking open)
`base_door_sound_delay` seconds later (Tuning.csv). The building sounds: `bld_brewery` bubbling, `bld_pub` cheering,
`bld_club_house`, `bld_dorms` snoring, `bld_training`, `bld_trophy`,
`bld_tavern`. Made with Ludo; the originals are in `art_source/ludo/base_sounds/`.

**Name Offset** in Buildings.csv (`x,y` in screen pixels) moves a building's
name off the bottom middle of its picture, e.g. the Club House's, so the
Trophy Room hut in front of it keeps its own name.

**Visitors greet you**: Visitors.csv `Sound` is played when you click them -
the Brewer's grunting "Servus" (`visitor_brewer`), Heatwave's cocky "Hah!"
(`visitor_heatwave`). The Traveling Tavern's door sound is `wagon_creak`.

**Visitors stand at a door** — `data/BaseSpots.csv`, one row per door: `X`,
`Y` are the centre of the visitor's card, `Building` the Buildings.csv ID
(the door is skipped while that building is not on the map). Each time the
base opens every visitor picks a free door at random. A visitor with a
`Building` in Visitors.csv only uses that building's doors (the Brewer stands
at the Brewery); blank = any door. No rows = they stand at their own `X`, `Y`
in Visitors.csv as before.

### The layers

| Layer | | |
|---|---|---|
| `background` | behind the grass | the village. Parallax `0` so it stays next to the grass |
| `crowd` | between the village and the grass | the Full House fans |
| `pitch` | **the playing surface** | grass and lines; see-through round the outside |
| `lights` | over the top of everything | `Tint` is multiplied over it, so a warm colour is floodlights and a cold one is a night game |

A row with no `Image` draws nothing. A row whose `Requires` fails is not
drawn either — the same condition language as everywhere else.

## 8b2. The look — Marcinelle, in pixels

> *"1970's-1990's european comic style reminiscent of Asterix & Obelix,
> Motomania, Smart & Clever, Kleiner Arschloch. I believe this art style is
> called MARCINELLE SCHOOL COMICS. The entire theme: Bavarian mythological
> and Oktoberfest brew drinking while playing soccer."*

### The honest problem, and the answer

Marcinelle is **brush-and-ink comic art**. This game is **pixel art** — 96×96
nine-slice chrome, 128×64 sprite cells, nearest-neighbour filtering
everywhere. Those are two different media, and pretending otherwise would
have meant rebuilding every asset in the project.

So: **keep the medium and borrow the language.** Five things carry over, and
all five survive at 96 pixels:

| | |
|---|---|
| **heavy black outline** | 1px, pure black, closed all the way round |
| **flat fill** | two or three tones a shape. No gradients, ever |
| **exaggerated silhouette** | big hands, small heads, round bellies |
| **a warm limited palette** | oak, brass, cream, **one** hot accent |
| **hand-wobble** | lines that are not perfectly straight |

### One hot colour, and only one

```
   colour accent       #f2b33d   BEER GOLD
```

In Marcinelle the eye is led by **one** hot colour against a warm neutral
ground — Uderzo does it with the red of the trousers, Franquin with the
yellow of the Marsupilami. So: everything you want pressed is the accent and
**nothing else is**. The four tier colours are deliberately muted, because a
tier colour is a label and four more bright colours would fight the one that
matters.

```
   colour background   #19110a   stained oak, almost black
   colour panel        #3a2415   walnut
   colour text         #f3e8d4   cream enamel — NOT white
   colour attack       #dd6f24   burnt orange, late autumn
   colour defend       #5a93cc   bavarian sky blue
```

**The text is cream, not white.** Pure white on this ground is a hole, and
the comics this is drawn from print on paper, never on light.

### `data/ArtOrders.csv` — the work order

Fourteen assets, in the order to make them, each with the exact PixelLab
tool, the exact prompt, the exact size and what to do with the result.

**Order 1 is the panel, and nothing else starts until it is right.** Every
box in the game is drawn from it, and the result is then passed as
`style_image` to all thirteen below — that is what makes fourteen separate
generations read as one game rather than fourteen.

**Since round AH the file has a `Phase` column** and 21 orders — the art
phases you asked for:

| Phase | what | orders |
|---|---|---|
| **pass 1** | the chrome: panel, window, button ×3, slot, bars — **done** | 1–7 |
| **A1** | **the pitch first**, then the title wallpaper and the base yard | 11, 8, 10 |
| **A2** | the referee, the twelve emblems | 12, 13 |
| **A3** | menu plaques, a display font | 9, 14 |
| **A4** | the units: each class's three sets, the Basic Team (the recruits wear it), the twelve Stars | 15–20 |
| **A5** | the icons in `data/ICONS_WANTED.csv` | 21 |

**`python3 tools/art_status.py`** checks every file these name — and every
`Artwork` the cards name — against `assets/`, and writes
`guides/ART_STATUS.md`: done, missing, and the next order to make. As of
round AH, 30 of the 31 unit Artwork files are missing (the units are
stand-ins), which is why A4 exists.

**PixelLab runs through your computer.** Its tools reach this session only
while the chat is linked to your computer through the desktop app.

### Round X — orders 1 to 7 are done

PixelLab's UI tool does not hand back one 96 x 96 tile. It hands back a
**whole sheet of panels** in the style you asked for. So three new columns
in ArtOrders.csv say how each game file is cut from a sheet:

| column | |
|---|---|
| `Status` | what happened to the order |
| `Sheet` | the PNG in `art_source/pixellab/` it is cut from |
| `Cut` | `x y width height corner` — which piece, and how big its corners are |
| `Finish` | what is done to it afterwards (below) |

```
python3 tools/cut_chrome.py
```

writes all eight chrome files from those three columns. **That is the loop
from now on:** regenerate a sheet in PixelLab, save it over the old one in
`art_source/pixellab/`, fix its `Cut` if the piece moved, run the script.
(`art_source/` has a `.gdignore`, so Godot never imports the big sheets.)

**What each order needed, and why:**

| order | finish | why |
|---|---|---|
| panel | `light` | **every screen tints the panel with its own colour, and tinting multiplies** — dark walnut came out nearly black. Black ink is kept; wood and brass are lifted so each screen's colour lands. The *mid-size* plaque was used, because the big ornate one's gold flourish ran 60px into each corner, past the 28px slice |
| window | `dark-centre` | PixelLab drew the opening cream; it is painted the window colour |
| button | `plain-button` | the big plaque at the top of the sheet; its scrollwork is cut at the 26px corner |
| hover, pressed | `lit:button`, `pressed:button` | **not generated** — made from the button itself, so they are certainly the same plaque |
| slot | `reduce` | the UI tool *painted* the beer mat rather than pixelling it, so it is shrunk to 96 x 96 and snapped to the palette. A Pixel-model retry lost the lozenges |
| bars | `bar-back`, `bar-fill` | it drew a lovely rack of steins, but a rounded rack cut to 32 x 32 became a blob — so both tiles are built from its colours: an oak track, and foam over amber |

**`tools/make_chrome.py` now refuses to run** while the PixelLab art is in,
so it can never paint the placeholders over it by accident.
`python3 tools/make_chrome.py --placeholders` brings them back on purpose.

### Two numbers in that file worth knowing

**The wallpaper is 480 × 270.** That is exactly a quarter of 1920 × 1080, so
scaling up lands on whole pixels and stays sharp. The game already draws
everything nearest-neighbour, so it reads as deliberate rather than blurry.

**The pitch is the biggest single win available.** The one in the project is
1000 × 667 — the wrong shape, stretched into a 16:9 box and blown up 2.56×.
`Stadium.csv` asks for 2560 × 1440, and section 8b has where the white lines
must sit inside it.

---

## 8c. `data/Theme.csv` — the skin

> *"Right now people can tell it is an AI game. I need to be able to customise
> the windows, the HUD, the lines, with images. Allow me to change the image
> through CSV."*

This is the file that changes how the game looks. **One row reaches every
screen at once.**

### Why one file can do that

Every box the game draws — a card face, a tile, a dialog, the strip above the
card row, the keeper's number, a button, the celebration window — is drawn by
**one function**, `MenuSupport.panel_style()`. Theme.csv sits in front of it.
Change the `panel` row and you have changed all of them without opening a
single screen.

And `ThemeBook.dress()` builds a real Godot `Theme` from the same rows and
sets it on the root window, so **every Button, Panel, Label and ProgressBar
in every `.tscn` in the project** picks it up too — including ones laid out
by hand in the editor that never call MenuSupport at all. That is the half
that makes this one file rather than thirty-six.

### A row

| Column | |
|---|---|
| `Element` | what kind of thing this is: `panel`, `button`, `window`, `slot`, `tab`, `bar_back`, `bar_fill`, `tooltip`, `divider`, and the three font rows `heading`, `body`, `small` |
| `State` | blank, `hover`, `pressed`, `disabled`, `focus`, `selected` |
| `Image` | a 9-slice PNG in `assets/ui/`. Blank = a flat colour |
| `Tint` | `no` draws your image exactly as you drew it. See below |
| `Slice` | how far in from the edge the corners are |
| `Fill` | the colour, when there is no image |
| `Border`, `Border Width` | the edge |
| `Corner` | how round the corners are |
| `Pad X`, `Pad Y` | the space between the edge and the words |
| `Font`, `Size`, `Text Colour` | a `.ttf` in `assets/fonts/`, and the words |
| `Repeat` | **round X.** `tile` REPEATS the four edges instead of stretching them — for a border with a pattern in it, like the beer mat's lozenges, which a stretch smears into stripes. Blank = stretch |

A state with no row of its own falls back to that element's ordinary row, and
an element with no row at all falls back to `panel`. So you can skin the
whole game with one row and then add detail where you want it.

### Nine-slice, which is the whole point

A window is not one picture. If it were, a wide window would be a stretched
picture with oval corners. So an image is cut into nine: four corners that
never stretch, four edges that stretch one way, and a middle that stretches
both. `Slice` is how far in the cuts are.

```
   Slice 14, on a 48 x 48 image:

     +----+--------+----+     the 14px corners keep their shape
     | 14 |   20   | 14 |     the top and bottom edges stretch sideways
     +----+--------+----+     the left and right stretch up and down
     |    |        |    |     the middle stretches both ways
     +----+--------+----+
```

**One 48 × 48 PNG draws every window in the game, at every size.**

### Tint — read this before you draw anything

By default the image is **tinted** by the colour the screen asked for. Every
screen already passes a colour — a blue panel here, a warm one there, a
locked grey one over there — and those calls are not going away. So one light
grey PNG arrives in each of them wearing that screen's own colour.

**The catch, and it will bite you the first afternoon:** tinting
*multiplies*. A panel colour of `#23262f` is dark, so whatever you drew comes
out darker, and the difference between the lightest and darkest parts of your
image survives only in proportion. **Draw it light and desaturated, and keep
the shape in the alpha rather than in the brightness.**

`Tint` = `no` hands the image over untouched, exactly as you drew it. You
then need one image per look instead of one for all of them.

| | Tint blank (the default) | Tint `no` |
|---|---|---|
| how many images | **one**, for every colour in the game | one per look |
| what to draw | light, desaturated, shape in the alpha | the finished thing |
| when | you want a consistent material across the game | you are drawing a specific frame |

### What ships in `assets/ui/`

**The game now comes wearing a skin.** `beerhall_*` is a Bavarian /
Oktoberfest / late-autumn set: stained oak, brass frames with corner studs,
cream beer-mat tiles with the blue-and-white lozenge, and a bar that is a
glass of beer with a head on it. Theme.csv points at it out of the box.

| | |
|---|---|
| `beerhall_panel` | light oak, **tintable** — it is the `panel` row, so it wears whatever colour each screen asks for |
| `beerhall_window`, `beerhall_button` and its two states, `beerhall_slot`, `beerhall_bar_fill`, `beerhall_bar_back` | drawn finished, `Tint` = `no` |

The three neutral ones from the round before — `panel_soft`, `window_frame`,
`button_face` — are still there if you would rather start from grey.

#### Drawing your own: the one rule

**Detail survives only where the image does not stretch.**

```
   corners  (Slice x Slice)  never stretch      -> ALL the detail goes here
   top/bottom                stretch SIDEWAYS   -> only horizontal lines survive
   left/right                stretch UP/DOWN    -> only vertical lines survive
   the middle                stretches both     -> keep it near-uniform
```

I learned this by ignoring it. The first beer-hall panel had wood grain
running through the middle, and stretched across a 700-pixel tile each grain
line became a 40-pixel bar. The grain lives in the corners now, the moulding
runs round the edges as straight lines, and the middle is a plain gradient.

### Try it in one cell

Put `panel_soft` in the `Image` column of the `panel` row, run the game, and
every box in it changes. Put it back to blank and they change back.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/theme_shot.gd
```

photographs the same screen twice — as your file is written, and with those
three images forced in — so you can look at both before you commit to
anything. It changes nothing on disk.

### Fonts

Drop a `.ttf`, `.otf` or `.fnt` into `assets/fonts/` and name it in the `Font` column
of the `heading`, `body` or `small` row. Nothing else to do.

**Round AN, take 2 (your answer: less pixelated when large, clean and crisp):
the font is now `SturmballComicHD`.** It has the same PixelLab letters, smoothed to
four times the detail by `tools/make_font.py`. The steps on curves and slopes are
rounded off, so big words are clean and small words stay sharp. It is on every
text row of `Theme.csv`. The plain pixel version, `SturmballComic`, is
still there, and you can put it in a Font cell to compare.

**Round AN, first take: one font for all text, `SturmballComic`.** A PixelLab comic pixel
font (`create_font`), with Ä Ö Ü ä ö ü ß added by `tools/make_font.py`, because
PixelLab's sheet has no umlauts. It is on `heading`, `body` and `small`, and
also on the words painted straight onto the pitch.

- It is drawn 16 pixels high, so **16, 32 and 48 are the crispest sizes**.
  Any other size still works and is a little softer.
- Letters it does not have (& # @) come from the **`fallback`** row's font
  (Schola). Symbols such as ★ and ▶ come from the computer's own fonts.
- To change a letter: open `art_source/pixellab/font/sturmball_comic_atlas.png`,
  redraw it, then run `~/.venvs/sturmball/bin/python tools/make_font.py`.
- The fonts below are still here, and are spares now.

**Three ship with the game**, and they are the single biggest step away from
"you can tell it is an AI game" — the default Godot font is the most
recognisable thing on a screen.

| file | what it is | where it is used |
|---|---|---|
| `Bonum-Bold.otf` | TeX Gyre Bonum — a Bookman. Heavy, wide, warm; the shape of a beer label | every `heading` |
| `Bonum-Regular.otf` | the same at normal weight | spare |
| `Schola-Regular.otf` | TeX Gyre Schola — a Century Schoolbook. Warm, sturdy, made to be read | `body` and `small` |

Both families are under the **GUST Font License**, a free licence that allows
redistribution; the licence text ships beside them in `assets/fonts/`.

> **If you want a Fraktur**, put it on `heading` **only**. Blackletter at 13
> points is unreadable, and a whole interface in it looks like a costume
> rather than a design. The pairing that works is a Fraktur title over a warm
> serif body — which is exactly what the two rows are for.

### The palette

Rows whose `Element` starts with `colour ` set the base palette; only their
`Fill` is read.

```
colour accent      colour background   colour panel      colour slot_empty
colour locked      colour text         colour text_dim
colour attack      colour defend
colour tier_1      colour tier_2       colour tier_3     colour tier_4
```

`attack` and `defend` are the two that carry meaning rather than taste: the
strip above the card row and the ATK / DEF tags on a Star's abilities both
read them, and a player learns them in the draft.

**The Colour tab of Settings still wins.** A deuteranopia or high-contrast
palette is a *need*, not a preference, and a designer's palette must not be
able to take it away. Theme.csv is the shipped look; the accessibility
palettes paint over it.

### Nothing breaks while it is empty

A missing file, a missing image, a colour it cannot read: every one of them
falls back to what the game looked like before this existed. **You can draw
one button today and the rest next month.**

```
godot --headless --script res://tools/theme_check.gd
```

lists every element, what it is drawn from, whether that file exists, every
palette colour and whether the game reads that name — and what is sitting in
`assets/ui/` that no row is using.

---

## 9. `data/Tuning.csv` — 437 numbers

Three columns: `Key`, `Value`, `What it does`. Every number the game uses that
is not content lives here. Groups, by prefix:

| Prefix | Rows | What |
|---|---|---|
| `adventure_` | 54 | the run, the fight, the lane, the windows, the timings |
| `juice_` | 5 | how much shake, flash and slow-motion the whole game gets |
| `card_` | 6 | card sizes |
| `friendly_` | 3 | how a scratch opponent is matched to you |
| everything else | ~184 | the match, the pitch, the menus, the economy |

Rows worth knowing about:

```
juice_scale             0 kills every shake and flash. The row to put in
                        Settings for people who dislike screen shake
juice_slowmo            false stops the slow-motion dips only
juice_slowmo_depth      0.35 = a third speed. 1.0 = no dip
juice_flash_strength    how bright a full-screen flash is. 0 = none

adventure_trait_bar     false hides the row of icons (the pile still works)
adventure_enemy_combos  false and the enemies get no combos at all
adventure_stretcher     false and the fallen are not carried off
adventure_buildup       false skips both build-up windows entirely

adventure_bar_height / adventure_bar_inset      the COMBAT bar
adventure_choice_top / adventure_choice_bottom  the card window
adventure_log_top                               the WHAT HAPPENED panel
```

A talent can edit any of these at runtime with `count:tune_<key>+<n>`.

---

## 10. Feel — `data/Juice.csv`

**No feel is typed into a script.** The code says *what happened*; this
spreadsheet decides what that looks and sounds like.

| Column | |
|---|---|
| `When` | the moment. Fourteen of them, listed below |
| `Who` | `player` / `enemy` / `screen` / `ball` — **what** gets shaken |
| `Shake` | how far it jumps, in pixels |
| `Shake Scale` | **how much harder a big hit shakes.** See below |
| `Flash` / `Flash Colour` | seconds of a colour wash, and the colour |
| `Pop` / `Squash` | scale it snaps to and back from |
| `Sound` | a row of Audio.csv, or just a file name in `assets/audio/` |
| `Slowmo` | seconds the whole game runs slow. Use sparingly |

The fourteen moments:

```
ball_received  ball_kicked   enemy_hit     enemy_died   player_hurt
player_exhausted             player_healed combo_fired  shot_struck
enemy_windup   goal_scored   play_maker    star_switch  coin_exact
```

**Two rows may share a `When` and both fire.** That is how `enemy_hit` shakes
the enemy *and* the screen from one event, with different settings for each.

> **`Flash` is currently 0 on every Adventure moment.** The full-screen wash
> was too bright over the scrolling pitch and it arrived at exactly the moment
> you were reading a number, so it was turned off there rather than dimmed.
> The number each row used to carry is written in its `Notes` cell, so putting
> it back is a copy and paste. The league rows are untouched.
Several rows of one moment asking for slow-motion make **one** dip, the
longest asked for — they cannot stack.

### `Shake Scale`, which is the interesting column

`Shake` is the shake for an *average* hit. `Shake Scale` decides how much the
size of the hit is allowed to move that number.

* `0` — every hit shakes the same
* `0.9` — a big hit shakes noticeably harder
* `1.4` — small hits barely register, big ones are an event

The game works out "average" by itself, from the hits you actually land in
that fight, so it stays true whether your side hits for 4 or 40. Pin it with
`juice_average_hit` if you would rather.

### `data/Audio.csv` — and the four things that were wrong with it

**Every screen announces itself.** `screen_opened` used to be fired by
`ScenePaths.go_to()`, which is every screen change in the game *except the
first* — the main menu is the project's main scene and is simply there when
the window opens. So the menu had no music until you walked to the tutorial
and back, which did go through `go_to()`. It is fired from
`MenuEscape.install()` now, which every screen already calls, so a screen
says what it is the moment it is built however it was reached.

**A screen with no music is quiet.** A looping track holds its bus until
something else claims it. The base had a row; the team shelf, the bounty
board and the builder did not — so walking out of the base handed the base
theme a lease on the Music bus for the rest of the session. A screen opening
now RECLAIMS the bus: if no looping row claimed it, whatever was playing is
faded out. **That is the cut between screens.**

> To carry a track across a screen on purpose, give that screen a row naming
> the same `Sound`. The loop sees the same cue and leaves it alone, so there
> is no gap at all.

**The pitch is a screen too.** The match has its own pause menu and never
called `MenuEscape.install()`, so `screen=match` could never match and the
crowd loop never played. It announces itself now.

**And the whistle goes at the kick-off.** `kickoff_whistle` hung on
`match_started`, which fires while the scene is still assembling — the
referee blew up over the loading screen. There is a `kick_off` moment now,
after the countdown, as play begins.

| Tuning row | |
|---|---|
| `music_follows_screen` | `false` goes back to a track holding its bus until something takes it |
| `music_fade_out_seconds` | how long the old track takes to go. `1.0`. Short is a cut, long is a dissolve |

> `tools/audio_check.gd` prints every row in Audio.csv and whether its file
> actually exists, which rows answer each moment, and the duel result worked
> through all four ways round. **A row whose file is missing is silent, and
> silence is indistinguishable from a bug** — that is what it is for.

### `data/Audio.csv`

`ID`, `When`, `Match`, `Sound`, `Bus`, `Loop`, `Volume`, `Fade`, `Requires`.

`When` is a game event. **A blank `When` is legal and means "nothing fires
this by itself; something asks for it by name"** — which is how Juice.csv
sounds work. Buses are `Music`, `Effects`, `Master`, and obey the Sound tab of
Settings.

A name Audio.csv has never heard of is looked for as a **file in
`assets/audio/`**, so you can drop `whump.wav` in, type `whump` in a Sound
column, and hear it without writing a row.

`SOUNDS_WANTED.csv` and `ICONS_WANTED.csv` are the shopping lists: every
sound and icon the spreadsheets name, with a line on what it should be. They
are for you and your artists; nothing loads them.

---

## 11. The base — nine doors, and a window behind each one

> *"Each of these should have a new window open (not a new whole scene cut
> from the base) with each of the content presented that way."*

Clicking the Brewery no longer takes the base away and puts a Brewery in its
place. **The base stays where it is, dims, and the screen opens on top of
it.** Close the window and you are already home — no loading, no camera jump,
and the building you just used is still under your cursor.

### The nine

| building | what it is |
|---|---|
| **Achievements** | the root. Everything is unlocked here first. **The only door with no `Requires`** — a game whose unlock board is itself locked has nothing to aim at |
| **Team Build** *(was the Talent Tree, round Y)* | three tabs: **Star Hall** (place your three Stars), **Your Teams** (create and edit sides) and **Talents** (the old talent tree, still behind `unlocked:Talent Tree`). **The Pub and every match wait on it** — see section 11e |
| **Club House** | exhaustion and recovery. A player's `P:x` is how many fixtures they need |
| **Dorms** | beds — how many players you may keep at all |
| **Trophy Room** | what you have won |
| **Training Ground** | Ausbildung, or one of the five games that automate a Brewery section |
| **Pub** | ten seats, ten drinks. Whoever is not in the room plays as a basic unit |
| **Brewery** | six sections and a yard |
| **The Traveling Brewer** | sells one thing at a time, dear |

**Four buildings were removed** — the Forge, the Still, the Reed Press and
the Cold Cellar — along with the Tap Room and the Gate. They were **worked
examples of the recipe pattern**, not rooms. That pattern has not gone
anywhere: `Requires: count:reed>=20` with `Action: count:reed-20;count:coins+60`
is still a complete trade with no code, and the Buildings.csv note says so.
The one thing they granted that something still needs — **Iron Boots**, which
the Iron Shod talent waits on — is now a row of the Traveling Brewer's cart.

### `window:` and `goto:`

```
   Action: window:brewery     opens it OVER the base
   Action: goto:brewery       throws the base away and opens it full-screen
```

Both name the **same screen** through the same ScenePaths word. `goto:` is
still what a Progression row should use when the base is not already open.

Both are **deferred** actions — see *"The four that need a screen"* in
section 4. `window` was missing from that list for a while, which is why
clicking a building used to print its description along the bottom and open
nothing at all. That is fixed, and an unknown action kind is now loud.

### No footer

There used to be a line along the bottom of the base listing every unlock you
had ever earned. It is **gone**. It was a *developer's* line — useful while
wiring content, and to a player a wall of small text under their base saying
things they already know. **The Achievements building says all of it
properly**, and says what is still missing as well.

If you want it back for a minute while writing content, the same information
is one line: `print(state.unlocked_names())`.

A **problem in a spreadsheet** still has to be said — it just does not go
across the bottom of the screen any more. It prints to the **Output panel**,
where every other loader's complaints already go, and **once**, when the base
opens, rather than on every rebuild.

### How a screen becomes a window

It is not rewritten. The **same scene file** is instantiated inside the
frame, with one flag set on it first:

```gdscript
content.set_meta("windowed", true)
```

and every screen asks `MenuSupport.in_a_window(self)` in its `_ready()`.
When the answer is yes it skips three things and nothing else:

```
   its own full-screen background    the window has one
   its own "Back to the base"        the window has a ✕
   MenuEscape.install()              the window handles Escape
```

That is the whole contract. Every one of these screens still works
standalone, and there is **one copy of each** rather than a windowed one and
a full-screen one drifting apart.

**One window at a time.** Opening a second closes the first, and the dim
behind it eats clicks — without that you can press a building *through* the
window and open a second one on top.

### Visitors go in the gaps

> *"The dialogue option for people to come by will still be possible, but
> not in the middle of the screen — rather on any empty space, and please do
> not layer them."*

A visitor's `X` and `Y` are a **preference** now. Buildings are placed first
and keep their spots; then each visitor is fitted into the nearest **free**
place, searching outward in rings so somebody written at `0.5,0.5` still
ends up near the middle rather than in a corner. If the yard is genuinely
full they are **not drawn at all** — a visitor you cannot read is worse than
a visitor who is not there, and the Output panel says who is waiting outside.

> **A bug that fell out of this.** `Seasons.csv` also has ID, Name and Story
> columns, so the base loader had been treating every season as a person and
> drawing "The County League" standing in the yard. It was invisible until
> the visitors were told not to overlap anything and started reporting that
> there was no room. **A visitors file is now recognised by its `Portrait` or
> `Once` column** — things only a person has.

### `data/Dorms.csv`

| column | |
|---|---|
| `Beds` | **the TOTAL**, not what this row adds. Buying the Long House replaces the Lean-To rather than stacking on it, so reading down the column tells you the whole story of your squad size |
| `Price` · `Currency` | from `Currencies.csv` |
| `Requires` | the ordinary condition language |

**The first row has to be free.** A new game cannot buy its first bed, and
the checker says so if the cheapest dorm costs anything.

### `data/Trophies.csv`

A trophy is a **name and a condition**. It does not have to come from a
competition — `count:matches_won>=3` is as good a trophy as a cup final, and
that is the row to copy when you want something on the shelf early. An empty
case is a room nobody goes back to.

### `data/Training.csv`

`Kind` splits the screen in two. **`ausbildung`** trains a number for the
whole side. **`minigame`** is one of the five that automate a Brewery
section, and its `Section` column names a row of `BrewerySections.csv`.

**What a mini-game gives today is a vat** — `count:batches_<section>+1` —
which is the foundation the played game will sit on top of later. Nothing on
that screen changes when the game itself arrives; it slots in between
pressing the button and the work being done.

### The Dorms are where everybody rests (round AN)

Every tired player sleeps in the Dorms, whatever tired them out. The Dorms
window lists **who is in bed, why, and how many fixtures to go**, then the
beds you can buy. `data/Resting.csv` says what sends a player there:

| ID | when | out of the box |
|---|---|---|
| `match` | everybody who has played his last round (`Plays` in `Recovery.csv`) | by power (`Recovery.csv`) |
| `adventure` | everybody who set off on an Adventure, however it ended | by power |
| `adventure_down` | **on top of** `adventure`, for a player knocked out on the run | +1 fixture |
| `brewer` | a **brewer** after a shift at a Brewery machine (see below) | 1 fixture |
| `brew` | **on top of** `match`, for a player who played on a one-match Pub brew. **Switched off** (`On` = false) since Anthony said Brew Players are the brewers | +1 fixture |

| column | |
|---|---|
| `On` | `false` and that row never sends anybody to bed |
| `Turns` | blank = by power from `Recovery.csv`; a number sets it outright |
| `Extra` | added on top |
| `Wakes Others` | `true` = this counts as a fixture, so everybody already in bed is one fixture nearer fit. A match and an Adventure both do |

`rest_less` in `Tuning.csv` takes fixtures off every rest (never below one);
the **Feather Beds** upgrade raises it. **`recovery` in `Tuning.csv` is the
master switch, and it is ON** (Anthony, 8 Oct).

**The rest day.** `tools/recovery_check.gd` still says the classes are too
thin: with three players a tier, one match can put so many in bed that you
can field neither a match nor an Adventure, and then nothing passes a
fixture. So the Dorms have a **Rest day** button: everybody in bed is one
fixture nearer fit. `rest_day_cost` in `Tuning.csv` is its price in coins
(0 = free, below 0 hides it).

**The Dev screen** (the Dev button, bottom left of the base) has a PLAYERS
row: a **Wake** button for everybody in the Dorms, **Wake everybody**, and
**Sign a new player** (pick a Tier and a power; free, random name and look).

`tools/dorms_shot.gd` takes a picture of the Dorms, the Club House, the
Training Ground, the Brewery and the Dev screen with a few players in bed.

### The brewers (round AN)

> *"Brew Players are trained at the training hall to be only brewers. They
> have the same number given to them as a power but that is their efficiency
> and % of success when they work the machines."*

- **Training them.** `Training.csv` has a row with `Kind` = `brewer` (The
  Brewer's Apprenticeship, 40 coins). The Training Ground lists your players
  under BREWERS with a Train button. A brewer **never plays again**: no
  match, no Adventure, no Pub.
- **Efficiency.** His power is his efficiency. `data/Brewers.csv` turns it
  into his % of success at a machine (0 = 55%, 5 = 100%). The `none` row is
  the chance when nobody is free (40%).
- **Working.** When you work a Brewery machine, the fittest brewer with the
  highest efficiency does it. A batch that fails uses up what it took and
  makes nothing. Then he rests in the Dorms (`Resting.csv` row `brewer`).
- `brewery_brewers` in `Tuning.csv` = false turns all of it off: every batch
  works, as before.

### Match Players, Adventure Players and Brewers (round AN)

> *"The player can train new player units as Adventure Player, Match Player
> and Brewer Player. There is also a separate Adventure Team and Match
> Team."*

Every one of your players has **one role**, and the Training Ground is where
you choose it. Under YOUR PLAYERS each player has a button for every role he
could switch to.

| Role | Training.csv `Kind` | Plays in | Cost |
| --- | --- | --- | --- |
| Match Player | `match_player` | your **Match Teams** | 20 coins |
| Adventure Player | `adventure_player` | your **Adventure Teams** | 20 coins |
| Brewer | `brewer` | no team, works the Brewery machines | 40 coins |
| Not trained yet | | no team | |
| *Retraining* | `retrain` (Quereinsteiger) | the new role | 200 coins |

- **Two kinds of team.** A team is a Match Team or an Adventure Team. The
  button next to the team's name in the builder switches it. A Match Team
  only lists your Match Players, an Adventure Team only your Adventure
  Players. The plain CSV cards are nobody's players and play for both.
- **Which team goes out.** A match shows only your Match Teams; an Adventure
  run (MatchModes.csv `Scene` = adventure) shows only your Adventure Teams.
  CREATE TEAM from there makes the right kind.
- **New players.** A player signed at the Club House arrives **untrained**
  (`new_player_role`). The starting team's **Role** column in
  `StartingTeam.csv` says what each starter arrives as: four Adventure
  Players (the middle Power of each Tier) and eight Match Players, so a
  fresh game can go on an Adventure straight away. A blank Role, and players
  signed on the Dev screen, use `starting_team_role` (match). A save made
  before roles existed counts everybody as a Match Player
  (`player_role_default`).
- **A role is for good** (`role_lock`). An untrained player is trained once,
  at the role's price. After that his row says *Role locked* and has no
  buttons.
- **Quereinsteiger.** The Quereinsteiger achievement (`Achievements.csv`,
  placeholder: play twenty matches) unlocks *Quereinsteiger*, which the
  Training.csv row with `Kind` = `retrain` needs. Then the Training Ground
  shows a QUEREINSTEIGER heading and every trained player gets *Retrain*
  buttons into any other role, for that row's Cost (200 coins) instead of
  the role's own price. A Brewer can take his apron off this way too.
  `role_lock` = false switches freely at the role's price, as before.

```
Achievements.csv  quereinsteiger  ->  Unlocks: Quereinsteiger
Training.csv      quereinsteiger  ->  Kind retrain, Needs unlocked:Quereinsteiger, 200 coins
```
- `player_roles` in `Tuning.csv` = false turns roles off: every team takes
  everybody, as before.

### Keys (round AN)

> *"For the machines and to get into the buildings, you need to buy the
> keys."*

Every building except the Club House, and every Brewery machine, needs its
**key**. An achievement still unlocks the building, but that only puts its
key on sale at the Club House:

```
Achievements.csv   first_win  ->  Unlocks: Dorms
Upgrades.csv       dorms_key  ->  Kind key, Needs unlocked:Dorms, 30 coins, Effect count:dorms_key+1
Buildings.csv      dorms      ->  Requires unlocked:Dorms;count:dorms_key>=1
Items.csv          dorms_key  ->  Kind key, Tab keys (it shows in the bag)
```

The Club House lists KEYS first, then UPGRADES. A key you already carry
(from an Adventure, a story, the test save) is never sold twice. A locked
building or machine says "the dorms key (buy it at the Club House)" or
"Needs its key". The **Keys tab is back in the bag** (`inventory_tabs`).
The test environment hands you every key.

### The Club House sells upgrades (round AN)

**An achievement only grants the right to buy an upgrade.** Earning it puts
the upgrade on sale; the money is still yours to find. `data/Upgrades.csv`,
one row per upgrade:

| column | |
|---|---|
| `Kind` | `upgrade`, or `key` (see Keys below) |
| `Achievement` | an ID from `Achievements.csv`. Blank = on sale from the start |
| `Needs` | any extra condition, in the usual language |
| `Cost` · `Currency` | from `Currencies.csv` |
| `Effect` | the ordinary effects language. `count:batches_cooling+1` is a vat, `count:tune_<any Tuning row>+n` raises a number, `unlock:x` opens a thing |

Each upgrade is bought **once**. The window shows what is on sale first, then
what is still locked (and which achievement opens it), then what you own.
The Achievements board says, under each achievement, which upgrade it puts
on sale. The recruitment board is still in the Club House, under the
upgrades.

**`second_vat` and `third_vat` changed.** Those two achievements used to hand
the vat over free in their `Reward`; now they put it on sale. To make an
upgrade free again, put its Effect back into the achievement's `Reward`.

### Price everything in seasons

```
godot --headless --script res://tools/rooms_check.gd

  A season of 10 fixtures, half won, pays 225 coins.

  The Lean-To       18 beds   150 coins    0.7 seasons
  The Stone Wing    36 beds   900 coins    4.0 seasons
  The Cellar Watch  minigame  300 coins    1.3 seasons
```

It also checks the thing a spreadsheet cannot: **that every building's Action
names a screen that exists.** A door that leads nowhere looks exactly like a
door that works.

---

## 11b. The Brewery — the chain, and the map

Six sections, each unlocked by an achievement, each turning one thing into
another. The **chain** went in first and the **map** was built on top of it,
which is the order I would take anything of this shape:

> A production chain is a thing you get wrong in the **numbers**, not in the
> pictures. If six bottles from a barrel is the wrong number, no amount of
> drawing the Bottler fixes it, and you will have drawn him twice.

The brewing mini-games arrived in round AN (below, "The brewing mini-games"), and they change nothing here:
a mini-game decides how **well** a section runs; this decides what it costs
and what it gives.

### The map

`src/ui/brewery_screen.tscn`, reached from the Brewery on the base or with
`goto:brewery`. Two windows along the top and a yard underneath.

| | |
|---|---|
| **RESOURCES** | what comes from outside — wheat, water, germs, hops, yeast — and the **tools**, which are needed and not used up |
| **BREWERY MATERIALS** | what the Brewery itself makes: malt, mash, wort, brew, barrel, bottle |

**That split is the `Kind` column and nothing else.** `raw` and `tool` go
left, `made` goes right. Add a resource tomorrow and it appears in the right
window with no edit to any screen.

**The yard is not laid out by hand either.** Every section has an **`X`** and
a **`Y`**, as a fraction of the yard — `0.5,0.5` is the middle. The same two
columns `Buildings.csv` uses. A thin arrow is drawn from each section to the
next in `Order`, because `Order` is the column the whole file turns on and a
list of numbers does not look like an order.

### A locked section names its achievement

Not its unlock. *"Needs Mill"* tells a player nothing they can act on;
**"LOCKED — Clean Sheet · Win a match without conceding"** is a thing to go
and do. Nothing stores that sign: the screen asks `Achievements.csv` who
hands out the name in `Needs`, so moving the grant to a different achievement
changes the sign with no edit anywhere.

### Where raw materials come from

Two rows of `Progression.csv`, and they are the whole supply:

```
harvest       every match, once the Brewery is open   3 wheat, 6 water, 2 germs
harvest_win   and if you won it                       2 hops, 1 yeast
```

Hops and yeast are the two the chain runs out of last, which is what makes a
good season taste different. **Keep the haul small on purpose** — the
Traveling Brewer sells the rest at a premium, and that is Phase 8.

### The cellar, and the vats you unlock

> *"The amount of batches will also be unlockable through achievements. The
> most basic foundation is there free, and everything that would make it
> easier or more can be unlocked later on."*

So every section has a **`Batches`** column — how many jobs it can have
running at once — and that column is what you get for nothing. Everything
above it is earned:

```
   count:batches_cooling+1     in an achievement's Reward, a talent's
                               Effects, a building's Action — anywhere
```

Nothing new had to be invented to say that: it is the counter language the
whole game already speaks, and it works for **any** section, not just the
cellar. `batches_boiling`, `batches_malthouse` — all of them.

There are two worked rows in `Upgrades.csv` (`second_vat`, `third_vat`): the
achievements of the same name put the vats on sale at the Club House (round
AN), rather than handing them over free.
And the measurement that says whether a vat was worth an achievement:

```
godot --headless --script res://tools/brewery_check.gd

  10 fixture(s) produced 24 bottle(s).
  With 1 more vat(s) unlocked: 48 bottle(s).
  With 2 more vat(s) unlocked: 54 bottle(s).
```

**The first extra vat doubles a season. The second adds a quarter of that**,
because by then hops are the limit rather than the cellar — which is the
shape a good unlock should have, and the point at which the Traveling Brewer
becomes the thing to spend on instead.

### The turn, and the opening stock

`BreweryBook.advance_turn()` is called from **the same line in `_full_time()`
that advances the squad's rest**, so there is one answer to "what is a turn":
a fixture. What comes out of the cellar is listed on the what-you-gained
panel.

`Start` is handed out on the first visit and **a flag is left behind**. The
first version only filled a resource whose count was zero, which reads as
"once" and is not: spend your last germ, walk out, walk back in, and it hands
you five more.

### The machines are the buttons (round AN)

Each section is drawn as its machine, which you click to work it, like a
building on the base, with its name on a see-through plate underneath. The
machines are the Steeping Tank, Grain Mill, Lauter Tun, Brew Kettle,
Fermenting Vat and Bottling Machine. Each picture is the **Art** column
(`assets/brewery/brewery_<id>.png`, PixelLab, layered in
`art_source/aseprite/brewery/`). Their size is `Tuning.csv
brewery_machine_size`. A section with no picture falls back to the old panel.

### The brewing mini-games (round AN)

> *"They are extremely simple, just 1-2 actions, like hitting the right
> temperature is a bar that goes back and forth having to hit the right spot
> to heat up, think of very simple flash games that take 5-15 seconds to
> complete."*

Clicking a machine opens its game. **Win it and the batch is made; lose it
and the batch is spoiled** (what it took is gone, nothing is made).

Anthony picked them from the playable mock-ups (8 Oct): "keep the others",
with Keep the fire for the Brew Kettle and the Fermenting Vat as it was.

| Machine | Kind | What you do |
|---|---|---|
| Steeping Tank | `stir` | **Stir the mash**: move the mouse round and round over the tank. Stop and it clumps |
| Grain Mill | `rhythm` | **Crank rhythm**: left, right, left, right (arrows, A/D, or click each half). The same side twice jams it |
| Lauter Tun | `colour` | **Watch the colour**: hold the tap open while the wort runs clear, let go when it clouds |
| Brew Kettle | `fire` | **Keep the fire**: the heat drops, click to pump the bellows and keep the needle in the gold |
| Fermenting Vat | `hold` | hold to cool, let go in the cold gold |
| Bottling Machine | `conveyor` | **Conveyor**: hold to pour, let go at each bottle's line, three bottles |

**The brewer's training makes it easier.** His success % (`Brewers.csv`)
sets how hard each game is: an untrained hand gets a narrower gold, a mash
that clumps faster, a mill that jams longer, less room at the fill line. So
an untrained hand fails more, which is your rule.

`data/BreweryGames.csv`, one row per machine:

| column | |
|---|---|
| `Section` | the BrewerySections.csv ID |
| `Kind` | `stir`, `rhythm`, `colour`, `fire`, `hold`, `conveyor` (the old `bar` and `mash` still work) |
| `Seconds` | the time limit |
| `Zone` | colour: share of the time it runs clear. fire and hold: the gold's width. conveyor: how close to the line counts |
| `Speed` | stir: soak per full turn. colour, hold, conveyor: fill a second |
| `Hits` | rhythm: turns to grind it. fire: seconds in the gold. conveyor: bottles |
| `Prompt` | the one line telling you what to do |
| `Art` | a folder of pictures, `assets/brewery/games/<machine>/` |

**The pictures.** Each game looks for these PNGs in its Art folder; one that
is missing is drawn as a plain shape, so the game always works.

| Kind | Pictures |
|---|---|
| stir | `tank.png`, `paddle.png` |
| rhythm | `mill.png`, `crank.png` |
| colour | `tun.png`, `bucket.png` |
| fire | `kettle.png`, `bellows.png` |
| hold | `vat.png` |
| conveyor | `tap.png`, `bottle.png`, `belt.png` |
| any | `background.png` behind it all (640x320 stage) |

No row = no game (the batch is rolled on the brewer's % as before).
`Tuning.csv brewery_minigames` false turns them all off. The game fires the
sound events `brew_game_hit`, `brew_game_won` and `brew_game_lost` for
`Audio.csv`.

### Plain beer (round AN)

> *"Plain beer gives random abilities that have one positive and then the
> opposite being negative."*

- **The basic three beers** (Anthony, 8 Oct: "small bottle, large bottle and
  a keg"). Before its game the Bottling Machine asks which size to fill, from
  `data/BottleSizes.csv`: one barrel is **6 Small Bottles, 3 Large Bottles or
  1 Kleiner Faß**, straight into the bag (`Items.csv small_bottle`,
  `large_bottle`, `keg`). Bigger fills more of the drunk meter: 10%, 20%, 35%.

| BottleSizes.csv column | |
|---|---|
| `Section` | the machine (`bottling`) |
| `Item` | the Items.csv ID that goes in the bag |
| `Many` | how many one batch fills |
| `Requires` | the condition language. Blank = always offered |

  One size offered = no question. In the tutorial Brewery only the Small
  Bottle is offered (the others need `!flag:tut_brewery`). A machine with
  sizes must have no lagering wait.
- `BreweryResources.csv` has a new `Counter` column (blank = `res_<ID>`).
  The bottle's is `small_bottle`, used only if BottleSizes.csv has no rows.
- **It's a lucky dip.** All three are plain beer, Use `brew:pool:plain`: every bottle picks one
  `Brews.csv` row whose new **Pool** column is `plain` (and whose Requires
  passes). Each row is a good **attack** side and its bad opposite on the
  **defend** side:

| Brews.csv row | Attack | Defend |
|---|---|---|
| `plain_goalie` | 1 stamina off the enemy keeper | 1 stamina off your own keeper |
| `plain_power` | +1 power | -1 power |
| `plain_keeper` | 1 stamina back to your keeper | 1 stamina back to theirs |

- **Pool rows are never poured at the Pub**, only drunk from the bag.
- **A plain beer takes hold however sober he is** (it takes less to get the
  ability, and it fills the meter only 10%).
- **In the tutorial only `plain_goalie` comes up**: the others need
  `!flag:in_tutorial`.
- Add a pair: an attack and a defend row in `Abilities.csv`, and a
  `Brews.csv` row with Pool `plain`.

### The tutorial Brewery (round AN)

In cycle 2 round 2 of the tutorial match the beer is gone and the Head Coach
calls a TIME OUT at the Brewery. **`MatchTalk.csv` Do `brewery:tut_brewery`**
freezes the match, sets `flag:tut_brewery` and opens the Brewery over it.
Three `Guide.csv` rows lead the way, all `Only`:

1. `tut_brewery_1`: Hanna explains brewers (a trained one rarely fails, an
   untrained hand spoils batches). Then hands over the Steeping Tank and the
   Bottling Machine with their keys, and the Steeping Tank lights up.
2. `tut_brewery_2`: after the malt, Hanna skips the middle four machines and
   hands over a barrel. The Bottling Machine lights up.
3. `tut_brewery_3`: six Small Bottles in the bag. `goto:back` closes the
   Brewery and the match carries on.

In those steps the game is played with Hanna's hand on it
(`Tuning.csv brewery_tour_chance` 85, `brewery_tour_worker` Hanna) and **a
miss starts it again**: the tutorial can't be lost. Everything it hands over
is in the tutorial's own save, so nothing is kept.

**Checked by:** `tests/unit/test_brewery_games.gd`, and
`tools/brewery_tour_shot.gd` presses the real buttons and plays both games.
`tools/minigames_shot.gd` plays all six games and takes the pictures.

### Tutorial jumps: the Dev screen goes straight to one part (round AN)

> *"Are you able to create a dev menu for me to jump between the different
> important aspects of the tutorial?"*

The Dev screen (the Dev button on the base) has a **TUTORIAL JUMPS** row, one
button per row of `data/TutorialJumps.csv`:

| column | |
|---|---|
| `ID` · `Label` | a name, and the words on the button |
| `Kind` | `brewery`: the tutorial Brewery TIME OUT on its own, Hanna and all (Value = its flag, `tut_brewery`). `minigame`: one machine's game on its own (Value = the BrewerySections.csv ID), played at `brewery_tour_chance` % and losable |
| `Value` | see Kind |

**Your save is never touched.** The Brewery jump plays in a throwaway save
(`user://tutorial_jump.json`) with `flag:in_tutorial`, and when Hanna is done
you are back on the Dev screen with your own save. Jumps into the match
itself (a cycle and a round) are with the Tutorial thread.
`tools/tutorial_jumps_shot.gd` presses the buttons and checks the save.

### `data/BrewerySections.csv`

| column | |
|---|---|
| `Order` | **is the map**. It is also what may feed what — see below |
| `ID` · `Name` · `Worker` | the Maltster, the Miller, the Lauterer, the Brewer, the Cellarman, the Bottler |
| `Needs` | the unlock condition. `unlocked:Malthouse` |
| `Takes` | `wheat:1;water:1;germs:1` |
| `Makes` | one resource ID |
| `How Many` | how many of it. Bottling makes **6** |
| `Wait Min` · `Wait Max` | the lagering, in turns. A turn is a fixture |
| `Art` · `Notes` | |

```
   1  MALTHOUSE   Maltster    Wheat + Water + Germs           -> Malt
   2  MILL        Miller      Malt + Water + Hammer           -> Mash
   3  LAUTERING   Lauterer    Mash + Filter                   -> Wort
   4  BOILING     Brewer      Wort + Hops + Boiler + Element  -> Brew
   5  COOLING     Cellarman   Brew + Yeast -> Barrel, lagered 1-3 turns
   6  BOTTLING    Bottler     Barrel -> 6 Bottles -> the Pub
```

### `data/BreweryResources.csv`

| column | |
|---|---|
| `ID` · `Name` | |
| `Kind` | `raw` comes from outside the brewery · `made` is produced by a section · `tool` is equipment |
| `Kept` | **`yes` means it is not used up.** You need a Hammer to work the Mill and you still have it afterwards. That is the whole difference between equipment and an ingredient, and it is one cell |
| `Start` | what a new game begins with |
| `Icon` · `Notes` | |

### Where the materials live

**In `GameState`'s counters, one per resource, named `res_<id>`.** Not a new
store — which means `count:res_malt>=3` is already a condition the whole game
can read. An achievement, a talent, a dialogue line and a Progression row can
all ask how much malt you have without a line of code being written for them.

### The order column is a rule, not a layout

A section may only be given something an **earlier** section makes, or
something raw. Otherwise the chain cannot be started, and that is the one way
a production chain breaks that a spreadsheet cannot show you: every cell is
spelled correctly and the map is impossible. The loader checks it and names
the section.

### The lagering

A barrel is not yours when you press the button. It sits in the cellar for
`Wait Min` to `Wait Max` turns. **A section lagers one batch at a time** —
deliberately, because it makes the cellar a decision ("do I start this now?")
rather than a queue. `BreweryBook.advance_turn()` is called from the same
place `RecoveryBook.advance_turn()` is, so there is one answer to "what is a
turn".

### The walk

```
godot --headless --script res://tools/brewery_check.gd
```

It starts a new game, opens every section, and works the chain over and over
until it runs dry:

```
  THE STARTING STOCK IS WORTH 24 BOTTLE(S).
  It stopped because it ran out of: Germs 0/1 at the Malthouse
```

**That second line is the one worth tuning against.** The bottleneck is
almost never the one you expect — it is germs, not wheat, and the game starts
with twice as much wheat as it can ever use.

It also prints which achievement opens each section, because a section
nothing unlocks is a building you can never walk into.

---

## 11c. The Pub, and the Traveling Brewer

### Tonight's ten

> *"The Pub: choose 10 players and give them drinks, else basic units."*

So the Pub is **two decisions**. First who is in the room — ten of them, and
the number is `pub_capacity` in `Tuning.csv`. Then what each of them drinks,
which is what the Pub already did. Anyone not in the room plays as they are:
printed power, no brew, no borrowed class.

**Right-click** a card to seat it or send it home. Left-click still pours,
and a card that is not in the room cannot be poured for — it is dimmed, not
hidden, because you need to see who you left out.

`pub_ten` in `Tuning.csv` is **false** out of the box. While it is false the
room is everybody and nothing on that screen changes. Turn it on the day the
squad is big enough for ten to be a choice rather than a chore.

The seats live in the save as `pub_ten`, one text, names separated by `|` —
the same shape `SquadBook` uses, for the same reason.

### Three beers — turning a plain player into a class (round X)

> *"Johannes is a plain Tier I Power 0, but when he drinks 3 water element
> beer he becomes a Tier I Power 0 Lorelei. Same for all of the other
> elements."*

**A number in the new `Drinks` column of Brews.csv makes a TURNING brew.**
Blank is an ordinary brew, exactly as before.

```
   pour 1   Johannes  Water ●○○
   pour 2   Johannes  Water ●●○
   pour 3   Johannes  Water ●●●   ->  "Who does Johannes become?"
                                       [ Sitri set  - Matthias ]
                                       [ Zepar set  - Werner   ]
                                       [ Sallos set - Johanna  ]
```

Your three answers are the rules:

| question | rule |
|---|---|
| whose abilities? | **you pick.** The Pub shows the class's cards at his tier and power, one per set, and he becomes the one you choose |
| mixing beers? | **a new element starts again.** Water, water, fire = Fire 1 of 3 |
| switched on? | **yes, for every plain card today** (BasicTeam's). Named recruits are a separate switch — section 6b |

**What he keeps:** his name, his tier, his power. **What he takes** from the
card you chose: class, element, set, both ability texts, both ability IDs and
its artwork. It is for good. He can still drink an ordinary brew on top — a
turned Lorelei may drink the Fire Brew, which is For Class Lorelei.

Closing the question without choosing is fine: he keeps his three beers, and
the Pub asks again the next time you click him with that brew.

**Four rows ship:** `turn_water` (Rhine Water Lager → Lorelei), `turn_fire`
(Rauhnacht Smoke Beer → Rauhnacht-Feuergeister), `turn_earth` (Miner's
Dunkel → Bergmännlein), `turn_air` (Unken Weisse → Unkengeister). Each is
For Class `Normal`, Drinks 3, and costs 2 of a material a beer.

**One gap the tool found:** each class has one tier that belongs to its Stars
alone, so a plain player of that tier has nothing to turn into:

```
   Lorelei                  nothing at Tier II
   Rauhnacht-Feuergeister   nothing at Tier IV
   Bergmännlein             nothing at Tier III
   Unkengeister             nothing at Tier II
```

The Pub refuses the first beer and says why, rather than taking three beers
and then having nothing to offer. Whether that tier should be able to turn —
into the Star? into a stand-in? not at all? — is a design question for you.

**Where it lives:** `drinks_<name>` (`water:2`) and `became_<name>` (the
Name of the card he became) in the save. Because it is stored against the
card he *became*, **renaming that set card breaks the link** — the same rule
as every card name. Code: `src/core/transform_book.gd`.

### The drunk meter (round AN)

Every player has a drunk meter, 0 to 100%. Every drink at the Pub fills it,
and the levels it reaches give him something.

| File | Column | What it does |
|---|---|---|
| `data/Brews.csv` | **Inspiration** | How much of the meter one pour fills, in %. |
| `data/Items.csv` | **Inspiration** | The same for a bottle in the bag. Blank = the brew's own number. A bought bottle can be weaker than the one your Brewery makes (bottled Fire Brew 15%, poured 25%). |
| `data/DrunkLevels.csv` | **From**, **Effect** | Where each level starts and what it gives. |
| `data/StarAbilities.csv` | **Tier**, **Power**, **Ability** | The star ability a drunk Star plays with. Today every row is Koch's Beer Courage. |
| `data/Tuning.csv` | `drunk_meter`, `drunk_lost_per_round` | Off switch, and how much of his meter a player loses after every round he played, as a % of what he has (50 = half). |

**The levels out of the box:**

- **Sober, 0%.** A brew with an Element, a Becomes or an ability (elemental
  or inspirational) **can always be drunk** (Anthony, 8 Oct): it is poured,
  paid for and fills the meter, but it does nothing in the match until he
  reaches Tipsy. A sober turning beer only fills the meter and does not
  count towards turning him.
- **Tipsy, 30%** (`brews`). Every brew takes hold.
- **Inspired, 70%** (`star;turn_drinks:-2`). He plays as a Star: STAR on his
  card and name plate, and the star ability from StarAbilities.csv on both
  sides. A brew's own ability still wins on its side. He also needs two
  fewer turning beers (three becomes one).

**How it wears off (Anthony, 8 Oct):** after every round he played (a match
or an Adventure played to the end) he loses `drunk_lost_per_round` % of what
he has, 50 out of the box, so 80% becomes 40%. While he can still play
(`Plays` in Recovery.csv) you top him up with more beers. Once he is
exhausted and resting in the Dorms, **his meter is empty**. A player who sat
the round out keeps his meter. A Quit changes nothing.

**Plain beers** are Brews.csv rows with no Becomes and no abilities, only
Inspiration: the Helles (+20%, free) and the Festbier (+35%, 1 Reed). They
never sit on the card as a brew; they only fill the meter.

**In the Pub** every card has the meter under it, with a notch at each
level, and the line at the top says when a player reaches a new level.

**To change it:** move the From numbers, add a level row, give a brew more
or less Inspiration, or add StarAbilities.csv rows such as `II,2,SOME_ABILITY`
when you design the star abilities. The most exact row wins.

**Checked by:** `tests/unit/test_drunk_meter.gd`, and `tools/drunk_shot.gd`
presses the real Pub buttons and takes the pictures.

### `data/Currencies.csv`

| column | |
|---|---|
| `ID` · `Name` | |
| `Counter` | the GameState counter it lives in. **Defaults to the ID**, so a currency called `coins` is the `coins` counter the game already had |
| `Earned In` | **the MatchModes.csv id that pays it.** Blank means every mode |
| `Win` · `Draw` · `Loss` | paid at the final whistle |
| `Icon` | |

**`Earned In` is the separation.** A Quick Match never pays league coins and
a season match never pays marks — which is the whole of *"separate currencies
per mode"*, and it is one column.

**A second currency is how a mode earns its place.** If the only thing a
Quick Match gave you was the same coins a league match gives, there would be
no reason to play one. Price something good in marks and there is.

### `data/Shop.csv` — the Traveling Brewer

| column | |
|---|---|
| `Sells` | `res:hops` for a Brewery material, `brew:fire` for a **recipe** |
| `How Many` | of the material |
| `Price` · `Currency` | |
| `Stock` | **how many he has EVER**, not per visit. Blank is unlimited |
| `Requires` | the usual condition language |
| `Art` | a 64×64 in `assets/shop/`, and the row reads fine without it |

`brew:<id>` unlocks that row of `Brews.csv` **by name**, exactly as a talent
or an achievement would. Anything else in `Sells` is handed to the ordinary
effects language, so `unlock:Something` works there too.

A sold-out row **stays on the screen and says SOLD OUT**. A thing that
vanishes is a thing you think you imagined.

### He is the pressure valve on the Brewery

`tools/brewery_check.gd` measures **hops** as the thing the chain runs dry of
— they only arrive when you win — and reports wort backing up nineteen deep
behind the boiling copper waiting for them. The Brewer sells hops, dear. He
is there for the week you need them, not instead of the Brewery.

### Price it in wins, not in coins

```
godot --headless --script res://tools/shop_check.gd

  hops_sack        6 Hops             45 coins    3 left    1.1 wins
  fire_recipe      the fire recipe    150 coins   1 left    3.8 wins
  EVERYTHING HE HAS, in coins: 790  (20 wins)

  === A SEASON: 10 fixtures, half won, half lost ===
  Coins          225
```

**"45 coins" means nothing on its own.** It means something beside "a season
win pays 40" — that sack is a win and a bit, and the whole cart is twenty
wins against a season that pays 225. That multiplication is the only thing
worth checking about a shop.

> Note that `Season.csv` also pays coins on some fixtures (`count:coins+25`
> on matchday 4, `+250` for winning the final). Those are on top of the
> per-match pay-out and they are meant to be — a cup final should feel like
> one — but it does mean a real season is richer than the 225 above.

---

## 11d. Around the match — competitions, runs, and the ground

### `data/SeasonRules.csv` — a competition's own rules

> *"Seasons with their own rules: what is allowed, what is on the field,
> what is different — per season, in a CSV."*

Three questions, three groups of columns:

| | |
|---|---|
| **what is allowed** | `Only Classes` · `No Brews` · `No Stars` |
| **what is on the field** | `Per Tier` |
| **what is different** | `Tuning` — any row of `Tuning.csv`, for the length of the competition |

**A competition's rules are LENT, not given.** Everything here is put back
the moment you play something outside that competition — because a Winter Cup
that quietly leaves the keeper tired for the rest of the game is a bug nobody
will ever trace back to the Winter Cup.

```
winter_cup     no brews, shot stamina bite is 0.75, out of bounds player chance is 0.6
the_crown      only Lorelei, Rauhnacht-Feuergeister, 3 per tier, max card power is 4
```

**The three named columns are Tuning rows too.** `No Brews`, `No Stars` and
`Per Tier` are written as their own columns because that is how you think
about them — and folded into the same Tuning machinery underneath, so there
is **one way to lend a rule and one way to hand it back**, not four. They
lend `brews_allowed`, `stars_allowed` and `season_per_tier`, which are
ordinary rows of `Tuning.csv` with ordinary defaults.

**Every key in a `Tuning` column has to be a real Tuning row.** A
misspelling there is a competition that *looks* like it bends the game and
does not, which is the worst kind of wrong. The checker names it.

### A dialogue before a season, and before a fixture

| | |
|---|---|
| `Seasons.csv` → `Story` | plays when you open that competition |
| `SeasonRules.csv` → `Story Before` | the same, for a competition whose rules you are writing anyway |
| **`Season.csv` → `Story`** | **NEW.** Plays before that one fixture |

A fixture's scene plays **on the way to the team sheet** — before you pick
anybody, which is the only moment a scene can still change your mind about
who to field. It comes back to the team sheet afterwards, so a scene is a
detour and never a dead end. A fixture's Story plays every time that fixture
is played; use `flag:x` inside the scene if it should only happen once.

### `data/Pickups.csv` — what a run is worth

> *"A fixed number of pickups before each wave and the boss, from a CSV,
> instead of however many happen to spawn."*

That was exactly the problem. Pickups arrived on a **timer with a random
gap**, so a run gave you somewhere between one and six of them and nobody —
not you, not me, not a tool — could say which. A biome whose haul is a dice
roll you never see cannot be balanced.

Now the number is written down, and the pickups are **spaced evenly** over
whatever distance the wave turns out to be, so a faster run is not a poorer
one.

```
godot --headless --script res://tools/season_check.gd

  biome                  per wave     boss         a whole run
  The Marshlands         4            6            18 pickup(s) over 4 wave(s)
  The Hollowdeep         3            5            20 pickup(s) over 6 wave(s)
```

`Biome = *` sets the pacing of every biome at once, which is the edit you
actually want while tuning.

### The enemy window knows where you are going

The window in front of a match used to show whichever class the next
**fixture** named — even when you were about to walk into the Marshlands. It
reads the run's own biome now, listing everything in that pool with how often
it turns up and marking the boss:

```
   Mire Grub  ·  attack 1  ·  4 layer(s)  ·  turns up often
   THE BOSS — The Marsh King  ·  attack 3  ·  12 layer(s)  ·  turns up rarely
```

`Weight` is read back in words on purpose. A number nobody can feel becomes a
sentence everybody can.

### The Stadium

Your ground — the background, the crowd, the floodlights — is `Stadium.csv`,
and every layer is unlocked by an achievement like everything else. The
screen is a **read-out, not a shop**: what it is for is telling you what your
ground would look like if you went and earned the next one, and which
achievement that is.

**It is on the top bar, not a building.** You said the base is those nine
buildings and no others, and the Stadium is what your ground *looks like*
rather than a room you walk into. Say the word and it is a tenth building:
one row of `Buildings.csv` with `window:stadium`.

> **The Unlocks button is gone.** It showed everything you can earn and what
> is missing — which is exactly what the **Achievements** building now shows,
> in the same words, from the same file. The screen itself is still in the
> project and `goto:board` still opens it.

---

## 11e. Team Build — the gate before the Pub and every match (round Y)

> *"A team has to be made before entering a pub... They also need to add the
> three star players to their talent tree before they can enter the pub or
> start a match. These are mandatory players and dictate their build
> entirely. Maybe rename talent tree to Team Build and the 'create a team'
> feature to that hub."*

### The rule

You are **ready** when at least one saved team is **complete — 12 players,
three Stars and nine more** — and **every Star of that team's class stands in
the Star Hall**. Until then:

- the **Pub** door, **Play a match** and **The season** open **Team Build**
  instead, on the tab you're missing, with the reason on the base;
- the team shelf's **LOCK IN** stays shut for a side whose Stars aren't
  placed;
- a `goto:pub` from a story line still lands on a Pub that says it's shut.

**Adventure is not gated.** You said Adventure comes later.

### The hub

```
   TEAM BUILD
   ✖ Stars placed 0 / 3    ✖ Team 0 / 12
   Place your three Stars in the Star Hall, then build a team of 12.
   [ STAR HALL ]  [ YOUR TEAMS ]  [ TALENTS ]
```

The base building (it keeps its ID, `talent_tree`, so nothing pointing at it
breaks) and the **Your teams** button both open it.

### The Stars come first

`class_tree_gates_units` is **on** now: a set's nine cards can only go into a
team once its Star stands in its node. That's "the Stars dictate the build",
and it's why a new player lands on the Star Hall tab.

### Two things that would have locked a new game

| problem | answer |
|---|---|
| Stars cost talent points, and talent points come from matches | **`team_build_free_stars`** (3): the first three Stars you ever place are free. The Star Hall says so on each class |
| The Talent Tree building only appeared after an unlock | Team Build has **no Requires**. The **Talents** tab inside still waits for `unlocked:Talent Tree` |

### The switches

| Tuning row | |
|---|---|
| `team_build_gate` | `true`. `false` and nothing is gated |
| `team_build_free_stars` | `3` |
| `class_tree_gates_units` | `true` since round Y |

Code: `src/core/team_build.gd` (the rule), `src/ui/team_build_screen.gd` (the
hub). `tools/team_build_shot.gd` presses the real doors on a new game and
checks they open Team Build — then that they open the Pub once you're ready.

---

## 12. Words — dialogue, localisation, keys

**`data/Dialogue.csv`** (and `data/tutorial/Dialogue.csv`) — a node graph in
a spreadsheet. `Scene`, `Node ID`, `Speaker`, `Portrait`, `Side`, `Mood`, `View`, `Animation`,
`Background`, `Music`, `Sound`, `Text`, `Next`, `Requires`, `Effects`, and then three
sets of `Choice N Text / Next / Requires / Effects`.

**`Sound`** (round AN) plays one sound the moment the line shows: an Audio.csv
ID or a file name in `assets/audio/`. The prologue's "Cheering!" uses
`bld_pub`, the beer hall cheering.

**Who is on screen (round AN, the stage).** Everybody who has spoken in a
scene stays on screen. One person alone stands in the middle and looks at
you (front face). Two or more stand at their own `Side`; the speaker shows
the line's Mood and View, the others turn to the room and are dimmed.
Somebody new on a taken Side pushes the old one off. They slide in, across
and out rather than popping. To send someone off, write their Speaker name
or Portrait ID in an optional **`Leaves`** column (several separated by `;`,
or `all`); add the column anywhere in the header when you need it.

**Writing dialogue in the chat (round AN).** Post a script like this in the
dialogue thread and Claude puts it in Dialogue.csv word for word:

```
## Scene: prologue
Narrator: Three players wait at the Stammtisch.
Head Coach (happy): Servus, Trainer! Sit down.
Head Coach (mad, side): Koch! Put that down.
> Shake his hand -> handshake
# handshake
Head Coach (drunk): Good grip.
```

`Name:` is the Speaker, `Narrator:` a blank Speaker. `(mood, side)` fills
Mood and View. `> text -> label` is a choice, `# label` the Node ID it jumps
to.

**The prologue (round AN)** is Anthony's Head Coach scene at the Stammtisch.
It plays the first time the base opens on a new save (Progression.csv
`welcome_at_base`). Koch's `silhouette` and `bergmaennlein` faces are Mood
words waiting for their StoryArt.csv rows; until then he shows his everyday
face. **`star-intro`** (round AN) is Anthony's scene back at the bar after the
first match: the Head Coach explains what a Star is. Progression.csv
`first_match_is_over` plays it; it ends on "Another game!", which leads into
the second match with three Bergmännlein Stars. The old Heatwave conversation is now the scene `heatwave_talk`, and the
base visitors (Visitors.csv `Story`) point at it.

A line with no choices runs on to `Next`. A line with choices stops and asks.
A choice whose `Requires` fails is greyed out rather than hidden, so the
player can see what they missed.

### The faces and the rooms — `data/StoryArt.csv` (round AN)

Every picture a conversation shows, one row each. Dialogue.csv only names a
row by its **ID**, so changing a face or a room everywhere is one cell.

| Column | |
|---|---|
| `ID` | the name Dialogue.csv writes in `Portrait` or `Background` |
| `Kind` | `portrait` (a face beside the text box) or `background` (the room) |
| `Speaker` | portraits only. A line with this Speaker and an **empty** Portrait cell gets this face, so you never type it on every line |
| `Image` | the PNG, as a `res://` path. The new art is in `assets/story/portraits/` and `assets/story/backgrounds/` |
| `Mood` | portraits only: `happy`, `sad`, `drunk`, `mad` ... any word. Blank = the everyday face |
| `View` | portraits only: `front` (looking at the player) or `side` (talking to someone in the scene) |
| `Faces` | side views: which way the drawing looks (`right` / `left`). The game mirrors it on the other side, so everybody looks into the room. A front view is never mirrored |
| `Front` | backgrounds only. `yes` draws that layer in front of the people |
| `Scale` | portraits only, **round AN**. How big this face is drawn, 1 = normal (blank = 1). A picture drawn closer in than the character's other faces (a bigger head) gets 0.8 or so; it shrinks towards the bottom edge so the shoulders stay on the text box. Koch's sad face is 0.8 and his happy face 0.85 |

**Every character has a front and a side face** (Anthony, round AN): front
for talking to the player, side for talking to someone else in the scene.
One character is several rows with the same ID, one per Mood and View. A
line in Dialogue.csv picks one with its own **`Mood`** and **`View`** columns
(blank View = front). When the exact face is missing, the game takes the
nearest: the same mood from the other side, then the everyday face, then any
face of that character.

**The Head Coach** (`coach`, Speaker `The Head Coach`): a 1990s German village
coach, perm mullet, moustache, purple-and-teal shell-suit, whistle and
clipboard. Eight faces: happy, sad, drunk and mad, each front and side.

**A room in layers.** Give several `background` rows the same ID: they are
stacked in file order, the first row at the back. The bar is two rows: the
empty Wirtshaus, then the regulars at the Stammtisch. Delete the second row
for an empty pub.

**The intro now plays in the bar.** The prologue and the first-team scene
open with `Background` = `bar`; a line with a blank Background keeps the room
that is already up. Faces: `heatwave`, `brewer`, `hoffmann`, `schaefer`,
`koch`.

**Making more.** PixelLab `create_image_pro`, 512×512 with a transparent
background and `art_source/style_refs/stammtisch/board_characters.png` as the
style image, prompt from `tools/art_prompt.gd -- pixellab "a waist-up
visual-novel dialogue portrait of one character, facing right ..."`. A room
is 688×384, one call per layer. The PixelLab originals are in
`art_source/pixellab/story/`, the layered files in
`art_source/aseprite/story/` (`bar.aseprite`, `cast.aseprite`: one layer per
face). To look at the result without playing:
`godot --path . --resolution 1920x1080 --script res://tools/story_shot.gd`.

A Portrait or Background that is not an ID in StoryArt.csv still works the old
way: a file name looked for in `assets/portraits/` or `assets/backgrounds/`.
The base visitors (Visitors.csv) still read `assets/portraits/`; since round
AN, Heatwave and the Brewer there are the same PixelLab front faces (the old
pictures are in `art_source/legacy/portraits/`).

**Music under the conversations:** Audio.csv row `story_theme` plays
`dialogue_suno` - your Suno Schlager *Leiser Oom-Pah* (round AN), the whole
song with a 4-second fade before it starts again (MusicLoops.csv row
`suno_dialogue`). The Pub (`pub_theme`) plays it too. To swap it: put the new
track in `assets/audio/` and write its file name (no ending) in `Sound`. A
line's own `Music` cell still wins for that line.

**`data/Language.csv`** — `Key`, `English`, `Deutsch`, `Notes`. Add a column
for a new language; the game finds it. Any text the game shows goes through a
key here.

**`data/Keys.csv`** — `Action`, `Label`, `Group`, `Default Key`, `Default
Button`. Keyboard and controller bindings, rebindable in Settings.

**`data/MenuConfig.csv`** — `Button ID`, `Label`, `X`, `Y`, `Width`,
`Height`, `Action`, `Art Path`. The main menu, laid out in a spreadsheet.

### The three window modes

Not a spreadsheet — `user://settings.json`, written by the Settings screen —
but worth knowing because all three behave the same way now:

| Mode | |
|---|---|
| `windowed` | a normal window at the chosen resolution, **centred on the screen it is on** |
| `fullscreen` | the whole screen, no window |
| `borderless` | a window with no frame, filling **the screen it is on** — the right monitor on a two-monitor desk, not always screen 0 |

**Fullscreen did nothing and Borderless shrank the window**, and it was one
cause with two faces: the old code set the mode and the borderless flag in
whichever order that arm happened to be written, starting from whatever the
window was already in. Clearing the borderless flag *after* asking for
fullscreen knocks the window straight back out of it; setting the flag and
*then* asking for a size leaves the window carrying the small size it had last
time it was a window.

It now always goes back to a plain window and clears every flag **first**, and
only then applies the mode asked for. One known starting point, three short
arms, and no arm has to know what the last one left behind. Switching between
the three in any order, any number of times, gets the same result every time.

---

## 13. Saving

Three save slots (`slot_count` in Tuning.csv). A save is flags, counters,
unlocks and your team.

**A card is identified by its `Name`.** Renaming a card in your unit CSV means
old saves no longer find it. Plan your names before you have players, or
accept that renames need a migration.

---

## 14. The tools

In `tools/`. Nothing in the game loads them; they are for you.

**Round Y, the combat abilities** — see the box in section 7 for the four
commands: `ability_audit.py`, `ability_rows.py`, `ability_coverage.gd`
(the meter) and `ability_check.gd` (the proof).

**Round AB — the balance report** (your answer Q059):

```
python3 tools/balance_report.py              5 matches per class
python3 tools/balance_report.py 20           20 per class (about 1.5 hours)
python3 tools/balance_report.py 10 Lorelei   one class
```

Plays whole matches with nobody watching, four at a time, each with its own
seed, and counts from the Output log: won / drawn / lost, goals, every Emblem
that turned over (or was blocked), Rose tokens, Swans, Ore, counters,
switches, negates, fouls, cards, coin flips - and any SCRIPT ERROR. Writes
`tools/balance_report.md`. It is the tool for the mass-testing phase. Round AB's first report (5 per class) is shipped as an example.

**Round AA — `data/Questions.csv`, the questions file.** Everything I need
to ask you that is not about one card's wording goes here, as many as there
are: `ID, Area, Question, Why It Matters, Options, My Default (playing now),
Your Answer, Status, Round`. Write in **Your Answer** (a letter is enough);
leave the rest - the default is already in the game. The workbench edits it
like any other file.

```
python3 tools/questions.py     how many are open, and which answers are not built yet
```

```
SOAK_CLASS=Lorelei xvfb-run -a godot --rendering-driver opengl3 \
    --resolution 1920x1080 --script res://tools/combat_shot.gd
xvfb-run -a godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/choice_shot.gd
```
**Round AA.** `combat_shot` photographs a real match every 1.5 seconds
(`cs_000.png`...) - the way to check what sits on top of what during combat.
`choice_shot` photographs the question window.

**Round Z.** `ability_check.gd` now makes each card's **If and Cost true**
before its moment (3 Ore for "Consume 3 Ore", a Rose token for "if you control
a token"), checks the Ore was spent, checks it does NOT go off with no Ore,
and plays **five Emblem stories** (Zepar, Sallos, Belphegor, Buer, Gremory).

```
xvfb-run -a godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/c2_shot.gd
```
**Round Z.** A Lorelei draft with Ore, a burn and a power counter, a Swan and
Werner's "next 2 swans" waiting - a picture of the match tracker, the card
strip and Zepar's SHOW button (`c2_01_draft.png`).

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/team_build_shot.gd
```
**Round Y.** On a throwaway save: presses the Pub and Play a match on a new
game and checks both open Team Build; places three free Stars and a team of
twelve; checks the Pub then opens. Photographs each step.

```
godot --headless --script res://tools/round_x_check.gd
```
**Round X, measured, on a scratch save that never touches yours.** Hands out
300 names and checks none repeat; recruits three players and releases one;
pours water, water, fire, then three waters, and checks he keeps his name and
takes the chosen card's abilities; prints which tier of each class has
nothing to turn into; prints the repeat-offender table for every referee; and
fires Karl's ore card seven times to prove it stops at its Max. Ends ALL GOOD
or with sentences.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/pub_turn_shot.gd
```
**Presses the real Pub buttons** — the Rhine Water Lager, then Müller three
times — photographs the "who does he become?" question, presses the first
set, and photographs the result. A broken button fails the run.

```
python3 tools/cut_chrome.py
```
Cuts the PixelLab sheets in `art_source/pixellab/` into the eight chrome
files, following the Sheet / Cut / Finish columns of ArtOrders.csv. See 8b2.

```
godot --headless --script res://tools/adventure_soak.gd
```
Plays 100 complete Adventure fights with no window — drafting a card for
every tier of every round, half of them deliberately unfair so the revive,
the stand-in and the everybody-is-down paths all get run. Prints how many
were cleared, and checks the tier ladder after every one. **Every error Godot
prints while it runs is a real error in the game.**

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/adventure_shot.gd
```
Opens the real Adventure scene, hurries the first wave along, drafts through
the tiers and **saves a screenshot at each step**. This is how layout gets
checked — a window cut off at the bottom is not something a parse check can
ever see.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/match_shot.gd
```
The same idea for a **league match**: it opens the real match scene with a
real team, watches the kick-off and the first clash, and saves the screen at
each step. Each line it prints says the camera's zoom, who is carrying the
ball and whether the match is marked live — which between them are the whole
kick-off test. A countdown that never appears, a camera that never pushes in
and a ball nobody ever picks up all look identical in a still picture.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/coin_shot.gd
```
Opens the **clash screen on its own**, calls a number, lets the coin land and
screenshots each step. The clash only turns up several minutes into a real
match, after a draft and a relay, which is a long way to walk to find out that
a button is off the bottom of the screen.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/screen_shot.gd
```
Opens the **Inventory** and the **Edit Element Bonus** picker on their own,
with a made-up save that has something in it, and photographs each tab. An
empty bag photographs as an empty box, which tells you nothing about how a
full one lays out.

```
godot --headless --script res://tools/lane_check.gd
```
Puts a player in every row of the Adventure running shape, knocks each one
over, and checks the **whole body** is still on the grass. Lying down makes a
player a completely different shape — turned a quarter-turn, a sprite thirty
wide and a hundred tall is a hundred wide and thirty tall — so somebody
standing legally in the top row could lie down and reach ninety pixels above
the band, onto the black. A screenshot only catches that if you happen to take
it at the right moment.

```
godot --headless --script res://tools/restart_check.gd
```
Calls the shot directly, four times, and watches the seconds that follow —
printing **how far everyone moved**, **whether the restart hold is on**, **the
clock**, and **how many players are standing over a keeper**. It calls the
shot rather than waiting for one because a restart happens once every few
minutes at the end of a long chain of duels, and a test that waits that long
is a test you stop running. Those
are the two things a screenshot cannot show: eleven players standing still and
eleven players running look identical in a still picture, and so do a shape
and a scrum. It stops with STUCK if six seconds of live play go by with nobody
moving.

```
godot --headless --script res://tools/movement_check.gd
```
Plays ninety seconds of a real match with AUTO on and prints two numbers:
**reversals per second** — how often a player turns more than 120° between one
tenth of a second and the next, which is what "shaking" actually is — and the
**pile-up**, meaning pairs of players standing closer together than a player
is drawn wide, given both at the worst moment and on average. The average is
the honest one: every scramble for a loose ball puts two players inside a
player's width for a moment, and that is a tackle rather than a fault. It also
prints any seconds of live play in which
*nobody* moved, because a frozen pitch and a calm one look the same in a still
picture.

It counts reversals rather than "distance walked ÷ distance gained" on
purpose: the second number scores a player wandering round their patch exactly
like a player vibrating on the spot, and the wandering is wanted.

```
godot --headless --script res://tools/shape_check.gd
```
**Are they standing in pairs, and is anybody using the pitch?** Plays eighty
seconds and prints **glued pairs** — two players from opposite sides both
close together AND level with each other, which is the shape in the
screenshot — plus how much of the pitch the shape covers at any one moment,
the average gap to the nearest player, how often anybody leaves their own
quarter, how many squares of the pitch anybody stood in, and how close anyone
came to each touchline and each goal.

**It reports all of that per phase as well** — ordinary play, the break, the
restart — because one average over a whole match hides the two moments that
were actually complained about, both of which are short.

```
godot --headless --script res://tools/enemy_play_check.gd
```
**Do the opposition's rules do what EnemyPlay.csv says?** Puts the same four
cards in front of the rules in every situation the columns can describe and
prints which rule answered and what it chose. A rule that never appears is a
rule that can never happen.

```
godot --headless --script res://tools/recovery_check.gd
```
**Is your roster big enough for fatigue?** Plays six fixtures in a second,
prints who is out and for how long each week, and ends with a verdict on
whether to turn `recovery` on at all.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/formation_shot.gd
```
The pitch from the stand, photographed every few seconds through ordinary
waiting play. `shape_check` says whether it got better; this says whether it
looks right.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/reveal_shot.gd
```
The **strip above the card row**, with real cards on it. It only exists while
something has been played face up, so this is the only way to look at it short
of playing a match and hoping the right card comes up in the right tier.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/sheet_shot.gd
```

The team sheet: six Stars, three a side, with their abilities printed under
them and tagged ATK / DEF. It also counts the lines and tells you the number —
six Stars should give twelve, and an odd number means somebody is missing a
side, which a photograph cannot tell you.

> It replaces `sheet_hover_shot.gd`, which photographed the hover panel that
> no longer exists.

```
godot --headless --script res://tools/goal_shot.gd
```

**The goal celebration, without having to score one.** It opens a match, gets
past the sheet, the line-ups and the kick-off, then calls the celebration
directly with a real card out of your own spreadsheets — every beat, from
Celebration.csv, in your order and with your Seconds. Four pictures: the
slide, the huddle, and both panels of the window.

It also **measures the huddle**: nine men, the radius `celebration_swarm_radius`
asked for, and the average, nearest and furthest they actually ended up. Run it
headless for that number — a rendered window on a machine with no graphics card
runs at two frames a second and the measurement wanders. Headless it reads
`110 / 110 / 110`.

```
godot --headless --script res://tools/theme_check.gd
```

Every element of `Theme.csv`, what it is drawn from and whether that file
exists; every palette colour and whether the game reads that name; and what is
sitting in `assets/ui/` that no row is using. An image name that is nearly
right draws nothing, and nothing looks a lot like "I have not drawn it yet".

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/theme_shot.gd
```

**The skin, before and after.** The same screen twice: as Theme.csv is
written now, and with the three starter images forced into it. It changes
nothing on disk — the swap is in memory, for the length of one screenshot.

```
godot --headless --script res://tools/shot_odds_check.gd
```

**The scoring curve, printed.** The whole grid — every stamina band against
every shot power — then the band the pitch will show, then ten thousand shots
at each to check the dice agree with the table. It is specifically checking
three things: that an empty keeper is 100%, that it gets easier all the way
down, and that the number on the screen is the number being rolled.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/keeper_shot.gd
```

The keeper's number in both places it is shown: the cut-away against a full
keeper and against an empty one, and the band under both keepers on the grass.

```
godot --headless --script res://tools/scoring_balance.gd
```

**How many goals is a match?** It plays the *shots* rather than the matches —
the real shot powers, the real keeper stamina, the real nine rounds, the real
curve, two thousand times — and prints goals per side, the spread, the share
of shots that go in, and how often somebody reaches six in a one-sided game.
**Run it after touching any number in ShotOdds.csv.**

> It exists because I tuned that curve against a shot power of 0 to 8 and
> then measured the game: shot powers are 10 to 22. A guess where a
> measurement belonged.

```
godot --headless --script res://tools/out_of_bounds_check.gd
```

Every row of `OutOfBounds.csv` in order with a clock down the side, everything
a row names that does not exist, the ordering rule — and **how long a round
now takes to open, multiplied by the nine times it happens in a match.**

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/throw_in_shot.gd
```

The whole out-of-bounds sequence photographed: the ball on its way over the
line, the animation window, the thrower standing outside the line, and the
screen where the coin used to be. It also **measures** how far outside the
line he ended up, because a picture cannot tell you that.

```
godot --headless --script res://tools/match_soak.gd
SOAK_CLASS=Lorelei godot --headless --script res://tools/match_soak.gd
```

(Round Z: `SOAK_CLASS` plays that class - so a Lorelei soak makes Rose
tokens and a Rauhnacht one burns.)

**A whole league match, played through with nobody watching.** AUTO on, speed
up, and let it run from kick-off to full time. It is the one question no other
tool answers — every other tool looks at a single moment — and it is the test
that a celebration which never returns, or a hold that never lifts, would
fail. Both of those look exactly like the game having frozen, and a frozen
game prints nothing.

It reports every goal, and if the score, the state and the clock are all
unchanged for forty-five seconds it says **STUCK** and gives up, because a
tool that hangs is a tool nobody runs. A clean run is about eighty seconds and
ends `NO TROUBLE`.

> Adventure has had `adventure_soak.gd` since round H and it has caught real
> crashes. The league match had nothing until now.

```
godot --headless --script res://tools/celebration_check.gd
```

Reads `Celebration.csv` back to you: both running orders with a clock down the
side, **how long a goal now costs** (yours and theirs, celebration plus the
walk back), and then everything a row names that does not exist — a sound with
no file, an animation with no row in Animations.csv, an `Art` file that is not
in `assets/`, a `{placeholder}` nothing fills in.

> The length is the number to watch. Eleven seconds reads beautifully the
> first time and is unbearable by the fourth goal; the checker says so out
> loud past twelve.

```
godot --headless --script res://tools/emblem_check.gd
```
Every class with its element and its Star tier; every Emblem with its Star,
its set, its token and who feeds it; **the race priced in duels**, with the
shortest named and the spread called out; and the element rule worked through
with your real cards. See section 7f.

```
godot --headless --script res://tools/class_check.gd
```
**Do a class's spreadsheets agree with each other?** A class is spread over a
unit CSV and an emblem CSV that have to line up by name. Prints what each
class describes and everything that does not match. **Run it before drawing
thirty cards for a class.**

```
godot --headless --script res://tools/csv_import_fix.gd
```
**Writes the missing `.csv.import` files and deletes the junk they cause.**
Godot treats a .csv as a translation file unless a three-line `.csv.import`
beside it says `importer="keep"` — so a new spreadsheet quietly produces one
`.translation` file per column. Four new files made thirty-two of them.

> It is not enough for the `.csv.import` to exist: when Godot imports a CSV
> as a translation it **writes one itself**, saying
> `importer="csv_translation"`. This checks what the file says, not whether
> it is there.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/menu_shot.gd
```
The save shelf, a slot's settings window, the Are You Sure, and the Escape
panel — none of them reachable from a tool without clicking.

```
godot --headless --script res://tools/clock_check.gd
```
Fires every slow-motion moment in overlapping bursts and checks
`Engine.time_scale` always comes back to 1.0. If it ever prints STUCK, the
compounding-slowdown bug is back.

```
godot --headless --script res://tools/phase_timing.gd
```
Times both halves of one real Adventure round — yours and theirs — at two,
four, eight and twelve enemies. "Their turn feels slow" becomes a number.

```
godot --headless --script res://tools/achievement_check.gd
```
Every achievement read back, the counter each one waits on, and the two
questions a spreadsheet cannot answer: **is anything gated behind a counter
nothing counts**, and **is anything tested that nobody grants**. See section
4b.

```
godot --headless --script res://tools/foul_check.gd
```
The foul curve read back at every trigger count, and then two thousand
matches simulated at each level — fouls, yellows, reds and how often a match
ends ten against eleven. It does the multiplication that makes "18%" mean
something: both sides roll, nine times a match, which is eighteen rolls. See
section 7d.

```
godot --headless --script res://tools/season_check.gd
```
Every competition's rules in a sentence, every borrowed Tuning row applied
and then checked that it was handed back, what a whole Adventure run is
worth in pickups, and which fixtures have a dialogue before them. See
section 11d.

```
godot --headless --script res://tools/rooms_check.gd
```
Every building, the screen its door opens, and whether that screen exists —
plus the Dorms, the Trophies and the Training priced in SEASONS. See
section 11.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/base_shot.gd
```
The base, and then one picture per window opened over it. Twelve shots, and
the point of every one is that the base is still there behind it.

**It presses the real buttons.** It finds each building's plaque on the map
by name and emits `pressed`, exactly as your mouse would, then checks that a
window actually appeared. It ends with one of two lines:

```
  [base] EVERY DOOR OPENED A WINDOW WHEN PRESSED.
  [base] 3 DOOR(S) DID NOT OPEN.        <- and it names them
```

> **Why it works that way.** It used to call `BaseWindow.open()` itself.
> Every picture came out perfect while the game was broken, because the
> buildings' `window:` actions were being dropped on the way through (see
> section 4). **A tool that reaches past the button cannot see a broken
> button.** If you ever write another screenshot tool, press the thing a
> player presses — it costs four lines and it is the difference between a
> picture and a test.

```
godot --headless --script res://tools/shop_check.gd
```
Every price on the Traveling Brewer's cart converted into WINS, and what a
ten-fixture season actually pays. See section 11c.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/shop_shot.gd
```
The cart with an empty purse and with a season's takings, and the Pub with
the ten-seat room forced on.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/brewery_shot.gd
```
The Brewery map photographed with five sections locked, then all six open,
then after one run of the chain with a barrel lagering. Getting there in a
real game is ten matches away.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/gate_shot.gd
```
The team builder photographed with `class_tree_gates_units` off and then
forced on, so you can see what turning that switch does before a player
does. It caught two bugs the day it was written — see its header.

```
godot --headless --script res://tools/class_tree_check.gd
```
The four files a class is spread over, checked against each other — and then
the tree WALKED on a throwaway save, so you find out what it costs before a
player does. See section 7e.

```
xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
    --script res://tools/class_tree_shot.gd
```
The Star Hall photographed empty, with the Star picker open, and with every
node filled — which in a real game is eight matches away.


```
godot --headless --script res://tools/brewery_check.gd
```
The six sections read back as a chain, which achievement opens each one, and
then **the walk**: a new game, every section open, the chain worked until it
runs dry. It prints what the starting stock is worth in bottles and what ran
out first. See section 11b.

**`sturmball_workbench.html`** is the spreadsheet editor: drop your `data`
folder into it and it edits every CSV with the right dropdowns, checks every
id and reference, and exports back out. It runs in a browser and uploads
nothing.

It has **five pages down the left**, above the file list:

| page | what it is |
|---|---|
| **Where things go** | every asset folder, and the **live** list of file names your spreadsheets are currently asking for — 148 of them today. Tick them off as you draw them |
| **Art & sizes** | **every kind of picture the game will ever ask for**, the box it is drawn into, the canvas to draw it on, how it is fitted, and which column names it. Forty kinds, with ticks and a *Copy as a work list* button. Every number on it was read out of the running game rather than guessed |
| **Handbook** | the rules the whole project obeys — how a CSV is read, what names a thing and what breaks if you rename it, the four actions that need a screen, where a number lives, what each tool measures *in*, the order to build content in, and the list of known gaps |
| **Reference** | the small languages: what you may write in a `Requires`, a `Do`, an ability, a Juice row |
| **Keywords** | the 49 words in 9 families the checkers test your cells against, and which 17 are planned rather than live |

**Where things go** and **Art & sizes** are two halves of one question. The
first is *which files am I missing*; the second is *how big should they be*.

There are two more in the game itself: **`content_report.gd`** prints a
readable audit of every spreadsheet, and **`install_check.gd`** runs on the
title screen and names anything missing, misplaced or duplicated.

---

## 15. Things that will bite you

**After a pull, a screen fails and drops you at the base** (8 Oct, the
Deck). A pull that adds a new script with a `class_name` can leave an open
Godot editor not knowing that name yet, and every script that uses it fails
to load. Close the editor and reopen the project (or run `godot --headless
--path . --import`). New code loads such scripts by path (`preload`) where a
failure would stop a match.

**Two copies of a script.** Godot registers a `class_name` once. A second copy
anywhere gives you `Class "X" hides a global script class` and then loads
whichever it feels like. `install_check.gd` finds these; the fix is always to
delete one.

**`.translation` files.** See section 5, point 4.

**Reserved words.** `reload` collides with Godot's own `Script.reload()` — a
static function called `reload()` is silently never the one that runs, which
is why every loader here has `reload_files()` instead. `when` is a reserved
word in Godot 4.2+ (match guards) and cannot be a variable name.

**Tabs, not spaces.** GDScript will not accept a mix. One space-indented line
kills the whole file, and the error names the line, not the cause.

**Dictionary access.** `row["thing"]` on a missing key is a hard crash;
`row.get("thing", default)` is not. Every loader in this project uses the
second form.

**Controls growing the wrong way.** When a Godot control needs more room than
its box, it grows in whichever direction `grow` says — and the default is
*both* ways. That is why the COMBAT bar used to be cut off by the bottom of
the screen and the log ran off the right. If a panel is half off the screen,
that is almost always why.

**Renaming a card.** See section 13.

**A loop over a bare `[...]` literal.** `for folder in ["a", "b"]` iterates an
UNTYPED array, so `folder` comes out untyped, so `var path := folder + name`
cannot be inferred and the file will not compile. Declare the list as
`Array[String]` first. **This has now cost five rounds in five different
files** — it is the single most common way to break a build here.

**Assuming two names are the same name.** A Star is called Gremory and its
nine units are the Sitri set. For months the checker reported that as two
problems and there was nothing to fix, because the *code* assumed a Star and
its set shared a word. The fix was a column (`Set`) that says which, not a
rename. **When a tool reports a problem you cannot find, check whether the
tool is asserting something nobody ever wrote down.**

**A Star with two abilities.** `Star Players.csv` has one `Front Side`, not an
Attack and a Defend. Writing both is not an error — the loader prefers them —
but it is not the design any more, and the second one will never be the
reason a Star is interesting. The Ultimate Side is.

**An action nobody handles.** A `Do` or `Action` term whose kind is not real —
`window:` before it was deferred, or any plain typo — used to be handed to the
condition language, which ignores what it does not know. The cell looked fine,
the button did nothing, and nothing anywhere said why. **That is now loud:** an
unrecognised term is named in the Output panel every time it runs. If a button
in your spreadsheet does nothing, look in the Output panel first — it will be
there.

**Adding a row to a list twice.** `room_screen.gd`'s `_row_frame()` puts the
row into the list *itself* and returns the box inside it. Six callers used to
finish with `_list.add_child(line)` on top of that, which asks Godot to give
a node a second parent. Godot refuses — once per row, in red. **Nothing
changed on screen**, because the frame was already in the list, so it looked
like a working screen that happened to print a hundred errors. That is the
worst shape a bug can take: harmless, loud and constant, until the Output
panel is so full of noise that the one line that matters scrolls away. If a
helper adds a node for you, say so in a comment above it, in capitals.

---

### Round AA additions

- **Round AB: `Status` in Questions.csv** is `open`, `answered` (built in a
  later phase), `built`, or `pinned` (your "test this later").
- **Diff your own commits.** The Rauhnacht file you sent this round was an
  older copy: every name had become "Unit Name" and the ability-ID columns
  were gone. I merged it by row and kept your Set Name swaps - but always edit
  the newest file (pull first), or the next round undoes the last.
- **A question window pauses the match.** Only for you, never in AUTO, so a
  soak or a tool never waits.
- **One Emblem at a time.** A side's Emblem is the Star on the pitch's.
- **The emblem bar and tracker are UNDER the duel window now** (layer 18).

### Round Z additions

- **A token changes the card a body plays.** Mid-match, the unit that was
  Matthias is a "Rose Unit". Anything that reads a squad DURING the match sees
  the token; at full time every original is put back before the squad is read.
- **The ability engine keys everything by card AND side.** Both teams can
  field the very same card (a friendly, a mirror match). If you write a tool
  that asks the engine about a card, say which side.
- **"Exile" is gone from the card texts.** If you write a new card, write
  "exhaust". The audit still reads an old "exile" as exhaust.
- **A Cost the side cannot pay means nothing happened** - not a trigger for
  the referee, not a use against its Max.

### Round Y additions

- **Edit a card's TEXT, not CardAbilities.csv.** That file is rebuilt from
  scratch by `tools/ability_rows.py` every time.
- **A ternary over two list literals is untyped** (`[a] if c else [b]`).
  It broke the SHOW button in round Y for a moment; `tools/ability_check.gd`
  caught it. The typed-array rule from the handover, again.
- **Fouls.csv was doubled.** About one card per match per side now.

### Round X additions

- **A set card's Name is now a save key for everyone who turned into it.**
  Rename Matthias and every player who became Matthias goes back to plain.
- **`make_chrome.py` will not overwrite the PixelLab art** unless you add
  `--placeholders`. If you want the old drawn chrome back, that is how.
- **A turning brew's cost has to be an item** (Items.csv). The brewery's
  bottles are a different counter (`res_bottle`), which is why the four
  turning brews cost reed, ash glass, bog iron and deep salt.

## 16. "I want to…" — the cookbook

| I want to | Open |
|---|---|
| add a new player | any unit CSV, or a new file with the same columns |
| add a whole new class | `ClassInfo.csv` + a unit CSV whose `Unit Type` matches |
| make a class unlockable | the `Requires` column of `ClassInfo.csv` |
| change how strong a tier is | `TierPowers.csv` — and read section 2 first |
| give a player an ability (league) | `Abilities.csv`, then the ability columns of the unit CSV |
| make an ability cost Ore | the `Cost` column of Abilities.csv: `ore:3` |
| make an Emblem's Basic side do something | write an `EMB_` row in Abilities.csv (copy one), then name it in the Emblem's `Basic Ability` column |
| make a card's ability work from its text | change the text, run `python3 tools/ability_audit.py` and `python3 tools/ability_rows.py`, then `ability_coverage.gd` |
| make a card switch to defender, force or negate | the C4 effects in Abilities.csv - or write the sentence on the card and run the two scripts |
| run many matches and see the numbers | `python3 tools/balance_report.py` |
| test with everything unlocked and every class ready | Dev screen > **TEST COMPLETE ENVIRONMENT** (a separate save) |
| see the zones and where every unit is heading | **Z** in a match |
| change how often a corner / drop ball / storm gust starts a round | `data/PlayMakerStarts.csv`, the `Chance` column |
| make units stand still less (or more) | `linger_seconds`, `edge_keep` in Tuning.csv |
| make a card swap in from the exhaust before a duel | an `exhaust_swap` row with Effect `swap_in_tier` (and a Max), plus what it does once in - or write "While in Exhaust: Swap this Unit with another Tier I ..." and run the two scripts |
| turn the Reveal question off (back to the SHOW button) | `reveal_after_pick` false |
| move or add a mine | `data/Mines.csv` (Across / Down on the pitch, Side you / them / both) |
| make mines give more or less Ore | `mine_ore_per_round`, `mine_reach` in Tuning.csv |
| change how many cards sit on the bench | `bench_size` in Tuning.csv |
| change what an Emblem's Basic side does | its `EMB_` row in Abilities.csv (Vassago, Glasya-Labolas, Caim, Gremory, Zepar, Sallos, Belphegor, Buer), or the Tuning rows `belial_`, `valefor_`, `haures_` |
| write or change an Ultimate | the **Ultimate Side column of Star Players.csv**, then `python3 tools/sync_ultimates.py` |
| change what Belial's ore shop sells | `data/OreShop.csv` |
| change what a free kick is worth, by distance | `data/FreeKicks.csv` (round AG) |
| change who is on the recruitment board, and what they cost | `data/RecruitBoard.csv` (round AH) |
| change the title screen's wallpaper, title or hero | `data/MainMenu.csv` (round AI) |
| turn a comic drawing into pixel art | `data/Pixelate.csv`, then `python3 tools/pixelate.py` |
| change the art style every picture is drawn in | `data/ArtStyle.csv` and `guides/ART_STYLE.md` (your references: `art_source/style_refs/`) |
| change a menu button's sound | `Hover Sound` / `Press Sound` in `data/MenuConfig.csv` |
| make or change a sound effect | `data/SoundRecipes.csv`, then `python3 tools/make_sfx.py` |
| loop a Suno or any other track | put the WAV in `art_source/suno/music/`, add a `MusicLoops.csv` row (Bars 8 or 16), run `python3 tools/make_loop.py`, name the `.ogg` in Audio.csv |
| change the menu tune (hand-written) | edit the notes in `data/songs/menu_blasmusik.csv`, the players in `data/SongParts.csv`, the speed in `data/Songs.csv`; run `python3 tools/make_song.py` (section 16d) |
| write a new tune for another screen | a new score in `data/songs/`, a row in `Songs.csv` and its players in `SongParts.csv`; run `python3 tools/make_song.py`, then name the `.ogg` in Audio.csv |
| dress another menu screen (layers, plank buttons, sounds) | rows for it in `data/ScreenLook.csv`, and one line in its `_ready()`: `Look.install(self, "<word>")` (section 16e) |
| carry music into another screen, quieter | an `Audio.csv` row for that screen with the **same Sound** and a lower Volume (section 16e) |
| a new or changed picture or song does not show up / sound different | since round AL the game reads music (.ogg/.wav/.mp3) and the menu pictures **straight from the folder**, so a changed file plays at once, even if Godot has not re-imported it. If something still looks old, restart the game. To refresh Godot's own copies: click into the editor (FileSystem progress bar), or Project > Reload Current Project |
| use the hand-written menu tune instead of Ludo's | put `menu_oktoberfest` in the `Sound` column of Audio.csv's `menu_theme` row |
| change the base music | `base_ludo_1`, `base_ludo_2` or `base_ludo_3` in the `Sound` column of Audio.csv's `base_theme` (and `base_theme_brewing`) rows |
| loop any music cleanly | a row in `data/MusicLoops.csv`, then `python3 tools/make_loop.py` |
| simulate 1,000 matches | `godot --headless --path . --script res://tests/sim_runner.gd` (matchups: `data/SimMatchups.csv`) |
| find over- and under-powered cards | `python3 tools/balance_analysis.py` -> `guides/BALANCE_ANALYSIS.md` |
| run the unit tests | `godot --headless -s addons/gut/gut_cmdln.gd` |
| stop a class's cards being listed in the Pub | `pub_hidden_classes` in `Tuning.csv` (`Rivals`) |
| let the player keep more recruits | buy a dorm, or lower `recruit_beds_kept` in `Tuning.csv` |
| make one class stronger in one tier | `tier_power_<class>_<tier>` in `Tuning.csv`, e.g. `tier_power_unkengeister_IV` |
| see what art is still missing, and what to make next | `python3 tools/art_status.py` -> `guides/ART_STATUS.md` |
| go back to the old flat free-kick bonus | `free_kicks` 0 in `Tuning.csv` |
| make a weak class's Tier IV Star stronger | `star_power_tier_IV` in `Tuning.csv` (a row per tier) |
| make Buer never fight below his printed power | `count_power_floor` 1 in `Tuning.csv` |
| change what Glasya-Labolas's Ultimate possesses | `glasya_objects` in `Tuning.csv` |
| see which tier a class is losing in | `python3 tools/balance_report.py 8 <Class>` - the "duels won, Tier" rows |
| make a kind of counter worth power in combat | `counter_power_<kind>` in Tuning.csv (e.g. `counter_power_burn`) |
| ask the player before an ability goes off | the `Ask` column of Abilities.csv: `yes` |
| answer my questions | `data/Questions.csv`, the `Your Answer` column |
| change what a Swan or a Rose token is | `EMB_ZEPAR_WINGS` / `EMB_GREMORY_ROSE` in Abilities.csv; `swans_count_as_tokens` in Tuning.csv |
| change what a passing move is worth (league) | `Combos.csv` |
| **change what a passing move is worth (Adventure)** | `AdventureCombos.csv` |
| add a new Adventure icon | `AdventureTraits.csv`, then breakpoints in `AdventureCombos.csv` |
| **add something to the bag** | a row of `Items.csv`. `Tab` says which of the three pages it lands on; leave it blank and `Kind` decides |
| **add a key item** | a row of `Items.csv` with `Kind: key` and no `Use`, then hand it out with a `Drops.csv` row or an `On Win` |
| **stop items being used mid-draft** | `draft_brew_button` in `Tuning.csv` |
| **make the referee stricter** | a row of `Referee.csv`, then `referee_id` in Tuning.csv. Run `referee_check` to see what it did |
| **change how a button feels** | three rows of `Motion.csv` — `button_hover`, `button_press`, `button_release` |
| **unlock every unit to test with** | `dev_mode` TRUE in Tuning.csv, then the DEV section of the pause menu |
| **make the art** | `data/ArtOrders.csv`, in order. Do number 1 first and pass it as the style image to the rest |
| **redo a piece of chrome from a new PixelLab sheet** | save it over the sheet in `art_source/pixellab/`, fix its `Cut` in ArtOrders.csv, run `python3 tools/cut_chrome.py` |
| **recruit a named player** | `recruit:I0` in any Effects / Do / Action / Reward. `named_recruits` TRUE for him to show |
| **add or remove names** | `data/Names.csv` |
| **make a new turning brew** | a Brews.csv row with For Class `Normal`, a Becomes, an Element and a number in `Drinks` |
| **make a card's ability work** | change its text if needed, then `python3 tools/ability_audit.py` and `python3 tools/ability_rows.py`. If its row says C2 or later, the engine needs that phase first |
| **answer a question about how an ability reads** | the `Your Ruling` column of `data/AbilityRulings.csv` |
| **see how many abilities work** | `tools/ability_coverage.gd` |
| **let a player into the Pub without a team** | `team_build_gate` FALSE in Tuning.csv |
| **let a card lean on the referee** | an Abilities.csv row with Effect `add_card_chance`, Scope `match` and a `Max`, then put its ID in the card's Attack Ability or Defend Ability column |
| **make repeat offenders easier to book** | `Caught Per Own Foul` and `Card Per Own Foul` in Referee.csv |
| **add a new class** | the **+ New class** button in the workbench. Emblem → Ultimate → Star → nine units, three times, then it writes all four files |
| **change what an Emblem is about** | its `Token` column. That is the word its nine units make and spend |
| **let another class of your element play** | the Element node of the class tree, or hand out `unlocked:Open Water` from anywhere |
| **make an Emblem easier or harder to turn over** | the number in its `Turns On`, then run `emblem_check` to see the spread |
| **make something at a building** | the `Action` column of `Buildings.csv` — `count:reed-6;count:brew_fire+1` |
| **let an item be used in an Adventure fight** | put `adventure_consume` in its `Tags` |
| **let an item be used on a player mid-match** | put `match_consume` in its `Tags`, and a `Use` of `brew:<id>` if it is a brew |
| **give the Adventure party more room** | `adventure_lane_height`, `adventure_party_rows` and `adventure_party_spacing` |
| **keep another tier out of the passing move** | `pass_skips_tiers` in `Tuning.csv` — `III;IV` |
| **give the sides longer to get back into shape** | `goal_pause_seconds` and `save_pause_seconds` |
| **make an icon something the player earns** | put `unlocked:Whatever` in the `Requires` column of `AdventureTraits.csv`, and hand that unlock out with a talent or a season reward |
| **write a player who damages an enemy the moment you pick them** | a breakpoint in `AdventureCombos.csv` with `Effect = strike`, `Target = focus` and `Lasts = once`. The `star_2` row has the whole note written on it |
| change the kick-off, the clash or the speed buttons | the `kickoff_`, `coin_` and `game_speed_` rows of `Tuning.csv` — section 7 |
| **put a sound on an exact coin call** | a `coin_exact` row in `Juice.csv` |
| **add a new ability trigger** | a row of `AbilityTriggers.csv`, marked `planned` until it is wired up |
| **write a card you can play face up** | give it an ability whose `Trigger` is `reveal` — `LORE_OPEN_HAND` is the worked example |
| **take the SHOW button off the cards** | `draft_reveal_button` in `Tuning.csv` |
| **write a card against a trigger that is not built yet** | do it. Mark that trigger `planned` and the card loads and waits |
| **ask for a keyword the game does not have yet** | a row of `Keywords.csv` with `Status: planned`. The sentence you write in `What It Does` is the specification |
| **find out what words I am allowed to write** | `Keywords.csv`, or the **Keywords** page in the Workbench |
| **write a card against an effect that is not built yet** | do it. Mark that word `planned` in `Keywords.csv` and the card loads and waits |
| **see what the other side actually does** | **ENEMY TEAM DATA** on the team shelf, or **TEAM** on the match HUD |
| **change what plays on a screen** | a `screen_opened` row in `Audio.csv` with `screen=thatscreen` |
| **make a screen keep the music from the one before** | give it a row naming the same `Sound` |
| **stop the music cutting between screens** | `music_follows_screen` in `Tuning.csv` |
| **find out why a sound is silent** | `tools/audio_check.gd`. It is nearly always a missing file |
| **change how big the pitch is** | the `pitch` row of `Stadium.csv`. It has to stay 16:9 |
| **change the village round the pitch** | `data/VillageGround.csv`, then `tools/make_village.py` (section 8b) |
| **move where visitors stand at the base** | `data/BaseSpots.csv`, one row per door |
| **change the base town map** | `data/BaseTown.csv`, then `tools/make_base_town.py` (one layer per part in `base_town.aseprite`) |
| **move the white lines in or out** | `pitch_inset_x` and `pitch_inset_y` in `Tuning.csv` - this moves the zones too - then `tools/make_pitch.py` |
| **see more or less of the village** | `camera_wide_ground` in `Tuning.csv` |
| **make the item icons bigger** | `icon_tile_size` in `Tuning.csv` |
| **add a spreadsheet without Godot mangling it** | run `tools/csv_import_fix.gd`, then delete `.godot` |
| **check a class's files line up before drawing its cards** | `tools/class_check.gd` |
| **read one Star's abilities** | they are printed on the team sheet, tagged ATK and DEF. There is no hover any more |
| **change how the opposition plays** | `EnemyPlay.csv`. Order low to high, first match wins |
| **give one opponent its own way of playing** | a word in the `Play Style` column of `Teams.csv`, and rows in `EnemyPlay.csv` with that `Style` |
| **script something the enemy does in one match** | an `EnemyPlay.csv` row with `When: flag:yourflag` and a `Do` — `brew:fire` pours one on the card they just took |
| **make players get tired** | `recovery` in `Tuning.csv`, and `Recovery.csv` for how long. Run `tools/recovery_check.gd` first |
| **let Adventure go out with four players** | it already does — `Squad Per Tier` of `MatchModes.csv` |
| **make the player own players rather than have them all** | `squad_ownership` in `Tuning.csv`, and `sign:Name` in an Effects column |
| **give somebody three players at the start of a new game** | a `new_game` row in `Progression.csv` with `sign:` effects |
| **play a scene when a season is opened** | the `Story` column of `Seasons.csv` |
| **stop players bobbing about off the ball** | `block_follow` and `drift_updown` in `Tuning.csv` — section 7 |
| **stop them standing in pairs** | `zone_lane_stagger` and `mark_level_floor`, and run `tools/shape_check.gd` |
| **stop the huddle when somebody shoots** | `surge_runners` and `recover_closers` |
| **change what happens when the ball goes out** | rows of `data/OutOfBounds.csv`, top to bottom |
| **bring back the 1–10 coin** | `out_of_bounds` = `false` in `Tuning.csv` |
| **get the ball back more often** | lower `out_of_bounds_player_chance` |
| **change how many goals a match has** | the `Chance` column of `ShotOdds.csv`, then `tools/scoring_balance.gd` |
| **make the keeper last longer** | lower `shot_stamina_bite` |
| **use a Fraktur** | put it on the `heading` row of `Theme.csv`. Only that row |
| **change how the whole game looks** | the `panel` row of `data/Theme.csv`. One cell |
| **draw my own windows and buttons** | 9-slice PNGs in `assets/ui/`, named in Theme.csv's `Image` column |
| **use my own font** | a `.ttf` in `assets/fonts/`, named in the `heading` / `body` / `small` rows |
| **make goals easier or harder** | the `Chance` column of `data/ShotOdds.csv`. `tools/shot_odds_check.gd` prints the grid |
| **stop an empty keeper being a certain goal** | the `0` row of ShotOdds.csv. It says 100 |
| **hide the keeper's percentage on the pitch** | `keeper_chance_on_pitch` in `Tuning.csv` |
| **change what a goal celebration does** | rows of `data/Celebration.csv`, top to bottom. `tools/celebration_check.gd` reads it back |
| **give one Star his own celebration** | put a picture file in that row's `Art` column |
| **make a goal shorter** | lower the `Seconds` on its rows, or delete rows. The checker adds it up |
| **put my club colours in the confetti** | `celebration_confetti_colours` in `Tuning.csv` |
| **turn the line-up parade off** | `line_up_parade` in `Tuning.csv` |
| **turn the team sheet off** | `team_sheet` in `Tuning.csv` |
| **stop the team sheet waiting for START** | `team_sheet_hold` in `Tuning.csv` |
| **hide what the enemy Stars do before kick-off** | `team_sheet_abilities` in `Tuning.csv` |
| **stop players fidgeting / standing on each other** | `unit_arrive_radius` and `unit_personal_space` in `Tuning.csv` — section 7, and run `tools/movement_check.gd` |
| **start a match without pressing START** | `kickoff_needs_button` in `Tuning.csv` |
| **give a class a crest** | the `Banner Art` column of `ClassInfo.csv`, and the file in `assets/team/` |
| **choose which eight icons a run carries** | the player does, on Edit Element Bonus. You decide what exists and what unlocks it — `AdventureTraits.csv` |
| change what is written over a player's head | the `plate_` rows of `Tuning.csv` — section 7 |
| make a brew change what somebody counts as | the `Becomes` and `Element` columns of `Brews.csv` |
| add a new enemy | `AdventureEnemies.csv`, and put its `Pool` on a biome |
| add a new biome | `Biomes.csv` + a pool of enemies + a drops table |
| add a bounty | `Bounties.csv` |
| change what loot drops | `Drops.csv` |
| add an item | `Items.csv` |
| change the league fixtures | `Season.csv` |
| add a competition | `Seasons.csv` |
| change match length or cycles | `MatchModes.csv`, or `Tuning.csv` for the defaults |
| make a hit feel harder | `Juice.csv` — the `Shake` and `Shake Scale` columns |
| turn screen shake off | `juice_scale` in `Tuning.csv` |
| attach a sound to anything | the `Sound` column of `Juice.csv`, or a row of `Audio.csv` |
| write a conversation | `Dialogue.csv` |
| add an achievement | `Stats.csv` to count it, `Progression.csv` to react |
| unlock something after N wins | `Progression.csv` with `count:matches_won>=N` |
| add a shop price | `count:gold-25` in an Effects column |
| add a talent | `Talents.csv` — `count:tune_<row>+<n>` reaches any number |
| translate the game | add a column to `Language.csv` |
| rebind a key | `Keys.csv` |
| change the main menu | `MenuConfig.csv` |
| find out why something is not showing up | the Output panel. The loaders say |

---

## 16b. The title screen, sounds and music (round AI)

### `data/MainMenu.csv` — what the title screen looks like

One row per thing on it. No file, no rows: it looks as it did before.

| column | |
|---|---|
| `Part` | `background` (the wallpaper — the first row wins), `layer` (a whole-screen picture drawn like the wallpaper, stacked in row order — round AN), `title` (the big word), `picture` (anything standing on it — any number of rows) |
| `Image` | the file. A picture may be a **strip**: `Frames` pictures side by side, all the same width |
| `Text` | the title's word (`STURMBALL`) |
| `X`, `Y` | the **centre**, on a 1920 × 1080 screen |
| `Width`, `Height` | how big to draw it (for the title, `Height` is the font size) |
| `Frames`, `FPS` | an animated strip; blank = a still picture |
| `Motion`, `Motion Settings` | round AN: makes the row move — see *The moving title screen* below |

As shipped:

- **The wallpaper:** the Oktoberfest riot (`assets/menu/menu_chaos_a.png`).
  The other one, `menu_chaos_b.png`, has the beer-tent stands at sunset; the
  beer hall from round AH is `background.png`.
- **The hero (round AK):** your sketch as a Marcinelle-school comic, foot
  on the ball, stein up (`hero_comic.png`; version B is `hero_comic_b.png`). The round AI backpacker
  (`hero_cheer.png`, 8 frames) is still there.
- **The title:** **STURMBALL** in gold.

### The moving title screen (round AN)

**Your sketch, built in.** The maypole view (at twice the resolution) is cut
into layers that move:

- **The sign** hangs on long ropes from the top of the screen and swings
  gently. **STURMBALL** is written on it and swings with it.
- **The clouds** drift slowly across the sky and wrap round seamlessly.
- **The maypole ribbons** sway like cloth: top right (tied at the top) and
  bottom left (tied at the bottom edge).
- **The menu buttons** hang on a Bavarian notice board in the middle.
- **An Alpendohle** with a Bavarian scarf flies in, sits on the notice
  board's roof for 5 seconds and flies off to the right. It follows **the
  song, not a timer**: it lands 5 seconds into the menu song every time the
  song loops, on the same beat (`sync=music; land=5`).

**Everything is two columns of `MainMenu.csv`:** `Motion` says how a row
moves, and `Motion Settings` holds its numbers as `name=value; name=value`.
Leave a number out and it keeps its default.

| Motion | for | numbers |
|---|---|---|
| `drift` | a layer — slides sideways for ever (clouds) | `speed` pixels a second (minus = the other way) |
| `sway` | a layer — waves like hanging cloth (ribbons) | `amount` pixels at the loose end, `speed` waves a second, `from` top / bottom (the tied edge), `reach` how far the ribbons hang, `wave` how stretched the ripple is (bigger = calmer), `phase`, `curve` |
| `swing` | a picture — swings round its top-middle (the sign) | `amount` degrees each way, `speed` swings a second |
| `bird` | a picture strip of 3 poses: wings up, wings down, sitting | `delay`, `fly`, `stay`, `leave` (seconds), `from` and `to` (x,y where it starts and flies off to), `flap` wing beats a second, `arc` how high it swoops. X / Y = where it sits. `sync=music` ties it to the menu song: it lands `land` seconds into the song, every loop (`delay` is then ignored; with the sound off it uses `delay` and flies once) |
| `follow` | the title row — written on the picture above it, moves with it | — |

- **The buttons** are placed in `MenuConfig.csv` (X, Y, Width, Height) inside
  the board's light panel: x 772–1183, y 689–1001.
- **The pictures** are in `assets/menu/layers/animated/`. Their sources, and
  the scripts that cut the layers, are in `art_source/pixellab/title_animated/`.
  The whole screen as one layered file is
  `art_source/aseprite/title_screen_animated.aseprite`.
- **To check it without watching:** `godot --path . --script
  res://tools/menu_motion_shot.gd` saves a picture a second for 13 seconds
  into `user://menu_motion/`.
- **The still screen it replaced** is
  `art_source/legacy/menu_round_an/MainMenu_maypole_still.csv`.

### Comic first, pixels second — the art style (rounds AJ–AL)

**Your rule:** every picture is drawn as a **Marcinelle-school comic
first**, and is pixelated afterwards.

**Since round AL, OpenAI paints the comic masters.** PixelLab's own drawings
always came out half pixel-art, so they could never look like your
Midjourney kicker. OpenAI's image model (gpt-image-1) can.

- **Characters away from the pitch** use this: the menu, the bar,
  conversations and portraits.
- **Players on the pitch** stay simple pixel sprites.
- **Ludo and Suno** make the music.

**The style is written down in two places:**

- **`guides/ART_STYLE.md`:** what makes it Marcinelle (ugly by
  exaggeration: noses, eyes, teeth, gangly or pot-bellied) and what does not
  (pig noses, ball heads, glossy shading).
- **`data/ArtStyle.csv`:** the words every art prompt is built from (`style`,
  `ugliness`, `line`, `colour`, `avoid`), the recipe (`pipeline`) and the
  character prompt template (`character_prompt`). **Change a row and every
  future picture changes with it.**

Your references are in `art_source/style_refs/`. **`ref_08.png`, your
Midjourney kicker, is the style reference sent to OpenAI with every
character.**

**How a picture is made:**

1. **The comic master.** OpenAI paints it at 1024 × 1536 on a transparent
   background. Two reference pictures go with it:
   - `ref_08.png` for the **style**;
   - your **sketch**, if there is one, for the **pose only**.

   It is saved in `art_source/openai/<thing>/`. The painting is done by the
   small helper on your Deck, `tools/mcp/openai_images.mjs`. Your key stays
   in `claude_desktop_config.json`.
2. **The pixel art.** A row of **`data/Pixelate.csv`**, then
   `python3 tools/pixelate.py`.

| column | |
|---|---|
| `Source` | the comic master |
| `Output` | where the pixel art goes |
| `Height` | pixels tall (the width follows). The screen draws it 2×, 3× … so keep the size you show it at a whole multiple |
| `Colours` | how many colours (32 for clean pixel art) |
| `Outline` | `yes` = a 1-pixel black ink line all round |
| `Ink` | colours darker than this become pure black ink (0 = off; about 45) |
| `Crop` | `yes` = cut away the empty space first |
| `Smooth` | **new in round AL.** `0` = off. `5`, `7` or `9` melt the fine hatching and paint texture **before** shrinking, so the result is clean, flat pixel art like your second image instead of noisy dots. 7 is about right for an OpenAI master |
| `Fill Holes` | a colour for see-through holes inside the figure. Only for PixelLab masters: OpenAI's transparency is clean, and filling would close the gap between an arm and the body |

| `Aspect` | **new in round AL.** For example `16:9`: trim the picture to that shape first, from the middle. Use it for full-screen backgrounds. Blank = keep the shape |
| `Flip` | **new in round AL.** `yes` = mirror it left to right, to turn a character round |

**ROUND AN: the art bible and a new title background.**
- **The art bible:** one sentence of style words, the `art_bible` row of
  `data/ArtStyle.csv`. It ends every PixelLab prompt. See
  `guides/ART_STYLE.md`.
- **The prompt builder,** `tools/art_prompt.gd`, writes a full prompt from
  `ArtStyle.csv`, so the style words never drift:
  `godot --headless --path . --script res://tools/art_prompt.gd -- pixellab "Lorelei siren"`
  (or `-- openai "..."`).
- **New title background:** `01_title_bg_b.png` (Pixelate.csv `title_bg_b`):
  the bumpy pitch, the Oktoberfest meadow, the beer town, a spooky bog and a
  sunset over the Alps. The other one is `01_title_bg_a.png` (the beer town by
  day). The old `01_field.png` stays in the folder. To swap, change the
  `background` row of `MainMenu.csv`.
- **PixelLab only, in layers (your decision):** all art is made with PixelLab
  from now on. The title screen is the PixelLab set now
  (`assets/menu/layers/pixellab/`, masters in `art_source/pixellab/title/`).
  The whole screen is also one layered Aseprite file:
  `art_source/aseprite/title_screen.aseprite`, made by `tools/make_aseprite.py`.
  See `guides/ART_STYLE.md` for how to edit it and bring a layer back.
- **The title screen now shows your base town (round AN, take 2).** The
  crowd, the brawl, the sign and the hero are the same. Behind them the
  camera stands at the right goal's end of a much bigger pitch: the big
  penalty box, the goal with its tall ball-stop net, the sandy path, the
  fields and the sky (`01_goal_end.png`, drawn with the base's `ground.png`
  as its style picture). The **Pub** (left) and the **Dorms** (right) are
  drawn again from the ground, massive and cut off by the screen edge.
  Their masters are in `art_source/pixellab/title_valley/` and their
  `Pixelate.csv` rows are `pl_title_pub`, `pl_title_dorms`, `pl_title_goal`
  and `pl_title_boards`. Take 1 (the whole valley with all the small
  buildings) and the old title background, brewery and tent are in
  `art_source/legacy/menu_round_an/`.
  **Take 3:** the Pub drawn x3 and further left, the Dorms flipped, no goal,
  the crowd and the boards half size (Scale 1) and further back, and the
  white lines painted out of the pitch for now (`goal_end_nolines.png`; the
  master with lines is `goal_end.png`).
- **The Stadium flag is off the base's top row (round AN).** Inventory hangs
  in its place, second from the left. The Stadium screen still exists.
- **Pitch boards, menu and base (round AN).** Like a German village club
  ground, low advertising boards now stop the ball: pictures of a stein, a
  pretzel, a sausage, a ball, a hop and a cow (no letters). On the menu
  they stand in front of the crowd (`06_boards.png`, three rows in
  `MainMenu.csv`). On the base they run all round the pitch:
  `BaseTown.csv` row `pitch_boards`, its own layer in `base_town.aseprite`
  (run `tools/make_base_town.py` after changing it).
- **Settings, the save screen and the menu button are PixelLab too:**
  `assets/ui/settings/pixellab/`, `assets/ui/save/pixellab/` (masters in
  `art_source/pixellab/menus/`), named in `ScreenLook.csv`. Layered files:
  `art_source/aseprite/settings.aseprite` and `save_screen.aseprite`
  (`tools/make_aseprite.py data/ScreenLook.csv <file> settings` or `slot`).
  Buttons and frames come from PixelLab's UI tool (`create_ui_asset`):
  the picture tool drew steins and sausages instead of a plank.
- **Everything else redone with PixelLab:** the UI skin (`Theme.csv`
  images, flat calm middles so text reads), all 39 icons (64 x 64), the team
  crest and formation picture, the match background (`Stadium.csv`:
  `stadium_back` + the unlockable `stadium_crowd`), and **one animated
  sprite sheet per class** (`assets/players/class_<Class>.png`, picked by
  `Tuning.csv` `placeholder_art_<Class>` for every card without its own
  Artwork). Originals are kept in `art_source/legacy/`. Not touched yet:
  the base screen and its buildings, Adventure Mode and the soccer field.
- **The tool comparison** (OpenAI, PixelLab, Ludo.ai, Claude by hand, a hybrid)
  is in `art_source/compare/`, with `comparison.png` side by side.
- **Pixelating on your Deck:** use `~/.venvs/sturmball/bin/python tools/pixelate.py`.
  That Python has Pillow installed; the system one can't install it.

**ROUND AM: every layer of the title screen, Settings and the save screen
was repainted in THE art style, Stammtisch-Comic.** That's the chaotic
German comic look of your Midjourney pictures; see `guides/ART_STYLE.md`
and the `stammtisch_` rows of `data/ArtStyle.csv`.
- **Same files, new pictures:** the file names didn't change, only the
  paintings behind them. The new masters are in
  `art_source/openai/stammtisch/`.
- **The hero comes in two iterations:** `hero_a_skinny.png` (on screen) and
  `hero_b_round.png`. Same face, opposite body.
- **New `Pixelate.csv` column, `Key Colour`:** a painting that came back
  with a filled background instead of a transparent one has that background
  cut away, but only where it touches the edge. The crowd uses `#fdf3d0`.

**The title screen is built from layers (round AL).** Every part of the
picture is its own painting, so each can be repainted, moved or swapped
without touching the others. OpenAI painted all of them in the **front
guy's style**: his clean picture was the style reference for every layer.
The prompts also ask for crisp neutral colours, and the new `Neutral`
column takes out any yellow tint that's left. All layers are pixel art
drawn at **Scale 2**, so every layer has the same pixel size.

They're drawn **back to front, in the order of the rows in
`MainMenu.csv`:**

| # | layer | file (`assets/menu/layers/`) | Pixelate.csv row |
|---|---|---|---|
| 1 | the empty pitch, sky and tree line, seen low from the touchline | `01_field.png` (the `background` row) | `layer_1_field` |
| 2 | the traditional Bavarian brewery, centre | `02_brewery.png` | `layer_2_brewery` |
| 3 | the Oktoberfest beer tent, right | `03_beer_tent.png` | `layer_3_tent` |
| 4 | the crowd behind the boards: three groups (A, B, C) side by side, then the same three flipped | `04_crowd_a/b/c.png` | `layer_4_crowd_a/b/c` |
| 5 | the brawl in the middle of the pitch | `05_brawl.png` | `layer_5_brawl` |
| 6 | the wide STURMBALL sign, then the `title` row that writes the name on it | `07_sign.png` | `layer_7_sign` |
| 7 | **the hero, in front** | `assets/menu/hero_comic.png` | `menu_hero` |

The menu buttons are drawn over everything.

The paintings themselves are in `art_source/openai/menu_layers/`.

**To change one layer:**
1. Repaint it, using the `character_prompt` recipe in `ArtStyle.csv`.
2. Save it over the file in `art_source/openai/menu_layers/`.
3. Run `python3 tools/pixelate.py`.

To move a layer, change its X and Y. To reorder layers, move its row.

**New `MainMenu.csv` columns:**

| column | |
|---|---|
| `Scale` | draw the picture at this many times its own pixels. **2 for every layer** keeps one pixel size across the screen. Width and Height still win if you type them |
| `Flip` | `yes` = mirrored left to right (the crowd uses it, so six pieces look like more people) |

**The title is drawn in its place in the list.** It comes right after the
sign, so the hero covers both: his stein is in front of the sign. The sign
sits slightly right of centre (X 1040) so the stein doesn't cover the "S".
The name is 76 points, about a quarter of the screen wide.

**If a layer is missing on screen,** check that Godot has imported it. Godot
imports new pictures when the editor window gets focus, and the FileSystem
panel shows a progress bar while it does. Since round AL the title screen
reads the PNG straight from the folder if it isn't imported yet, so a layer
no longer goes missing. The Output panel then says
`[menu] '...' is not imported yet`. Click into the editor once and the
message goes away.

**The `Neutral` column in `Pixelate.csv`** (0–1) takes out the yellow
"AI painting" tint. It makes the near-white parts (clouds, white walls,
foam) truly white and shifts every other colour by the same amount. The
layers use 0.5; the hero is left as he is.

**The white parts problem:** OpenAI's transparent background sometimes
removes white areas inside an object, like the brewery's walls, the tent's
stripes and the sign's diamonds. `Fill Holes #f7f5ef` paints them back.

**New `Pixelate.csv` columns this pass:**

| column | |
|---|---|
| `Widen` | `1.5` = make it 1.5× wider by stretching only the middle; the ends keep their shape. For buttons and signs |
| `Max Hole` | with `Fill Holes`: only fill see-through holes smaller than this % of the picture (`0.6` fills a ball's panels but not an arm gap). Blank = fill every enclosed hole |

`Crop` now ignores the faint haze AI paintings leave round a figure, so it
cuts tight.

### The buttons' sounds — two columns of `data/MenuConfig.csv`

`Hover Sound` and `Press Sound` name an `Audio.csv` row or a file in
`assets/audio/`. As shipped:

- **Hover:** `menu_hover` on every button.
- **Press:** `menu_start` on Start, `menu_back` on Quit, `menu_click` on the
  others.

### Sound effects from a spreadsheet — `data/SoundRecipes.csv`

- Every row becomes `assets/audio/<Name>.wav` when you run
  `python3 tools/make_sfx.py`. Install pyfxr first, once:
  `pip install pyfxr`.
- The columns are the classic sfxr dials, explained at the top of the script:
  - `Wave`: square, saw, sine or noise;
  - `Base Freq`;
  - `Freq Ramp`;
  - `Sustain`;
  - `Punch`;
  - `Decay`;
  - `Arp Mod` (the coin's jump);
  - `LPF Freq` (lower = bassier);
  - and a few more.
- **To change a sound:** change a number, run the script again, and listen
  in Godot.
- **Two sounds are ready but not used yet:** `coin_register` and
  `explosion_heavy`. Name them in any `Sound` column.

### The menu music — `tools/make_music.py` (replaced in round AL, see 16d)

- **What it is:** an Oktoberfest oom-pah polka on 1990s chiptune instruments
  (tuba, off-beat chords, an accordion-ish lead, kick, snare and claps).
  It's 32 bars, about 30 seconds, and it loops.
- **To change it:** the tempo, the chords (one per bar) and the melody (four
  notes a bar, `-` holds, `R` rests) are at the top of the script. Run it
  again and it writes `assets/audio/menu_oktoberfest.ogg`. The `menu_theme`
  row of `Audio.csv` plays it.
- **Ludo.ai** can make a richer version once its key works (see the README).

## 16c. Testing: the simulation, the analyst and the unit tests (round AI)

### `tests/sim_runner.gd` — 1,000 matches in under a minute

```
godot --headless --path . --script res://tests/sim_runner.gd
```

- **What it is:** the real AbilityEngine, cards, Emblem Basic sides, bank,
  keeper and `ShotOdds.csv`, played with no pitch. Its results go to
  `data/combat_telemetry.json`.
- **What it leaves out:** touches, mines, gravestones, fouls, and the Emblem
  race (so no Ultimates). So it under-rates Bergmännlein and the cards that
  need the pitch.
- **What it plays:** `data/SimMatchups.csv`, one row per matchup.
  - `Home` and `Away`: a class, `Normal`, or `random`.
  - `Home Picks` and `Away Picks`: `strongest`, `random` or `weakest`.
  - `Share`: how much of the run this row gets.
- **Settings:** `SIM_MATCHES`, `SIM_SEED`, `SIM_OUT`. `SIM_TRACE=Kurt`
  prints every duel that card plays, with the reason.
- **Tuning rows:**
  - `sim_classes`: which classes `random` draws from;
  - `sim_cycles`: the match length.
- **There are no hit points, so the numbers are:**
  - power per duel, standing in for DPS;
  - power faced per duel, standing in for damage taken;
  - keeper stamina taken;
  - duels a match;
  - abilities fired.

### `tools/balance_analysis.py` — the analyst

`python3 tools/balance_analysis.py` writes `guides/BALANCE_ANALYSIS.md`:

- **Classes** outside 45%–55%, from the fair "random classes" row.
- **Cards** against their **peers**: the other cards of the same tier and the
  same printed power, because a P5 should beat a P3. A card more than 15
  points better or worse than its peers is flagged.

`guides/BALANCE_REVIEW.md` is my reading of it as a designer.

### GUT — the unit tests

The GUT plugin is in `addons/gut/`. It's switched on in `project.godot`, and
its panel is at the bottom of the editor. To run every test from a terminal:

```
godot --headless -s addons/gut/gut_cmdln.gd
```

The tests are in `tests/unit/`; 27 of them pass:

| file | checks |
|---|---|
| `test_fouls.gd` | more triggers never lower the foul chance; a missed foul fills the bar; the bar fills and caps; a whistle empties it; a man's fouls are remembered; bookings only add to red; verdicts are always one of four words |
| `test_recruit_board.gd` | the board's whole lifecycle: names unique; signing costs and empties the place; can't sign twice; a match refreshes the board and frees names; releasing frees the bed |
| `test_shops.gd` | the cart: buying takes one off the stock; sold out = no sale and no charge; no money = refused, never negative. The ore shop never takes Ore below 0 |
| `test_clamping.gd` | keeper stamina stays between 0 and max; ShotOdds is always 0–100%; coins never underflow; bad indexes are refused; every book is safe when handed nothing |

**To add a test:** make `tests/unit/test_<thing>.gd` extending `GutTest`, and
write `func test_...():` with `assert_eq` / `assert_true`. GUT finds it.

## 16d. Music written note by note, and music from Ludo.ai (round AL)

**As of the end of round AL, the main menu plays the Ludo.ai Blasmusik
(`menu_oktoberfest_ludo`), your pick. The base plays Ludo option 1, and option 3
once the Brewery opens.** The hand-written polka below is kept as a spare,
`menu_oktoberfest`.

**The base music** comes from three Ludo loops in the menu's style. Each was
made with the menu prompt (augment prompt off, 40 seconds) with only the
mood changed:

- `base_ludo_1`, a beer garden: relaxed, F major, 104 BPM;
- `base_ludo_2`, a swaying beer-tent waltz in 3/4;
- `base_ludo_3`, a livelier polka in Eb with off-beat cymbals.

Their rows are in `MusicLoops.csv`. Switch by changing the `Sound` column of
`base_theme` or `base_theme_brewing` in Audio.csv.

**A hand-written Bavarian Blasmusik polka, with no AI.** Real recorded brass instruments play it, from the free
*GeneralUser GS* soundfont. Because every note is written down, nothing
creeps in as the song goes on: it plays exactly what's in the spreadsheet.
The Ludo.ai version is kept as a spare, `menu_oktoberfest_ludo`.

### The hand-written song: three spreadsheets

Run `python3 tools/make_song.py`. It writes `assets/audio/menu_oktoberfest.ogg`
as a perfect loop: the echo of the last bar is folded onto the first.

**`data/Songs.csv`** has one row per song.

| column | |
|---|---|
| `Score` | the score's CSV (`data/songs/…`) |
| `Output` | the `.ogg` the game plays. Name it in Audio.csv's `Sound` column |
| `Tempo` | beats a minute, 4 beats a bar (116 = a relaxed beer-tent polka) |
| `Soundfont` | the instruments (`art_source/soundfonts/GeneralUser-GS.sf2`, free: github.com/mrbumpy409/GeneralUser-GS) |
| `Reverb` | 0–1, how much beer-tent room |
| `Loudness` | the average level in dB |
| `Humanize` | the milliseconds the players may drift, so it sounds played, not programmed (0 = robot-tight) |

**`data/SongParts.csv`** has one row per player.

| column | |
|---|---|
| `Plays` | `melody` (the tune), `thirds` (the tune a third lower — the Bavarian sound), `bass` (root then fifth), `chords` (the short "pah"), `drum` |
| `Instrument` | a General MIDI number: 56 trumpet, 57 trombone, 58 tuba, 60 French horns, 71 clarinet, 21 accordion. For a drum: 36 bass drum, 38 snare, 42 hi-hat, 49 or 57 crash |
| `Volume` | 0–127. **0 switches a player off** (the clarinet ships off) |
| `Pan` | −100 left to 100 right |
| `Octave` | +1 or −1 to move a part up or down an octave |
| `Beats` | when bass, chords and drums play: `1 3`, `2 4`, `1& 3&`… |
| `Length` | how long a bass or chord note lasts, in eighth-notes |

**`data/songs/menu_blasmusik.csv`** is the score, one bar a row.

| column | |
|---|---|
| `Chord` | `Bb`, `F7`, `Eb`, `Cm`, `Gm7`… The tuba and the pah follow it |
| `Melody` | 8 eighth-notes: `D5` (the D above middle C), `Bb4`, `Eb5`, `F#4`; `-` holds the note before, `R` is a rest |

As shipped, it has 32 bars in Bb major, 66 seconds:

- **A** (bars 1–8): the tune.
- **A2** (bars 9–16): the tune with a higher ending.
- **B** (bars 17–24): the trio, in Eb, as Bavarian polkas do.
- **A2** (bars 25–32): the tune again, and the last bar leads back into bar 1.

### Your Suno tracks (round AL) — what plays now

The three WAVs you sent are in `art_source/suno/music/`. `tools/make_loop.py`
cut each one into a loop that is a **whole number of bars**, so the beat
never stumbles at the join.

| where | your track | the loop |
|---|---|---|
| main menu | **Sturm Ball** (round AN, 7 Oct) | the whole song, 29.4 s, with four crowd cheers between the shouts (see *The menu song: Sturm Ball* below) |
| base | Sonniger Nachmittag | 16 bars at 99 BPM, 38.6 s, from 26.3 s into the song |
| matches | Fussball im Bierzelt | 16 bars at 110 BPM, 35.1 s, from 36.7 s into the song |

**New columns in `MusicLoops.csv`:**

| column | |
|---|---|
| `Bars` | loop exactly this many bars (4 beats each). 8 or 16 is usual. Blank = the old way, any length between Min and Max Length |
| `Search From`, `Search To` | look for the loop only between these seconds of the song, for example the part you like best. Blank = the whole song |

The menu's tuba part is about 8 bars long, so its loop is 15 s rather than
30 s. A 16-bar loop would have to include the quiet part after it. If you'd
rather have 30 s, set `Bars` to 16 and empty `Start` and `Length`.

### The Ludo.ai version (kept as a spare)

`menu_oktoberfest_ludo.ogg`: Bavarian Blasmusik made by Ludo.ai, a brass band
in a beer tent, cut into a loop by `tools/make_loop.py`.

### What we learned about AI music, so it doesn't sound like AI

- **Keep it short: 40 seconds.** Given two minutes, Ludo keeps adding
  instruments and build-ups, and that's the AI giveaway. The game loops a
  short piece instead.
- **Name every instrument and ban the rest.** For example: "the same
  instruments, volume, tempo and key throughout, with no build-up".
- **Oktoberfest means a brass band, not an accordion.** Tuba with accordion
  or fiddle, a minor key, or a fast 2/4 polka all sound like **pirates or a
  sea shanty** to the AI. What worked: flugelhorns and tenor horns playing
  the tune in harmony, tuba, a baritone horn, a snare and a bass drum.
- **The winning version had Ludo's "augment prompt" switched OFF.** Ludo
  normally rewrites your description behind the scenes. With it off, it
  followed the words more closely.

**The exact prompt for the menu theme** (Ludo createMusic, 40 s, augment
prompt off):

> Bavarian Oktoberfest Blasmusik, a German brass band polka in a Munich
> beer tent. Major key, 4/4, 116 BPM. Flugelhorns and tenor horns play the
> melody in thirds; tuba oom on 1 and 3; baritone pah on 2 and 4; snare and
> bass drum. Gemütlich, cheerful, traditional German. No accordion, no
> fiddle, no pirate or sea shanty sound. The same arrangement for the whole
> track, no build-up. Instrumental loop.

### `data/MusicLoops.csv` — one row per looping track

Run `python3 tools/make_loop.py`. It finds the two moments in the track
that sound most alike, cuts between them, blends the join, evens out the
loudness, and writes the `.ogg` the game plays.

| column | |
|---|---|
| `Source` | the track as Ludo made it (`art_source/ludo/music/…`) |
| `Output` | the looping `.ogg` (`assets/audio/…`). Name it in Audio.csv's `Sound` column |
| `Start`, `Length` | leave **blank** and the script finds the cleanest loop and prints what it chose. Type seconds to force your own |
| `Min Length`, `Max Length` | when it is finding: the shortest and longest loop allowed |
| `Crossfade` | seconds of blending at the join (0.2–1) |
| `Loudness` | the average level in dB (−16 is right for music). Audio.csv's `Volume` applies on top |

The menu loop as shipped starts 1.94 s in and lasts 26.64 s. The join was
checked: no click, and the same loudness either side.

**The game now loops `.ogg` and `.mp3` music gaplessly.** Before round AL it
restarted the track when it finished, which could leave a tiny gap. `.wav`
music still restarts.

### Getting files from Ludo or PixelLab into the project

Claude's cloud computer can't reach Ludo's storage, but your Deck can. The
small helper `tools/mcp/openai_images.mjs` runs on the Deck. It paints
pictures with OpenAI, and its `download_file` tool saves any Ludo or PixelLab
result straight into the project. It's set up in `claude_desktop_config.json`
as `openai-images`, and your key lives only there.

## 16e. Settings and the save screen: the Beer Keller and the trophy room (round AL)

Both screens now have painted backgrounds in the title screen's style, made
of layers like the title screen. Every button on them is the oak plank,
with the same sounds as the title screen. **One spreadsheet runs all of it:
`data/ScreenLook.csv`.**

| screen | the room | its layers, back to front (`assets/ui/...`) |
|---|---|---|
| **Settings** (`settings`) | the **Beer Keller**, a vaulted brick beer cellar | `settings/01_keller_room.png`; the ceiling beam with lanterns, hops, bratwursts and pretzels (three pieces across the top); the barrel rack (left); the big barrel with a sleeping Bergmännlein (right) |
| **The save screen** (`slot`) | the **trophy room**, a panelled hunting-lodge hall | `save/01_trophy_hall.png`; pennants and scarves with the class symbols (four pieces); the trophy cabinet with cups, the golden stein and the creature emblems (left); one mounted trophy per class (right): the Unkengeist toad king, a Rauhnacht fire spirit in a lantern, the Lorelei swan with her harp, the Bergmännlein hood and pickaxe, and a bog lurker |

**`data/ScreenLook.csv`**, one row per thing, drawn top to bottom (back to
front), all **behind** the screen's own buttons and text:

| column | |
|---|---|
| `Screen` | `settings` or `slot` (any screen that calls `Look.install(self, "<word>")` in its `_ready`) |
| `Part` | `background` (fills the screen); `picture` (a layer); `shade` (a see-through dark box so the text stays readable); `margin` (`Width` = how far the content sits in from the left and right, `Height` = from the top and bottom); `button` (how every button looks and sounds) |
| `Image` | the picture |
| `X`, `Y` | the centre, on 1920 × 1080 |
| `Width`, `Height` | blank = the picture's pixels × `Scale` |
| `Scale`, `Flip` | as in `MainMenu.csv`: 2 for every layer; `yes` mirrors it |
| `Colour` | shade: `#RRGGBBAA`, where the last two digits are how solid it is (00–ff). Button: the text colour |
| `Hover Sound`, `Press Sound`, `Back Sound` | `Audio.csv` rows. Buttons that say Back, Close, Quit or Cancel play the Back Sound |

Plain buttons become planks. Tick boxes, sliders and drop-downs keep their
own look so they still read as what they are. The plank keeps its corners
at any button size; only its middle stretches.

The paintings are in `art_source/openai/settings_layers/` and
`art_source/openai/save_layers/`; their `Pixelate.csv` rows are
`keller_...` and `trophy_...`.

### Settings now work, and there is a Save button (round AN)

**The bug:** moving the volume sliders changed nothing. The game had only
one sound channel (Godot calls it a *bus*), Master, so every sound that
asked for Music, Effects or UI played on Master, and the Music slider turned
down a channel that did not exist. The sliders were also named SFX and
Voice while `Audio.csv` says Effects and UI. Text size did nothing either.

**Now:**
- **Every change happens at once** (drag Music and the music gets quieter
  while you drag) but is **only kept when you press Save**.
- **Back with unsaved changes asks:** Save, Don't save, or Stay. Leaving any
  other way puts the saved settings back.
- **Key bindings and the language** still save the moment you change them.
- **Text size** makes every bit of writing in the game bigger or smaller.
- **Vibration** turns controller rumble on and off (see below).

**`data/SoundBuses.csv`** is the list of sound channels, one row each, top
to bottom = the sliders on the Sound tab:

| column | |
|---|---|
| `Bus` | the name `Audio.csv` uses in its Bus column: Master, Music, Effects, UI, Voice |
| `Slider` | the words beside the slider |
| `Setting` | where `settings.json` keeps it. Don't rename an old one, or players lose their volume |
| `Default` | 0 to 1 on a fresh install |

Add a row and the game makes a new channel with its own slider; then point
`Audio.csv` rows at it. An `Audio.csv` row naming a channel that isn't in
this list plays on Master and is named in the startup report.

**`settings_unsaved_on_leave`** in `Tuning.csv`: `ask` (the window),
`save` (save without asking) or `discard` (throw them away without asking).

**Controller rumble: `data/Rumble.csv`.** One row per moment the pad
shakes. `When` and `Match` are the same moments `Audio.csv` uses
(`goal_scored`, `foul_shown` with `card=red card`, `save_made` with
`power>=4` ...), so anything that makes a sound can shake the pad too.

| column | |
|---|---|
| `When`, `Match` | the moment, exactly as in `Audio.csv` |
| `Weak` | the small, fast motor, 0 to 1 |
| `Strong` | the big, slow motor, 0 to 1 |
| `Seconds` | how long it shakes |

If two rows fit (a goal, and a star's goal), the stronger one wins. It ships
with goals, conceded goals, cards, Tier IV duels won, big saves and a tiny
tap on every shot. Delete a row to stop that shake.

### The menu music now carries on

**The title music keeps playing in Settings and on the save screen, without
restarting, and is quieter there.** Their `Audio.csv` rows
(`settings_theme`, `slot_theme`) name the **same Sound** as `menu_theme`
with a lower Volume (−17 instead of −9). When a screen asks for the track
that's already playing, the game no longer restarts it; it only glides to
the new Volume. Use the same trick to carry any music across screens: same
Sound, different Volume.

**The menu song is the normal, unedited song.** All 60 seconds play
exactly as Suno made it, at its own loudness. The last 6 seconds slowly fade
to silence, then it starts again from the top. That's the `suno_menu` row of
`MusicLoops.csv`: Start 0, Length 60, Crossfade 0, **Fade Out** 6,
**Loudness** `keep`.

**Two `MusicLoops.csv` columns for this:**
- **`Fade Out`:** the seconds at the end that fade to silence before the
  loop restarts. Blank = no fade.
- **`Loudness` `keep`:** leave the song exactly as loud as the file.
  Otherwise it's evened out to the dB you type.

**Button sounds are 6 dB quieter:** `menu_hover` is −20, and `menu_click`,
`menu_start` and `menu_back` are −12. The same four sounds play on every
button of the title screen, Settings and the save screen.

**To check it all:** `xvfb-run godot --path . --script res://tools/screens_shot.gd`
photographs the three screens into `user://` and prints the music on each.
It shows the same player at −9, −17, −17 and −9 dB, which means the track
never restarted.

**Crowd cheers over the menu song (round AN).** The cheering now sits on
top of your Untitled track at irregular moments, so it is clear and never
locked to the beat. The song itself is untouched. Each cheer is one row of
`data/MusicCheers.csv`:

| column | |
|---|---|
| `At` | seconds into the song where the cheer starts |
| `Volume` | dB: 0 = as loud as the cheer file, −6 = half as loud |
| `Pan` | −1 left, 0 middle, 1 right |
| `Cheer` | the sound: five Ludo.ai crowd bursts in `art_source/suno/cheers/` |

After a change, run `~/.venvs/sturmball/bin/python tools/mix_cheers.py`,
then rebuild the loop. The cheers belong to a song through the `Song`
column (a `MusicLoops.csv` ID).

### The menu song: Sturm Ball (round AN, 7 Oct)

The main menu now plays your Suno song **Sturm Ball** (prompt: 128 BPM
B-flat oompah brass anthem, zither and alphorn intro, group shouts
"Sturm! Ball!", dry mix, no crowd noise). Suno played it at about
123 BPM, not 128. The WAV is `art_source/suno/music/sturm_ball.wav`.

**The loop.** The song has a real ending: the last brass hit is at
28.0 s and it rings out to silence by 29.4 s. So it is not cut into
bars. The loop is the whole song: `Start 0`, `Length 29.4`, `Crossfade 0`,
`Fade Out 0.6` (only tidies the silent tail), `Loudness keep`. You hear
the ending, a short breath, then the zither intro again, like a stadium
song played on repeat.

**The cheers.** The ten old cheers were timed for the 60 s Untitled song,
so they would have landed on the new shouts. There are now four, in the
gaps (rows `s01`–`s04`, Song `suno_menu`):

| at | cheer | why there |
|---|---|---|
| 2.1 s | crowd swell (cheer_4) | the band starts after the intro; gone by 8 s |
| 9.6 s | short "hey!", right | finished before the first "Sturm! Ball!" (about 12.3 s) |
| 14.6 s | whistles, left | between the first shouts and the chant (18.3–20.5 s) |
| 21.0 s | big roar (cheer_1) | after the chant, gone before the last shouts (about 26.3 s) |

**Switching back:**

| you want | change |
|---|---|
| Sturm Ball without cheers | `MusicLoops.csv` `suno_menu` Source = `art_source/suno/music/sturm_ball.wav`, rebuild the loop |
| the old Untitled song (with its ten cheers) | `Audio.csv` `menu_theme` Sound = `menu_suno_untitled` (already built; its cheers are the `Song suno_menu_untitled` rows) |
| Untitled without cheers | the `suno_menu_untitled` Source = `art_source/suno/music/menu_untitled.wav`, rebuild |

Rebuild: `~/.venvs/sturmball/bin/python tools/mix_cheers.py`, then
`~/.venvs/sturmball/bin/python tools/make_loop.py suno_menu` (librosa now
lives in that venv too).

## 16f. The isometric players on the pitch (round AN)

On the tilted pitch every player is a small isometric figure that turns to
face one of **8 directions** and plays its own **idle, run, kick, tackle,
fall and cheer**. These pitch sheets are for the pitch only: cards, duels,
portraits and the story keep each card's own 12 × 39 sheet.

**What plays when:** run while a player moves (facing where they go); idle,
facing the ball, while they stand; kick on every pass and shot (the game
draws its own ball, so the drawing has none); tackle when they win the ball,
and fall for the player who lost it; cheer for the scoring side whenever
they stand still during a goal celebration. The scorer's knee slide is the
tackle animation.

**Two spreadsheets:**
- `data/PitchSprites.csv` — who wears which sheet. **Wears** is the card's
  own sheet file name (`class_Normal_female_bob.png`), its card name, or its
  class (`Normal`); the file name is tried first. **Pitch Sheet** is a file
  in `assets/players/pitch/`. List several with `|` and each player gets one
  and keeps it. A card with no row plays on its old sheet, as before.
- `data/PitchAnims.csv` — where each animation sits on a sheet. Each takes 8
  rows from **First Row**, one per direction: east, south-east, south,
  south-west, west, north-west, north, north-east. **Frames**, **FPS** and
  **Loop** as in `Animations.csv`. **PixelLab** is the animation's name in
  the PixelLab export.
  **Stand-in** (optional) is what a sheet plays instead while it has no
  rows for this animation yet.

**Drinking on the pitch** (10 Oct). When you use a drink from the bag on a
player during a match, his figure plays `drink` once: he lifts the beer,
gulps and wipes his mouth with his arm. It is the `drink` row of
`PitchAnims.csv` (rows 48-55); its Frames and FPS set how long it lasts.
Until a look's sheet has the drink drawn, it plays its Stand-in (`cheer`).
`Tuning.csv` `pitch_drink_stands_still` (true) stops him on the spot while
he drinks; a player with the ball always keeps running. Drafts:
`art_source/pixellab/iso_players/drink_drafts/`.

**Ten looks for The Club** (Anthony: no red nose, and people of different
skin colours and backgrounds in the same comic style). Five men (`club_m1`-`m5`: light with brown hair,
dark brown and curly, olive with a beard, East Asian, ginger with freckles)
and five women (`club_f1`-`f5`: blonde ponytail, brown with plaits, East Asian
bob, afro puffs, short ginger). Every new player gets a random one (picked by
their random name) and keeps it, so skin colour, hair colour and style vary. All six were drawn with PixelLab's style copy of the
approved player, so they match. Add a look: draw it, build its sheet, add
its file to the right row of `PitchSprites.csv` with `|`.

**The other classes** (two looks each, same style): Rivals (stubbly man,
woman with a ponytail; grey and blue), Lorelei (water spirits: a woman of living
water, a river nymph with scales; teal), Rauhnacht-Feuergeister (flame figure, charcoal with a Perchten
mask), Bergmännlein (bearded dwarf in a red cap, dwarf woman with braids
and a helmet), Unkengeister (warty toad, fire-bellied toad), Brandteufel
(fire-devil man and woman with horns). Their rows in `PitchSprites.csv`
are by class, so every card of the class gets one of its two looks.

**Size:** `pitch_sprite_scale` is 0.8 (Anthony's pick A, so the pitch is not
crowded).

**Grey when not in play** (Anthony: the grey shows who is not in the Play
Maker session, so you can follow the play). A player in the session is in
full colour; everyone else is drained of colour, and a spent player is also
dark. `pitch_sprite_rest_saturation` (0 = fully grey, 1 = full colour) and
`pitch_sprite_rest_brightness` set how strong it is.

**Only during a Play Maker** (Anthony, 8 Oct). The grey goes on at the
**PLAY MAKER!** call and comes off when that round's shot is over (and at
every Star swap). The rest of the time **everyone is in full colour**, spent
players too. A Star picked in its tier counts as in the Play Maker. To film
it: `godot --rendering-driver opengl3 --resolution 1280x720 --path .
--script res://tools/play_maker_film.gd`, then
`~/.venvs/sturmball/bin/python tools/make_film_gif.py out.gif`.

**More Tuning.csv dials:** `pitch_sheet_cell` (frame size, 72),
`pitch_sprite_scale` (how big they are drawn), `pitch_sprite_lift` (moves
the figure up so the feet sit on the spot), `pitch_ground_squash` (how flat
the tilted ground is; it decides when a run counts as north-east rather
than east).

**Making a sheet:** animate the character in PixelLab, download it (the
character's Download button), unzip it into
`art_source/pixellab/iso_players/<name>/`, then run
`~/.venvs/sturmball/bin/python tools/make_pitch_sheet.py art_source/pixellab/iso_players/<name> <name>`.
It writes the sheet, a layered Aseprite file (one layer per animation) in
`art_source/aseprite/players/pitch/`, and a preview GIF next to the export:
one row per animation, one column per direction. A missing direction is
filled with the standing pose and the script says so.

**To watch it in a match:** `godot --path . --script res://tools/pitch_sprite_shot.gd`
plays a Club match and saves frames round the ball into `user://pitch_shot/`.

## 17. A short glossary

**Tier** — one of four slots your squad is built in. See section 2.
**Rung** — one power value within a tier. Tier I has rungs 0, 1 and 2.
**Cycle** — every tier having fielded everybody it has. Resets the Star
rotation in a league match and the pile in Adventure.
**The pile / the stack** — the running collection of icons in an Adventure
fight.
**Breakpoint** — a row of AdventureCombos.csv: "at 3 Fire, this happens".
**Held vs once** — a breakpoint that is true while you hold it, versus one
that fires the moment you reach it.
**Icon / trait** — a tag a player brings to the pile, out of
AdventureTraits.csv.
**Layer** — one band of an enemy's health, with an optional soak.
**Soak** — damage taken off every hit into a layer. It slows you; it can
never stop you.
**Walkover** — a completely empty tier. Adds nothing to your hit and doubles
theirs.
**Juice** — shake, flash, pop, slow-motion and sound. All of it in Juice.csv.
**Haul** — what you are carrying in an Adventure run, lost if everybody goes
down.

## Readable menus (round AN)

Anthony's note: the Settings and Choose a Save screens had icons and words
off-centre and hard to read, and the intro text was small and ragged.

- **Icon-and-words buttons** (every Settings tab, Back, Save, the key
  buttons, the save tiles' Settings button) keep the icon and the words
  inside the frame, centred. A word too long for its button shrinks instead
  of being cut off. Tuning.csv: `button_text_size` (18), `button_icon_fill`
  (0.8), `button_inset` (6).
- **Settings**: every word is `settings_text_scale` (1.25) times its old
  size, and words on the cellar painting sit on the see-through black plate
  (`text_backdrop_alpha`, the same rule as the match).
- **Choose a Save**: the words sit inside each tile instead of on its
  border. `save_tile_text_size` (20), `save_tile_small_size` (15),
  `save_tile_padding` (18).
- **Conversations** (the intro, the bar, every story scene):
  `story_text_size` 32, `story_name_size` 32, `story_hint_size` 16,
  `story_choice_size` 32. The pixel font is drawn 16 high, so 16, 32 and 48
  stay crisp; the old 21 was what made it look ragged.
- **Faces of different sizes**: StoryArt.csv `Scale` (see above).

**Every screen, not only these** (Anthony: the base, the buildings,
Adventure, the match). Three game-wide rules, put on by `ThemeBook.dress()`,
which every screen and the match pass through:

1. **Smooth words** (`text_smooth`, true): the font keeps smaller copies of
   every letter, so any size is clean, not only 16, 32 and 48.
2. **A smallest size** (`text_min_size`, 14): a screen that asks for
   smaller gets 14. Left alone: words that wrap inside a designed box (a
   longer size would run over), words that shrink themselves to fit (banner
   titles, button words) and the players' name plates. A label that cuts
   off at the edge of its box only grows as far as the box allows.
   Settings > Text size multiplies on top. 16 is easier to read but some
   tight boxes (Adventure's combo tiles) start to cut off.
3. **The see-through black plate** (`text_backdrop_alpha`) behind any word
   that sits straight on a picture. Words on a panel or a button keep
   theirs. An empty label shows no plate.


## The Match Maker, and two tabs gone (round AN)

**Play a match** (the flag on the base) opens **the Match Maker**: a small
window in the same frame as every other box, with one button per row of
`data/MatchMaker.csv`.

A match is counted in **Play Maker cycles**, 30 minutes of clock each.

| Button | Plays | Length |
|---|---|---|
| **Normal Match** | `friendly` | 3 cycles, 90 minutes, three Stars (what the flag always played) |
| **Test Match** | `friendly_test` | 2 cycles, 60 minutes, one Star swap |
| **Quick Match** | `friendly_cycle` | 1 cycle of 3 rounds, 30 minutes, one Star |

`MatchMaker.csv` columns: **Words** (the button), **Icon** (`art|glyph`: an
icon file in `assets/icons/`, and the characters shown until it exists),
**Mode** (a `MatchModes.csv` ID: that row sets the clock, cycles, rounds,
Star swaps and what it pays), **Under** (the line under the button),
**Requires** (hides it until true). **A new length is two rows**: one in
`MatchModes.csv`, one here.

**No Extra Abilities** (Anthony, 8 Oct) is a switch at the top of the
window, OFF unless you turn it on. ON, the match you pick plays on **base
power only, for both sides**: no ability fires (attack, defend, Star,
Emblem), no ability asks you anything, a brew already on a card does
nothing and the bag will not pour one mid-match, and the season's
difficulty bonus is not added. The duel window says "no ability" for every
card and the kick-off says **NO EXTRA ABILITIES**. Every other way into a
match (the season, Adventure, the Tutorial) leaves it off. Film one with
`FILM_PLAIN=1` in front of the `play_maker_film.gd` line above.

- A shorter clock squeezes the Play Makers in by itself: the last one comes
  as long before the final whistle as in a full match (8 minutes).
- Test and Quick pay a little less than a Normal Match (`Rewards` columns).
- While a story match stands in for the friendly (the first match of a new
  game), the flag skips the Match Maker and starts that match, as before.
- To check it: `godot --path . --resolution 1920x1080 --script
  res://tools/match_maker_shot.gd` presses the real flag and saves the
  window, the bag, Team Build and two bird landings to `user://match_maker/`.

**The bag has no Keys tab** and **Team Build has no Talents tab**. Both are
one row of `Tuning.csv`:

- `inventory_tabs` = `items;resources` (add `;keys` to bring it back). Keys
  are still carried and still open their gates; they are only not listed.
- `team_build_tabs` = `Star Hall;Your Teams` (add `;Talents` to bring it back).

## Bavarian sound effects (round AN, 8 Oct)

**Every sound effect in the game is new** (your notes: "some older sound
effects are really hurting the ears ... replace ALL sound effects with
bavarian sounds", then "these are supposed to be quick sound effects").
The music is untouched.

- **Your picks:** you chose sound by sound on the sound board. Each sound
  is one of two sets:
  - **classic** (27 sounds): built from sine waves and noise - the full-time
    fanfares, the duel abilities, hits, menu hover and back, most of the base.
  - **band** (28 sounds): one quick idea each on the real recorded
    instruments of the GeneralUser GS SoundFont the songs already use (tuba,
    trombone, trumpet, accordion, dulcimer, cow bell, wood blocks, bass drum),
    plus synthesized thumps and beer.
- **What each one is:** `data/SoundCredits.csv`, one line per file: what you
  hear, which Audio.csv rows play it, the source and the licence.
- **Where they live:** `assets/audio/bav_*.ogg`. Audio.csv's `Sound` column
  names them; every row's ID stayed the same, so Juice.csv, Buildings.csv,
  Visitors.csv, MenuConfig.csv, ScreenLook.csv, Dialogue.csv and
  OutOfBounds.csv needed no change.
- **Kind to ears:** every file is low-passed (nothing shrill), faded in and
  out, brought to the same loudness and kept under -1 dB so nothing clips.
  How loud each plays is Audio.csv's `Volume`, as before.
- **Swap one to the other set:** the `PICKS` table in
  `tools/make_bavarian_sfx.py` says `classic` or `band` for every sound.
  Change the word, then `python3 tools/make_bavarian_sfx.py bav_goal`
  remakes that one; no name remakes them all and rewrites SoundCredits.csv.
  Needs numpy, scipy, tinysoundfont (`pip install --no-deps tinysoundfont`)
  and ffmpeg.
- **Undo one completely:** each Audio.csv note names the file it replaced
  (still in `assets/audio/`). Put that name back in `Sound`.
- **Spares, ready to use:** `drink_big` (three gulps - for the tutorial's
  drinking window), `woods_birds` (a bird in the trees) and `farm_moo` (a cow
  on the Alm). Name one in a `Sound` column.
- **Licence:** the classic set is our own. The band set uses GeneralUser GS
  by S. Christian Collins, free for any use including commercial; a line
  in the game's credits is appreciated.

## Conquests: a banner for a mode that is not built yet (round AN, 9 Oct)

**The torn, old flag with the black infinity** hangs at the right end of the
base's top row. It is **Conquests**, the Draft Mode: the replayable roguelite
you described (a run into the realm of the Myths, a draft from your unlocks,
players sacrificed to the infinite realm, a high score on the menu board).
**Nothing of the mode is built.** Pressing the banner only opens a "not open
yet" note. The idea is written up in `guides/CONQUESTS.md`.

| To change | Where |
|---|---|
| The banner's name, the note's heading and words | `Language.csv` `conquests_button`, `conquests_title`, `conquests_soon` |
| The banner picture | `art_source/pixellab/banners/cloths/conquests.png` (its own cloth) and `emblems/conquests.png`, then `tools/make_banners.py`. Both are stand-ins made by `tools/tear_cloth.py`; ArtOrders.csv `conquests_banner` is the PixelLab order |
| Its own cloth for any other banner | drop `cloths/<name>.png` next to the shared `cloth.png` and run `make_banners.py` |

It is left out of both tutorials, where the row is already full.
`tools/conquests_shot.gd` presses it and photographs the note.
