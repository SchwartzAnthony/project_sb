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
  src/core/       loaders, rules and shared helpers (51 scripts)
  src/ui/         screens (30)
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
| `assets/audio/` | every sound and every piece of music | `.ogg` for music (it loops properly and is a tenth of the size), `.wav` for short effects | Audio.csv `Sound`, Juice.csv `Sound`, Biomes.csv `Music`, Dialogue.csv `Music` |
| `assets/icons/` | small square pictures — trait icons, item icons, menu glyphs | `.png` with transparency, 64×64 or 128×128, the same size across a set | AdventureTraits `Icon`, AdventureCombos `Icon`, Items `Art`, MenuConfig `Art Path`, AdventureSpawns `Art` |
| `assets/players/` | card spritesheets, one per card | `.png`. Default grid is **12 × 39** — write an Animations.csv row for anything else or the card shows as a sliver | any unit CSV's `Artwork`, Brews `Artwork` |
| `assets/goalies/` | keeper art | `.png` | Goalies `Artwork` |
| `assets/base/` | the base and its buildings. A file called `background` here is the backdrop | `.png` / `.jpg`. Buildings are placed by X and Y (0–1 across the screen), so draw them to stand alone | Buildings `Art` |
| `assets/portraits/` | faces for dialogue and base visitors | `.png` with transparency | Visitors `Portrait`, Dialogue `Portrait` |
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
```

**`count:` and `flag:` are the escape hatches.** A shop price is
`count:gold-25`. An achievement is `flag:beat_the_keeper`. Base building is
`count:wood+10`. None of that needs new code — you write it in a cell.

A special case worth knowing: **`count:tune_<row>+<n>` edits a row of
Tuning.csv.** That is how talents work. `count:tune_press_speed+12` adds 12
to the `press_speed` row for as long as the talent is held. Any Tuning row
can be driven this way.

The rules are in `src/core/dialogue_grammar.gd`, and a malformed term is
reported by name on load rather than silently ignored.

---

## 5. How the game reads a spreadsheet

Five things worth knowing before you edit anything.

**1. Files are identified by their COLUMNS, not their names.** A units file is
anything with a `Unit Type` column and a `Base Power Left` column. You can
call it `Units Set FO2 - Whatever.csv`, drop it in `data/`, and it loads. The
same is true of brews, enemies, biomes and the rest. **Adding content usually
means adding a file, not editing one.**

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
| `Name` | the card's name. Used as its identity everywhere — **renaming a card breaks old saves** |
| `Player Type` | `Normal` or `Star` |
| `Base Power Left` | **ATTACK power. This is the tier slot.** See section 2 |
| `Base Power Right` | defence power |
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

**At a restart both sides walk back into shape first.** The break is ended the
moment the ball is dead rather than when play resumes, and then the game holds
for a couple of seconds — the keeper stands there with the ball while everyone
gets home. Nobody sprints; they simply set off earlier and the restart waits.

| Tuning row | |
|---|---|
| `goal_pause_seconds` | the hold after a goal. `2.0` |
| `save_pause_seconds` | the hold before the keeper kicks. `2.0` |
| `goal_kick_tier` | which tier the keeper aims at. `III` |

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

### The speed buttons

**1x is always there. 2x, 4x and 8x are shown greyed until they are unlocked,
and pressing a locked one says so** rather than doing nothing.

That is deliberate: a button you cannot press yet is a thing to want, and a
button that is not there is a feature the player never learns exists. It is
also not `disabled` in the Godot sense — a disabled button swallows the click
and so cannot tell you why nothing happened.

| Tuning row | |
|---|---|
| `game_speed_buttons` | `true` and 2x / 4x / 8x work |
| `game_speed_buttons_needs` | a `Requires` condition that must pass as well — e.g. `unlocked:Fast Forward`, handed out by a talent or a season reward |
| `game_speed_locked_words` | what a locked one says when pressed. Word it to match whatever you called the unlock |

**Holding the mouse button or the spacebar through a duel still hurries it
along whatever these say.** That is a different thing and it is always on.

**AUTO sits beside the cards**, not in the corner. It is the button that takes
the choosing over from you, so it belongs where the choosing happens.

| Tuning row | |
|---|---|
| `auto_button_x` | across the screen. `0.5` is the middle |
| `auto_button_y` | down the screen. **Leave it blank** and it follows the card row — half a card below `card_row_y` — so moving the cards moves the button with them |

### How a player is labelled — the nameplate

A player reads the same in a league match and in Adventure:

```
        Silver-Rhine          <- the name, over the head, centred
            ,---.
           ( o o )            <- the artwork
            `-^-'
      Tier I        P: 2      <- at the feet. Tier left, Power right
      [==========    ]        <- Adventure only: the stamina bar
```

A league player has no stamina — only the keeper does — so there is nothing to
draw a bar from and twenty-two of them would say the same thing anyway.

The name has the class taken off the end of it: *Songbound Shore Lorelei*
becomes *Songbound Shore*, because the class is on the end of every card in a
set and is already obvious from who is standing there. The full name is still on
the card, in the log and in the team builder.

| Tuning row | |
|---|---|
| `plate_names` | `false` hides every name in both modes. Tier and Power stay |
| `plate_name_size` | the name over the head. `13` |
| `plate_stat_size` | the Tier and Power at the feet. `11` |
| `plate_width_max` | the widest a plate may get, in pixels. `150` |
| `plate_name_width` | how wide a name may be, **as a multiple of the window under it**. `1.0` = never wider, which is what stops eleven names in a crowd writing across each other. Anything longer is cut with a … |
| `plate_gap` | pixels between the body and the first label. `5` |

> **The labels are placed from the drawn character, not from the frame.** A
> spritesheet frame is mostly transparent padding and every sheet has a
> different amount, so anything measured from the frame floats. Each texture is
> measured once, so a label hugs the body whatever the padding is — and it keeps
> working when you replace the art.

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

Items: `ID`, `Name`, `Kind`, **`Tab`**, `Stack`, `Art`, `Use`, `Target`,
`Requires`, `Description`. Every item is a counter in the save, so anything
that can test a counter can test an item.

`Use` is what happens when it is used in a fight — `revive`, `heal:6`,
`heal:3;all`, `hit:4`. Blank means it is not usable.

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

#### A brew is in the bag without being an item

You never pick a brew up. `Brews.csv` already says what one **costs** in
materials and what must be **unlocked** before it can be poured, so a brew is
in your bag when its `Requires` passes and is clickable when you can pay its
`Cost`. Nothing new is stored anywhere. One you cannot afford is still shown,
greyed, with the price — a brew you are two Reed short of is a thing to go and
get.

#### Pouring one on a card mid-draft

Every card in the match draft has a small **flask in its top-left corner**.
Pressing the card chooses that player; pressing the flask opens the Inventory
and pours a brew on them there and then — the card changes class, art and
abilities while you are still deciding.

It is the same pour the Pub does: the same cost, the same unlock, the same
`For Class` rule (a Fire Brew written `For Class: Lorelei` is refused on a
Brandteufel, out loud). It is always a **one-match** brew — a permanent
decision in the middle of a match is not something anybody meant to make — so
the final whistle takes it off again, which is the same line that has always
cleared them.

| Tuning row | |
|---|---|
| `draft_brew_button` | `false` takes the flask off the cards and brews go back to being poured at the Pub only |

---

## 9. `data/Tuning.csv` — 233 numbers

Three columns: `Key`, `Value`, `What it does`. Every number the game uses that
is not content lives here. Groups, by prefix:

| Prefix | Rows | What |
|---|---|---|
| `adventure_` | 54 | the run, the fight, the lane, the windows, the timings |
| `juice_` | 5 | how much shake, flash and slow-motion the whole game gets |
| `card_` | 6 | card sizes |
| `friendly_` | 3 | how a scratch opponent is matched to you |
| everything else | ~135 | the match, the pitch, the menus, the economy |

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

## 11. The base, and everything around a match

**`data/Buildings.csv`** — `ID`, `Name`, `Description`, `Requires`, `Art`,
`X`, `Y`, `Action`. The base is a map of buildings; `Action` says which screen
a building opens. A `Requires` that does not pass means the building is not
there yet.

**`data/Visitors.csv`** — `ID`, `Name`, `Portrait`, `Requires`, `Story`, `X`,
`Y`, `Once`. Somebody standing in the base with something to say.

**`data/Brews.csv`** — `ID`, `Name`, `Requires`, `For Class`, `Becomes`,
`Element`, `Attack Ability`, `Defend Ability`, `Cost`, `Permanent`.

A brew is an overlay on a card. `Becomes` changes its class; `Element`
changes its Adventure icon; the two ability columns give it abilities for the
league. `Cost` is `reed:6|bog_iron:2`. `Permanent` blank means it wears off
after one match.

**`data/Talents.csv`** — `ID`, `Name`, `Tree`, `Tier`, `Parent`, `Requires`,
`Cost`, `Effects`. A talent tree. `Effects` is the condition language, and
`count:tune_<row>+<n>` is what lets a talent change any number in Tuning.csv.

**`data/Progression.csv`** — `ID`, `When`, `Requires`, `Do`, `Once`. The
glue: when *this event* happens and *these conditions* hold, do *this*.
`When` is a game event (`base_opened`, `match_ended`, …). This is where
achievements, unlocks and story triggers are wired without code.

**`data/Stats.csv`** — `Counter`, `Event`, `When`, `Amount`, `Group`,
`Label`. Every number the game counts. A counter name may contain `{card}`,
which makes one counter per card — that is how the post-match screen lists
your scorers. Anything counted here can be tested with `count:` anywhere else.

---

## 12. Words — dialogue, localisation, keys

**`data/Dialogue.csv`** (and `data/tutorial/Dialogue.csv`) — a node graph in
a spreadsheet. `Scene`, `Node ID`, `Speaker`, `Portrait`, `Side`, `Animation`,
`Background`, `Music`, `Text`, `Next`, `Requires`, `Effects`, and then three
sets of `Choice N Text / Next / Requires / Effects`.

A line with no choices runs on to `Next`. A line with choices stops and asks.
A choice whose `Requires` fails is greyed out rather than hidden, so the
player can see what they missed.

**`data/Language.csv`** — `Key`, `English`, `Deutsch`, `Notes`. Add a column
for a new language; the game finds it. Any text the game shows goes through a
key here.

**`data/Keys.csv`** — `Action`, `Label`, `Group`, `Default Key`, `Default
Button`. Keyboard and controller bindings, rebindable in Settings.

**`data/MenuConfig.csv`** — `Button ID`, `Label`, `X`, `Y`, `Width`,
`Height`, `Action`, `Art Path`. The main menu, laid out in a spreadsheet.

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

**`sturmball_workbench.html`** is the spreadsheet editor: drop your `data`
folder into it and it edits every CSV with the right dropdowns, checks every
id and reference, shows the asset shopping list, and exports back out. It
runs in a browser and uploads nothing.

There are two more in the game itself: **`content_report.gd`** prints a
readable audit of every spreadsheet, and **`install_check.gd`** runs on the
title screen and names anything missing, misplaced or duplicated.

---

## 15. Things that will bite you

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

---

## 16. "I want to…" — the cookbook

| I want to | Open |
|---|---|
| add a new player | any unit CSV, or a new file with the same columns |
| add a whole new class | `ClassInfo.csv` + a unit CSV whose `Unit Type` matches |
| make a class unlockable | the `Requires` column of `ClassInfo.csv` |
| change how strong a tier is | `TierPowers.csv` — and read section 2 first |
| give a player an ability (league) | `Abilities.csv`, then the ability columns of the unit CSV |
| change what a passing move is worth (league) | `Combos.csv` |
| **change what a passing move is worth (Adventure)** | `AdventureCombos.csv` |
| add a new Adventure icon | `AdventureTraits.csv`, then breakpoints in `AdventureCombos.csv` |
| **add something to the bag** | a row of `Items.csv`. `Tab` says which of the three pages it lands on; leave it blank and `Kind` decides |
| **add a key item** | a row of `Items.csv` with `Kind: key` and no `Use`, then hand it out with a `Drops.csv` row or an `On Win` |
| **stop brews being poured mid-draft** | `draft_brew_button` in `Tuning.csv` |
| **keep another tier out of the passing move** | `pass_skips_tiers` in `Tuning.csv` — `III;IV` |
| **give the sides longer to get back into shape** | `goal_pause_seconds` and `save_pause_seconds` |
| **make an icon something the player earns** | put `unlocked:Whatever` in the `Requires` column of `AdventureTraits.csv`, and hand that unlock out with a talent or a season reward |
| **write a player who damages an enemy the moment you pick them** | a breakpoint in `AdventureCombos.csv` with `Effect = strike`, `Target = focus` and `Lasts = once`. The `star_2` row has the whole note written on it |
| change the kick-off, the clash or the speed buttons | the `kickoff_`, `coin_` and `game_speed_` rows of `Tuning.csv` — section 7 |
| **put a sound on an exact coin call** | a `coin_exact` row in `Juice.csv` |
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
