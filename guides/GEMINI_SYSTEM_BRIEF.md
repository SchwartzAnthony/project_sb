# Project SB — complete system brief

**Upload this one file to Gemini (or any assistant) before asking design
questions.** It describes the whole game as it actually exists, so the
answers you get are about your project rather than about football games in
general.

- **Engine:** Godot 4.7, GDScript.
- **Repo:** https://github.com/SchwartzAnthony/project_sb
- **Author:** A. J. Schwartz. Built with a non-programmer in mind.

---

## HOW TO BRIEF YOUR ASSISTANT

Paste this at the top of your first message:

> I am building a Godot 4.7 autobattler. The attached brief describes every
> system in it. Three rules for every answer you give me:
>
> 1. **New content is a spreadsheet row, never code.** If your answer needs
>    a new column or a new CSV, say so explicitly and give me the exact
>    header line. If it needs new GDScript, say that too and keep it in one
>    named file.
> 2. **Tell me which existing thing to reuse before inventing anything.**
>    This project deliberately reuses: counters for all resources, the
>    condition language for all gating, and the goalie for anything that
>    takes a shot.
> 3. **Give me step-by-step instructions I can follow without asking a
>    follow-up question** — which file, which column, what to type.
>
> Do not write new systems until you have told me what already covers it.

---

# 1. WHAT THE GAME IS

A football autobattler. You field a team of cards; the match plays itself in
rounds; at each round you choose which card takes the duel. Between matches
you build up a base, learn talents, drink brews and work through a season.

**A match, in order:**

1. **Kick-off** — you have a class, a Star Player and nine regulars.
2. **PLAY MAKER** — the round starts with rock/paper/scissors. The winner
   chooses to attack or defend.
3. **The draft** — you are offered your available cards for one tier and
   pick one. Weakest on the left, strongest on the right.
4. **The duel** — powers are compared, abilities fire, someone wins.
5. Winning carries the ball forward; reaching the goal is a **shot** against
   the opposing **goalie**, who has a stamina bar.
6. **HOLD UP** between cycles swaps your Star for another of your Stars.
7. **Full time** — the post-match screen lists what you gained.

---

# 2. THE ONE RULE EVERYTHING OBEYS: THE TIER LADDER

    Tier I     holds a 0, a 1 and a 2
    Tier II    holds a 1, a 2 and a 3
    Tier III   holds a 2, a 3 and a 4
    Tier IV    holds a 3, a 4 and a 5

Three cards per tier; their powers are always three different numbers in a
row. This holds **at all times** — in the collection, in the team builder,
on the pitch, for your side and the opposition. There is no exception.

- A **rung** is a power with a slot reserved for it.
- A card's rung is its **Base Power Left** (attack). Base Power Right
  (defence) should match.
- The numbers come from `data/TierPowers.csv` (Min Attack → Max Attack).
  That is the only place they exist.
- Enforced by `src/core/tier_ladder.gd`. Every screen asks it; none of them
  hold their own copy of the rule.

**The only thing that may change a power is an ability or element, during a
match, temporarily.** `AbilityEngine` holds bonuses *beside* the card and
throws them away at the end of the duel/round/cycle/match. `PlayerData` is
never written to, so a card walks into the next match on its proper rung.

**Anything that would make a side stronger permanently must be added
somewhere other than card power** — to the shot, to the goalie, to the
reward. Season Difficulty works this way: it adds to the opposition's shot,
not to their cards. This is the design constraint to hold any assistant to.

**A class's three Star Players hold one tier between them**, one on each
rung, and rotate through it at HOLD UP.

---

# 3. THE CONDITION LANGUAGE

Every gate in the game — a locked building, a talent, a story choice, a
sound cue, an opposing team — uses the same little language, in a column
usually called **Requires**. Terms are separated by semicolons; all must
pass. A blank column means "always".

| Requires | true when |
|---|---|
| `flag:brave` | the flag is set |
| `!flag:brave` | the flag is not set |
| `unlocked:Lorelei` | you have unlocked it |
| `!unlocked:Lorelei` | you have not |
| `count:gold>=10` | a number comparison — `>= > <= < = !=` |
| `is:next_class=Lorelei` | a stored word matches |

| Effects | does |
|---|---|
| `flag:brave` / `flag:brave=false` | set / clear a flag |
| `count:gold+10` `-5` `=0` | add / subtract / set a number |
| `unlock:Lorelei` | unlock anything, by name |
| `set:next_class=Lorelei` / `clear:next_class` | remember / forget a word |

**`count:` is the escape hatch and the most important idea in the project.**
Every resource, every currency, every achievement tally is a counter. A
shop price is `count:gold-25`. Wheat is `count:wheat+3`. Because they are
all counters, everything that can test a counter works on all of them the
day they exist — with no new code.

Names are matched case- and space-insensitively: `Spared The Keeper`,
`spared_the_keeper` and `sparedthekeeper` are the same flag.

Implemented in `src/core/dialogue_grammar.gd`.

---

# 4. WHAT THE GAME REMEMBERS

`GameState` (`src/core/game_state.gd`) — four kinds of memory, and
everything the game will ever need fits in one of them:

- **flags** — on/off facts
- **counters** — numbers (all resources live here)
- **texts** — remembered words
- **unlocks** — a list of earned names

Saved to `user://story_state.json`. It rides between scenes on the
SceneTree, so there is **no autoload to register** — the same trick is used
by `TeamSelection`, `MatchReport` and `MatchMode`.

---

# 5. EVERY CSV IN THE GAME

All live in `res://data/`. **Every `.csv` in that folder is read**, so a
spare copy of a file silently doubles its content.

Loaders identify a file **by its columns, not its name** — so you can call
your files anything and split them however you like.

| File | What it is | Key columns |
|---|---|---|
| `Units Set FO1 - *.csv` | **the cards** | Unit Type, Name, Attack, Defend, Element, Base Power Left, Base Power Right, Tier, Tool, Artwork, Player Type |
| `TierPowers.csv` | **the ladder** | Tier, Min Attack, Max Attack, Min Defense, Max Defense |
| `Abilities.csv` | what a card does | Ability ID, Name, Trigger, Target, Effect, Value, Scope |
| `Goalies.csv` | keepers | Team, Name, Max Stamina, Passive / Ability, Artwork |
| `Teams.csv` | who you play | ID, Name, Class, Cards, Power, Requires, Keeper, Description |
| `Season.csv` | the fixture list | ID, Match, Opponent, Team, Class, Difficulty, Final, Requires, On Win, On Loss |
| `MatchModes.csv` | the kinds of match | ID, Name, Records Season, Timer, Cycles, Rounds, Star Rotation, Opponent, Requires |
| `Stats.csv` | **what gets counted** | Counter, Event, When, Amount, Group, Label |
| `Progression.csv` | when things happen | ID, When, Requires, Do, Once |
| `Talents.csv` | the talent tree | ID, Name, Tree, Tier, Parent, Requires, Cost, Effects |
| `Brews.csv` | what the Pub pours | ID, Name, Requires, For Class, Becomes, Attack Ability, Defend Ability, Permanent |
| `Buildings.csv` | the base | ID, Name, Description, Requires, Art, X, Y, Action |
| `Visitors.csv` | people at the base | ID, Name, Portrait, Requires, Story, X, Y, Once |
| `Dialogue.csv` | the story | Scene, Node ID, Speaker, Text, Next, Requires, Effects, Choice 1–3 (Text/Next/Requires/Effects) |
| `Audio.csv` | every sound | ID, When, Match, Sound, Bus, Loop, Volume, Fade, Requires |
| `Animations.csv` | spritesheet slicing | Animation, Unit Type, Sheet Columns, Sheet Rows, Row, First Frame, Frames, FPS, Loop |
| `MenuConfig.csv` | the main menu | Button ID, Label, X, Y, Width, Height, Action, Art Path |
| `ClassInfo.csv` | class blurbs | Class, Display Name, Description, Banner Art, Formation Art |
| `Tuning.csv` | ~130 numbers | Key, Value, What it does |

## Stats.csv — the most useful file to understand

It teaches the game what to count, with no code:

```
Counter,Event,When,Amount,Group,Label,Notes
goal_points,goal_scored,,1,Match,Goal points,
wheat,duel_won,tier=I,2,Quick Match,Wheat,Two wheat per Tier I duel won.
```

**Events the match reports:** `goal_scored`, `goal_conceded`, `shot_taken`,
`save_made`, `duel_won`, `duel_lost`, `brew_drunk`, `match_ended`. Plus, for
`Audio.csv` only: `screen_opened`, `match_started`, `play_maker`, `hold_up`,
`card_hovered`, `card_picked`.

**`When` filters the event** on the facts it carries: `tier=I`, `star=yes`,
`class=Lorelei`, `result=win`, `power>=4`, `screen=base`. Blank = always.

**`Group` sorts the post-match screen into panels.** New counter, new row,
nothing else.

---

# 6. THE SCRIPTS

`src/core/` — the data and the rules

| File | Class | Does |
|---|---|---|
| `card_database.gd` | CardDatabase | reads every CSV; owns the cards |
| `tier_ladder.gd` | TierLadder | **the ladder rule**, shared by all screens |
| `player_data.gd` | PlayerData | one card |
| `ability_engine.gd` | AbilityEngine | buffs, held beside cards, expired by scope |
| `ability_data.gd` | AbilityData | one row of Abilities.csv |
| `game_state.gd` | GameState | flags, counters, texts, unlocks; the save |
| `dialogue_grammar.gd` | DialogueGrammar | the Requires/Effects language |
| `dialogue_db.gd` | DialogueDB | the story |
| `stats_rules.gd` | StatsRules | Stats.csv |
| `progression.gd` | Progression | Progression.csv |
| `season_db.gd` | SeasonDB | fixtures, the table, the end of a season |
| `team_db.gd` | TeamDB | opposing teams; power matching |
| `match_mode.gd` | MatchMode | **season vs quick match** |
| `talent_db.gd` `brew_db.gd` `base_db.gd` | | talents, brews, buildings |
| `audio_db.gd` `audio_director.gd` | | sound from CSV |
| `match_report.gd` | MatchReport | photographs the save before and after |
| `content_report.gd` | ContentReport | **the startup report** |
| `scene_paths.gd` | ScenePaths | where screens live, and the **back trail** |
| `game_speed.gd` `goalie_data.gd` `csv_importer.gd` | | |

`src/ui/` — the screens

`main_menu` `class_select` `team_builder` `base_screen` `season_screen`
`match_stats_screen` `talent_screen` `pub_screen` `unlock_board`
`save_inspector` `dialogue_view` `pause_menu` `match_hud` `rps_clash`
`card_popup` `card_stats_panel` `player_card_ui` `shootout_view`
`duel_arena` `menu_support` `star_badge` `progress_row` `new_unlocks_panel`
`unlock_progress` `zone_overlay`

`src/units/` — `player_unit` `goalie_unit` `ball` `sprite_animator`
`src/formations/` — `main_scene.gd` (the match itself, ~3100 lines)

---

# 7. CONVENTIONS THAT MATTER

Hold any assistant to these — they are why the project stays editable.

1. **The CSV is the game. Code reads it; it never hard-codes content.**
2. **Loaders identify files by columns, not names.** Any CSV with both a
   `Cards` and a `Power` column is a teams file, wherever it lives.
3. **New content = a row. New *kind* of content = a column. New *behaviour*
   = one named file.** In that order of preference.
4. **Nothing ever stops the game.** A bad row is named in the Output panel
   and skipped. `ContentReport` gathers every complaint at startup, and
   also finds cross-file problems — a counter that is read but never
   written, a story scene that does not exist.
5. **Cross-scene state rides on the SceneTree**, never an autoload.
6. **Placeholder art is drawn in code** (`_draw()`) so a missing PNG shows a
   labelled shape rather than nothing. Supply the art and it disappears.
7. **Screens built in code** except `season_screen.tscn`, which is the
   template for `.tscn`-designed screens: the scene decides the layout, the
   script only fills named nodes.
8. **Back uses a trail**, not hard-coded destinations —
   `ScenePaths.go_to()` remembers, `go_back()` returns.
9. **Tabs for indentation.** Godot rejects a file that mixes them.
10. **Never name a helper `_set`, `_get`, `_draw`, `_init`, `_notification`
    or `_to_string`** — they collide with Godot's own and the script will
    not compile.

---

# 8. THE TWO MATCH TYPES

**Season Match** — against another human side who drink brews to become
stronger. 90 minutes, three cycles, three Stars rotating. The result goes in
the table. A completed season grants a **big unlock** — *Season of Fire*
opens a building.

**Quick Match** — a single run for **resources**. No clock, one Star,
nothing written to the table. This is how you afford the buildings that
would otherwise produce your materials.

Both are the same match code; the difference is a row in `MatchModes.csv`.

**The intended enemy mode (designed, not yet built):** enemies come out of
**nests** that must be cracked open. Players pass the ball as normal; a won
power check means a **shot at an enemy**, and *the enemy is a goalie* with a
stamina bar. Dead enemies drop recipes, items and resources. Planned CSVs:
`Enemies.csv`, `Nests.csv`, `Drops.csv`. Full design in
**ENEMIES_AND_QUICK_MATCH.md**.

The currency split is deliberate and worth protecting:
**quick matches pay in materials; seasons pay in unlocks.**

---

# 9. STATE OF PLAY

**Built and working:** the match loop, the tier ladder, the draft, duels and
abilities, goalies and shootouts, the RPS clash, AUTO play, pause, the
season and its table, opposing teams with power matching, the talent tree,
brews, the base with buildings and visitors, the story system, stats and
progression, unlock tracking, audio from CSV, the startup report, the
back-trail, match modes, Quick Match.

**Designed, not built:** the enemy/nest mode, resources and recipes as their
own CSVs (`Items.csv`, `Recipes.csv`) and a stash screen, seasons as a
biome tree (`Seasons.csv`, `SeasonTiers.csv`), the tutorial
(`Tutorial.csv`), the halftime locker room.

**Not started:** settings, keybinds and controller support (every input is
currently a hard-coded key and must become a named action in Godot's Input
Map first), Steam Deck packaging, player-side roster upgrades, the shot
cut-away and passing animation polish.

---

# 10. GOOD QUESTIONS TO ASK YOUR ASSISTANT

These are shaped to get useful answers out of this system:

- "I want *X*. Which existing CSV covers it, and what rows would I write?"
- "Here is my `Stats.csv`. What is missing for a resource economy?"
- "Design `Items.csv` and `Recipes.csv` to fit the conventions in section 7."
- "Write ten `Enemies.csv` rows for a marsh biome using the columns in
  ENEMIES_AND_QUICK_MATCH.md."
- "My Tier II has no 1-power card. What are my options?"
- "I want the opposition to feel harder without breaking the tier ladder.
  Where can the difficulty go?"

And the one to ask before any big feature:

> "Before you design this, tell me what in the existing system already does
> part of it."
