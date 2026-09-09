# Adventure, Phase 3 — the encounter, and the look of the run

Two halves. The look and motion you asked for from the screenshot, and then
the fight itself.

---

## STEP 1 — Where the files go

| File | Folder | |
|---|---|---|
| `adventure_encounter.gd` | `src/adventure/` | **NEW** |
| `adventure_scene.gd` `adventure_walker.gd` | `src/adventure/` | replace |
| `adventure_db.gd` | `src/core/` | replace |
| `Biomes.csv` `AdventureEnemies.csv` `Items.csv` `Drops.csv` `Tuning.csv` | `data/` | replace |

**`AdventureEnemies.csv` and `Items.csv` have changed shape — replace them
rather than merging by hand.** What changed is in Step 4.

---

# PART 1 — THE LOOK

## The party was standing on the black. Fixed.

Your screenshot showed them above the grass in rigid rows. Three things
were wrong and all three are fixed:

**1. There is a lane now, and it is absolute.** `LANE_TOP` and
`LANE_HEIGHT` in `adventure_scene.gd` define the grass band, and *every*
walker clamps into it at the end of every frame — drift, errand, formation,
it does not matter. Nobody can leave the pitch.

**2. Nobody marches in rows.** Each player got three pieces of its own
randomness:

- **its own pace** (0.82× to 1.22× the party's), so they slide past each other
- **its own drift** — a slow figure-of-eight around its slot, at its own rate
- **a staggered slot** — four across, odd columns half a lane lower

The result is a loose group crossing over itself as it runs, which is what
a team jogging up a pitch actually looks like.

**3. Pickups appear anywhere in the lane, high or low.** They used to spawn
at one height, so the same front players always got them. Now an item near
the top edge is reached by whoever happens to be drifting up there.

## A biome is now four colours and a picture

`Biomes.csv` gained six columns. **No code changes for a new biome.**

| Column | |
|---|---|
| **Background** | an image file name. Tiles and scrolls behind everything |
| **Parallax** | how fast it slides. `0` = still, `1` = same speed as the ground. `0.3` reads well |
| **Sky** | the colour behind it — and what you see when there is no image yet |
| **Grass** | the lane |
| **Grass Stripe** | the mown stripes on it |
| **Edge** | the line along the top and bottom of the lane |

Colours are written the way a designer writes them: `#213a26`. Leave one
blank and it falls back to the marsh green, so a half-filled row still
draws. A bad colour says so once in the Output panel and keeps going.

**I added a fourth biome, The Frostreach, purely as a worked example of an
ice palette** — `#101822` sky, `#28455e` grass, `#20384d` stripes,
`#4d7a9e` edges. Copy that row, change four colours, and you have a desert.

For the image: put it in `assets/backgrounds/` (or any folder in
`MenuSupport.ICON_DIRS`) and name it in the **Background** column without
the extension. Until the file exists you get the Sky colour and one line in
the Output panel telling you which file it is looking for.

## The pace varies now

You said the speed felt right and just wanted variety. Three `Tuning.csv`
rows, and the change is eased rather than snapped so it is felt rather than
noticed:

```
adventure_fetch_pace,1.18        a yard faster while somebody is chasing a pickup
adventure_approach_pace,0.55     eased down to this on the run-in to a fight
adventure_slow_distance,260      how far out the easing starts
```

---

# PART 2 — THE ENCOUNTER

## Enemies have no tiers any more

You were right, and it made the whole thing simpler. **An enemy is two
numbers: Attack, and Layers.**

`AdventureEnemies.csv` lost `Tier` and `Power`, and `Damage` is now
**`Attack`** (the old name is still read, so nothing breaks).

```
ID,Name,Pool,Attack,Layers,Targeting,Element,Ability,Art,Drops,Weight,Boss,Description
bog_lurker,Bog Lurker,marsh,2,Hide:3:1|Body:6,weakest,Water,,lurker,lurker_drops,6,no,"..."
```

A wave is simply *N* enemies drawn from the biome's pool, weighted by the
**Weight** column — a 10 turns up five times as often as a 2. Change how
many with `adventure_enemies_per_wave` (3 today). Variety, amounts, stamina
and attack are all yours to tune from here.

## A round, in order

1. **FOCUS** — pick one enemy. **Hover any of them** to read what it hits
   for, who it goes for, and every layer with how much is left of it.
2. **ITEMS** — optional, before the drafting starts.
3. **DRAFT** — Tier I, then II, III, IV. One card each from whoever is
   still standing in that tier.
4. **FLEE** — live until you commit the **fourth** tier.
5. **Your hit** — the four powers are added up and go into the focused
   enemy's outermost layer, minus that layer's soak.
6. **Their hit** — *then* every living enemy strikes back, one at a time.

## The two rules that keep it fair

**A tier with nobody left is a walkover — and only a completely empty one.**
Not a thin tier, not one down to a single player: every player in it knocked
out. That tier adds nothing to your hit, and the enemies' damage is
**doubled** for the round (`adventure_walkover_multiplier`).

**Enemies spread their damage.** The default `weakest` targeting hits the
weakest player in whichever tier currently has the **most** still standing,
lowest tier first on a tie — exactly as you described. That keeps your four
tiers level and stops any one being quietly wiped, which is what would
trigger the walkover above.

`Targeting` breaks that rule on purpose:

| | |
|---|---|
| `weakest` | the default, above |
| `strongest` | goes for your best player |
| `lowest_stamina` | finishes what is already hurt |
| `aoe` | the weakest of **each tier** — four targets |

## Items, and the ITEMS button

`Items.csv` gained **Use** and **Target**. An item with a blank Use is just
material and never appears in the menu.

| Use | |
|---|---|
| `revive` | one knocked-out player comes back, at half stamina |
| `heal:6` | six stamina to one player still standing |
| `heal:3;all` | three to everyone still standing |
| `hit:4` | four damage into the enemy you are focusing |

Four are shipped: **Smelling Salts** (revive), **Field Bandage**,
**Half-Time Orange** and a **Throwing Stone**. They drop from bosses and
occasionally off the ground, so your first run finds one or two.

Because items are counters, using one is spending a counter — nothing new
had to be built, and an item you invent tomorrow works the same day.

---

## STEP 4 — What the balance actually does

I simulated 200 full runs of each bounty, stamina carrying between waves
with no healing (the sim does not use items, so the real thing is kinder):

| Bounty | Cleared | Stamina left |
|---|---|---|
| Clear the Reeds | 200/200 | 92% |
| The Marsh King | 200/200 | 76% |
| The Slag Run | 200/200 | 77% |
| The Ash Tyrant | 200/200 | 23% |
| **The Hollow Mother** | **126/200** | 6% |

That is the ramp I would want: the first job is a walk, the middle ones
cost you something, and the last boss in the game beats you **about a third
of the time**. Items are the difference between those runs, which is
exactly what the ITEMS button is for.

**One rule I changed on the evidence.** `aoe` originally hit every standing
player — up to twelve. That made one enemy three times stronger than any
other and decided fights on its own (the Ash Tyrant left you on 1%
stamina). It is the weakest of **each tier** now: four targets, a proper
sweep, still the scariest thing in a wave. 1% became 23%.

The party's total stamina is **162** with the default 6 + 3×power. Every
number above moves with `adventure_stamina_base` and
`adventure_stamina_per_power`.

---

## STEP 5 — One thing I want to check

Your point 4 said the walkover was "correct", but with enemies no longer
having tiers, *they* can never field an empty one — so the rule can only
ever run against you now.

**I have built it as: your empty tier contributes nothing, and doubles what
the enemies do that round.** That makes losing a whole tier genuinely
frightening, which I think is what you meant. If you wanted something
gentler — the tier just contributing nothing, with no doubling — it is one
number: set `adventure_walkover_multiplier` to `1`.

---

## NEXT — Phase 4 and 5

Phase 3 turned stamina on, so most of Phase 4 is already done: knockouts
work, the walkers show their bars and go grey with a cross when they are
out, and the party going down ends the run with nothing.

**What is left:**

- **Phase 4** — the ball-kick animation on your hit (the last player in the
  tier draft kicking at the focused enemy), and enemies visibly striking.
  Right now damage is a line in the log rather than a thing you watch.
- **Phase 5** — items usable from the Bounty Board before you set off, and
  stamina carried into the next wave shown on the loot popup.
- **Phase 6** — biome unlock chains and the scaling loop after a boss.

Play a run first. The fight is the part I most want you to feel before I
put animation on top of it.
