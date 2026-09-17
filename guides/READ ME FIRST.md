# Read me first

## 1. Before you copy anything: delete 12 files

They are still in your repo. I checked the clone just now. Every one of them
is a **second copy** of a script that already exists somewhere else, and Godot
registers a `class_name` exactly once — so a second copy gives you

    Class "GoalieUnit" hides a global script class

and then Godot loads whichever it feels like, which may be the empty one.

In Godot's FileSystem dock you can Ctrl-click all of these and press Delete
once. Delete the `.uid` file beside each `.gd` too if you see one.

```
src/core/adventure_db.gd
src/core/adventure_run.gd
src/core/enemy_pick_layer.gd
src/ui/base_db.gd
src/ui/dialogue_choice.gd
src/ui/dialogue_line.gd
src/ui/goalie_unit.gd
src/ui/goalie_unit.tscn
src/ui/zone_overlay.gd
src/units/sprite_animator.gd
export_sheet_preview.gd          (the one in the project ROOT, not src/core/)
test_run.gd                      (the one in the project ROOT, not src/core/)
```

**How to tell you have the right one if you are unsure:** open it. The copy to
delete is 35 lines long and has no `class_name` at the top — it is the blank
stub I shipped so that this would be a delete rather than a hunt. The one to
keep is the long file.

## 2. And 148 leftover `.translation` files

`data/` still has 148 `.translation` files — `Tuning.en.translation` and so on.
Godot made them back when it was importing your spreadsheets as translation
tables. That is fixed (every CSV now has a `.csv.import` saying
`importer="keep"`), so these are dead weight. Select them all in `data/` and
delete them. Nothing reads them.

## 3. Then copy the folders

The zip has `src/` and `data/` laid out exactly as your project is. Drop them
over the top of your project folder and everything lands where it belongs.

Only files that actually changed are in here — 21 of them.

---

# What is new

## Juice — `data/Juice.csv`

The thing you asked for, and it is a spreadsheet.

**Nothing about how the game FEELS is typed into a script any more.** The code
says what happened — `enemy_hit`, `ball_received`, `enemy_died` — and Juice.csv
decides what that looks and sounds like. Thirteen moments, sixteen rows out of
the box, and you can add, delete or retune any of them without opening a `.gd`
file.

| Column | What it does |
|---|---|
| `When` | the moment. Thirteen of them, listed at the top of `juice_db.gd` |
| `Who` | player / enemy / screen / ball — **what** gets shaken |
| `Shake` | how far it jumps, in pixels |
| `Shake Scale` | **how much harder a big hit shakes.** See below |
| `Flash` / `Flash Colour` | seconds of a colour wash, and the colour |
| `Pop` / `Squash` | scale it snaps to and back from, and how much it squashes |
| `Sound` | a row of Audio.csv, or just a file name in `assets/audio/` |
| `Slowmo` | seconds the whole game runs slow. Use sparingly |

Two rows may share a `When` and both fire — that is how `enemy_hit` shakes the
enemy *and* the screen from one event, with different settings for each.

**`ball_received` is the row you described.** A player takes the ball and gets
a two-pixel knock and a little pop. Open the row and change the 2 to a 6 to see
what I mean about it being a spreadsheet now.

### Shake Scale, which is the interesting column

You asked for the shake to grow with the damage. `Shake` is the shake for an
*average* hit; `Shake Scale` decides how much the size of the hit is allowed to
move that number.

* `0` — every hit shakes the same. Flat, predictable.
* `0.9` — what `enemy_hit` ships with. A big hit shakes noticeably harder.
* `1.4` — what `enemy_hit_big` ships with. Small hits barely register; big ones
  are an event.

**And it works out "average" by itself.** It keeps a running average of the
hits you actually land, in this fight, so a big hit means big *for this fight* —
true whether your side hits for 4 or for 40. There is no number to keep
re-tuning as the game grows. If you would rather pin it, `juice_average_hit` in
Tuning.csv.

### Turning it down

* `juice_scale` — 0 kills every effect, 0.5 halves them, 2 doubles them. This
  is the row to put in the Settings screen for people who dislike screen shake,
  and the row to set to 0 while you are debugging something.
* `juice_slowmo` — `false` stops the slow-motion dips only.

### Sound

The `Sound` column names a row of **Audio.csv** — so a juice sound is an
ordinary game sound, obeys the Sound tab of Settings, and has volume, bus and
fade already. I have added the twelve new rows it needs, and the twelve files
to **SOUNDS_WANTED.csv** with a line each on what they should sound like.

A name Audio.csv has never heard of is looked for as a **file in
`assets/audio/`** instead, so you can drop `whump.wav` in, type `whump` in the
Sound column, and hear it without writing a row first.

---

## Adventure

**The card window can no longer be cut off.** It is anchored to the screen with
a margin top and bottom (`adventure_choice_top`, `adventure_choice_bottom` in
Tuning.csv), the cards wrap onto a second line rather than running off the
edge, and it scrolls if you ever field more than fit.

**Hovering a card reads out its abilities**, exactly as a league match does —
name, tier, power, stamina, element, and both its attack and defend abilities
out of Abilities.csv, in the tooltip and in the command bar.

**Players rotate.** Once a player has been used they are "done" until everybody
else in that tier has had their turn, then the whole tier refreshes. Used
players stay on screen greyed out and labelled *resting*, so you can see the
rotation rather than having to remember it. A player **knocked out** is retired
for good — which is what makes losing somebody cost you a tier slot in the next
fight, the way you asked.

**A player with no stamina lies on the ground.** They turn on their side where
they fell, the drift stops, and they stay there. When the last enemy goes down,
**two players who are not on your team** jog in from behind the party, pick up
everybody on the ground, and carry them back off the way they came — then the
party runs on. They are drawn from your unit CSV, so they get real artwork and
they will not be the same two every time. `adventure_stretcher` in Tuning.csv
turns it off; `adventure_stretcher_seconds` sets how long it takes.

**The enemies now get a build-up window of their own**, the mirror of yours.
They come on one at a time, each adding what it hits for to a running total,
their abilities named out of Abilities.csv — and **their combos fire out of the
same Combos.csv yours do.** An enemy's Pool stands in for its class, and a Boss
counts as the Star. Your side of the window shows how many are standing in each
tier, because an empty tier is what doubles everything they do.

Their bonus goes to **one hit — the last of them to strike** — for the same
reason yours goes to the shot and never to a card. One move, one bonus, both
sides.

> **What this does to the balance.** I ran 20,000 waves against your current
> AdventureEnemies.csv: a combo fires on about **half** of them and it adds
> about **12% more enemy damage overall**. That is a real bump but not a
> different game. The one thing worth knowing is that `Chained` (three sharing
> an element) is doing most of the work, because a pool tends to be all one
> element — marsh is all Water. **Mixing elements within a pool is what would
> make their combos interesting rather than automatic.** `adventure_enemy_combos`
> in Tuning.csv turns the whole thing off if you would rather combos belonged
> to your side alone.

**And their turn now ends out loud.** `THEIR TURN IS OVER` comes up across the
middle of the screen when the last enemy has finished hitting you. There is no
longer a moment where you are waiting on the game and the game is waiting on
you. `adventure_turn_over_seconds` sets how long it holds.

---

## The small ones

* **"HOLD UP" is now "STAR PLAYER SWITCH"** — on screen, in the log, and in
  every spreadsheet that described it. The *audio event* is still called
  `hold_up` on purpose: that is the key your Audio.csv row is written against,
  and renaming it would silence your whistle.
* **The Seasons shelf is centred.** Every row is centred on the screen, and the
  `Column` column now decides the order and spacing *within* a row rather than
  the absolute position — so three or four side by side spread evenly across
  the middle, and one on its own sits in the centre. Gaps in your Column
  numbers still mean something: a row using columns 0 and 2 keeps the hole, so
  a branch still looks like a branch. You do not have to renumber anything.
  It re-centres when you resize the window.
* **The League page's Play button is bottom right**, in the corner opposite
  Back.

---

## New Tuning.csv rows

```
adventure_choice_top          90      margin above the card window
adventure_choice_bottom      130      margin below it — the cut-off fix
adventure_enemy_buildup     true      their build-up window
adventure_enemy_combos      true      whether their combos fire at all
adventure_turn_over_seconds  0.7      how long THEIR TURN IS OVER holds
adventure_stretcher         true      carrying the fallen off
adventure_stretcher_seconds  2.4      how long that takes
juice_scale                  1.0      all shake/flash/pop, 0 = none
juice_slowmo                true      the slow-motion dips only
juice_average_hit              0      0 = work it out from play
```
