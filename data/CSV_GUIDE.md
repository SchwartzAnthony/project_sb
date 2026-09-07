# Adding things to the game without touching code

Everything the game knows lives in `res://data/*.csv`. There is **no import
step** — drop a file in, press Play, it's in the match. You can delete
`data/players/`, `data/goalies/` and `src/core/csv_importer.gd`; nothing reads
them any more.

---

## Two rules that make this safe

**1. File names don't matter.** The game looks at each CSV's *header row* to
work out what it is:

| If the header contains… | The file is treated as |
|---|---|
| `Unit Type` **and** `Base Power Left` | unit cards |
| `Max Stamina` | goalies |
| `Ability ID` | abilities |
| `Key` **and** `Value` | tuning |

Anything else is ignored. So `Units Set FO2 - Nachtkrapp.csv` just works.

**2. Column order doesn't matter, and extra columns are fine.** Columns are
matched by *name*, ignoring capitals, spaces and underscores — `Base Power
Left`, `base_power_left` and `BASEPOWERLEFT` are the same column. Add your own
columns (`Designer Notes`, `Print Status`, whatever) and the game skips them.

Both of these are tested: a unit CSV with its columns randomly shuffled and a
junk column added loaded all 24 cards correctly.

---

## Adding a new class / race

1. Export a CSV into `res://data/` with the same headers as your existing unit
   files. Name it whatever you like.
2. Put the card art PNGs in `res://assets/players/`, named exactly as the
   `Artwork` column says.
3. Add a row to `Goalies.csv` for its keeper. `Team` must match `Unit Type`
   exactly.
4. *Optional:* add `res://src/formations/<class>_formation.tscn`. Without one,
   a formation is generated from the pitch automatically.

That's it. No code, no editor script.

> **Roster rule:** all three of a class's Star Players must share one Tier, and
> the three non-Star tiers need 3 cards each (9 regulars). If they don't, the
> game says so by name on startup.

---

## Adding an ability

Abilities live in `Abilities.csv`. An ability is five answers:

| Column | Question | Allowed values |
|---|---|---|
| `Trigger` | When does it go off? | `on_attack`, `on_defend`, `on_duel_start`, `on_win_duel`, `on_lose_duel`, `passive` |
| `Target` | Who does it hit? | `self`, `opponent`, `all_allies`, `all_enemies`, `enemy_goalie`, `own_goalie`, `tag:<tag>`, `tier:<I-IV>`, `enemy_tier:<I-IV>` |
| `Effect` | What does it do? | `add_attack`, `add_defense`, `add_power`, `add_shot_power`, `drain_stamina`, `restore_stamina` |
| `Value` | How much? | any whole number — **negative values are debuffs** |
| `Scope` | How long? | `duel`, `round`, `cycle`, `match` |

`tag:` matches anything from a card's tag set: its element, its class, its
tier, and `star` or `normal`. So `tag:brandteufel`, `tag:fire`, `tag:star` all
work.

Then point a card at it: add an **`Attack Ability`** and/or **`Defend
Ability`** column to your unit CSV and put the `Ability ID` in it. Leave it
blank for cards with no mechanical ability — their `Attack`/`Defend` prose
stays as the printed card text either way.

**Worked example** — "when this wins its duel, every Brandteufel gets +1 power
for the rest of the round":

```
Ability ID,Name,Trigger,Target,Effect,Value,Scope,Notes
BRAND_RALLY,Furnace Rally,on_win_duel,tag:brandteufel,add_power,1,round,
```

then in the unit CSV, on Coalblaze's row, `Attack Ability` = `BRAND_RALLY`.

### The one limit worth knowing

The six `Effect` words above are the whole vocabulary. New **cards** using
those words need no code. Inventing a genuinely new *kind* of effect — say
"transform a unit into another class", or "draw an extra pick" — needs one
code change, in exactly one place: `_apply_one()` in
`src/core/ability_engine.gd`. Add the word to `AbilityData.EFFECTS`, then say
what it does. Tell me the effect you want and I'll add it.

---

## Changing balance

`Tuning.csv` holds every number that used to be buried in code — match length,
goalie save chances, ball speed, pass and tackle radii, how fast units run.
Each row is `Key,Value,What it does`.

A missing, deleted or misspelled row falls back to the built-in default, so you
cannot break the game by editing this file. Deleting `Tuning.csv` entirely was
tested: the match ran normally on defaults.

---

## When you get something wrong

On startup the game prints one tidy report and then plays on. It never crashes
on bad data. From the real test:

```
[CardDB] 24 cards, 2 goalies, 8 abilities, 0 tuning values.
[CardDB] 6 thing(s) need attention in your CSVs:
   - Abilities.csv: ability 'BAD_EFFECT' — Effect 'makecoffee' is not one of:
     add_attack, add_defense, add_power, add_shot_power, drain_stamina, restore_stamina
   - Abilities.csv: ability 'BAD_ZERO' — Value is 0, so this ability would do nothing
   - Abilities.csv: ability 'BAD_TRIG' — Trigger 'whenever' is not one of: ...
   - Abilities.csv: ability 'BAD_TARGET' — Target 'the_vibes' is not recognised
   - Goalies.csv: goalie 'Undine Aegis' has Max Stamina 0 — using 25
   - Units Set FO1 - Lorelei.csv: 'Echo of the Cliff Lorelei' has tier 'Tier Five'
     — expected I, II, III or IV
```

A broken ability row is skipped, a broken number falls back to a sane default,
and a broken card still loads. That whole match still finished 2–1.

**Read this report in the Output panel every time you change a CSV.** It is the
one place that tells you if a row didn't take.

---

## Quick reference: which file for what

| I want to… | Edit |
|---|---|
| add cards, or a whole new class | a unit CSV in `res://data/` |
| change a keeper's stamina or name | `Goalies.csv` |
| create or change an ability | `Abilities.csv` |
| point a card at an ability | `Attack Ability` / `Defend Ability` columns in the unit CSV |
| change match length, speeds, save odds | `Tuning.csv` |
| add a genuinely new *kind* of effect | `src/core/ability_engine.gd` — ask me |
