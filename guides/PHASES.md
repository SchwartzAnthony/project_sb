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

## Phase 1 — Sound, and the way in and out  ✅ IN THIS ZIP

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

## Phase 2 — Reading the match

You cannot tell whether the football is good if you cannot follow it. All of
this is about the same thing: making the state of play obvious.

| | |
|---|---|
| | **ATTACKING or DEFENDING, big.** On the clash result, and then held on screen through every tier pick, so there is never a moment where you are choosing a card without knowing which way round you are |
| | **The line-ups walk out.** After the loading screen: your eleven one at a time, then theirs. Click, space or escape skips it |
| | **The goal celebration.** The scorer slides, the team surrounds them, a window opens for an animation, confetti, the crowd. You dictate what is in it and for how long, in a CSV |
| | **A Star's abilities once, not twice.** Remove the hover — it duplicated what is already printed — and make attack and defend read differently at a glance instead of being two identical grey lines |

**Why second:** it is all presentation of things that already work, so it is
low risk, and it is what makes the next phases judgeable.

---

## Phase 3 — The skin

> *"Right now people can tell it is an AI game. I need to be able to
> customise the windows."*

This is the phase that changes how the game looks, and it is one system
rather than four: everything drawn by the interface goes through
`MenuSupport`, so a **`Theme.csv`** in front of that reaches all of it at
once.

| | |
|---|---|
| | Panels, buttons and windows drawn from **images** rather than flat colours — 9-slice, so one image stretches to any window without distorting its corners |
| | Borders, corners and dividers as images |
| | Fonts: the file, the sizes, per element |
| | Colours: the palette in one place instead of constants in the code |
| | A state per element — normal, hover, pressed, disabled, focused |
| | Every number that is a size or a margin |

**Why third:** it is the largest *visual* change and it touches every screen,
so it wants the screens to have stopped moving first — which is what Phase 2
finishes doing. Doing it before would mean skinning things I am about to
rebuild.

---

## Phase 4 — Out of bounds, and the new PLAY MAKER

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

The one I would personally pull forward is the **goal celebration** out of
Phase 2, because it is the moment the game is *for* and it currently passes
in silence.
