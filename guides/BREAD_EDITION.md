# The Bread Edition (Brotzeit): a plan

Anthony, 9 Oct 2026: some players cannot or will not play a game built on
alcohol. They should get a **bread version** of Sturmball, and one purchase
should give both.

This is a plan only. Nothing in the game has changed yet.

---

## 1. The short answer

**One game, two skins.** Keep one codebase and one set of rules. The bread
version is the same game with different names, words, pictures and sounds,
switched on at start-up. Brewing becomes baking, the Pub becomes a Brotzeit
room, the drunk meter becomes a "full belly" meter. Every number stays the
same, so there is one balance to look after, not two.

How it reaches players is a separate, later choice (section 5). The switch
inside the game works for every store option, so we can build it first and
decide the store later.

---

## 2. How much beer is in the game today

Measured on `round-AN`, 9 Oct.

| Where | How much | Notes |
|---|---|---|
| **Spreadsheets** | 59 of 127 CSVs mention beer, brewing, drunk, pub, keg or bottle | Heaviest: Dialogue (62 rows), Tuning (38), Items (22), Brews (16), Audio (15), Abilities (14), StoryArt (14), Theme (14), Upgrades (12), Achievements (10) |
| **Words inside the code** | about 98 player-facing strings in 18 `.gd` files | Mostly `pub_screen.gd` ("DRUNK METER", "too sober", "+30% drunk"), plus shop, inventory, card panel, class tree, team build, match coach |
| **Art** | 64+ files named for beer, plus pictures that show it without saying so | Brewery yard, six machines and their mini-game folders, Pub building, bottles and kegs, Koch and the Head Coach drunk portraits, the beer-hall title wallpaper |
| **Look of every screen** | `Theme.csv` | The whole UI is a beer hall: beer-mat slots, "beer gold" accent, bars drawn as a glass filling with beer |
| **Sound** | 15 Audio rows | Pouring, the Pub and Brewery doors, the base theme once the Brewery opens, cheers |

### The systems, one by one

| System | Files | What it does now |
|---|---|---|
| Brewery | `BrewerySections`, `BreweryResources`, `BreweryGames`, `Brewers`, `BottleSizes` | Six machines from wheat to bottle, each with a mini-game |
| Brews | `Brews.csv`, `Items.csv` | Fire / Water Brew, Keeper's Tonic, Team Spirits, turning beers, plain beer, combo beers (Helles, Weiße, Dunkel), Kleiner Faß |
| Drunk meter | `DrunkLevels.csv`, `drunk_book.gd` | Sober 0, Tipsy 30 (brews take hold), Inspired 70 (Star) |
| Pub | `Buildings.csv`, `pub_screen.gd`, `pub_book.gd` | Pour drinks on players before a match |
| Time-outs | `Abilities.csv` (`TUT_KOCH_BEER`, `TUT_KOCH_EARTH`, `PLAIN_*`, `COMBO_*`) | Koch's Beer Courage, Earth Courage, the plain-beer gambles |
| Story | `Dialogue.csv`, `TutorialMorningDialogue.csv`, `MatchTalk.csv`, `StoryArt.csv` | Koch's prologue, Hanna the brewer, the Traveling Tavern |
| Progress | `Achievements.csv`, `Stats.csv`, `Upgrades.csv`, `Shop.csv` | "The First Brew", "Master Brewer", the machine keys, recipes for sale |

---

## 3. The good news: baking fits the brewery almost one to one

The brewing chain and the baking chain use the same ingredients in the same
order, so every machine, mini-game and number can stay. Only the names and
pictures change. **All names below are drafts for Anthony to replace.**

| Beer edition | Bread edition (draft) | Mini-game stays as |
|---|---|---|
| Brewery | Bakery (Backstube) | |
| Steeping Tank | Dough Trough | stir: knead the dough |
| Grain Mill | Grain Mill | rhythm: unchanged |
| Lauter Tun | Flour Sifter | colour: sift while it runs fine |
| Brew Kettle | Wood Oven | fire: keep the oven in the gold |
| Fermenting Vat | Proving Shelf | hold: let it rise, stop in the gold |
| Bottling Machine | Bread Basket line | conveyor: one loaf per basket |
| wort, malt, mash, germs, hops | sponge, dough, sourdough, yeast, caraway | |
| Small bottle / large bottle / keg | Semmel / Brezn / Laib (whole loaf) | |
| Plain Beer | Plain Roll | |
| Anstoß Helles / Doppelpass Weiße / Abstauber Dunkel | Anstoß Brezn / Doppelpass Weißbrot / Abstauber Schwarzbrot | |
| Fire Brew / Water Brew | Fire Loaf (Flammkuchen) / River Bread | |
| Turning beers (Smoke Beer, Miner's Dunkel, Unken Weisse) | Smoked Rye, Miner's Pumpernickel, Unken Bun | |
| Pub | Brotzeit Stube | |
| Drunk meter: Sober / Tipsy / Inspired | Belly meter: Peckish / Fed / Fired Up | same 0 / 30 / 70 |
| Beer Courage (Koch) | Brezn Courage | |
| Traveling Tavern | Traveling Baker's Cart | |
| Hanna, the brewer | Hanna, the baker | |
| Beer-gold UI, beer-mat slots, glass bars | Crust-gold UI, bread-board slots, a loaf rising in the bars | |

Oktoberfest, Bavarian folklore and the dark comic humour all stay: a Wiesn
has as many pretzels as beers.

---

## 4. How the switch would work (when we build it)

It copies a trick the game already uses. The **tutorial** swaps
`res://data/` for `res://data/tutorial/` and nothing else needs to know
(`src/core/tutorial_base.gd`). The bread edition does the same, with one
difference: it **patches** rows instead of replacing whole files.

1. **`data/bread/`** holds small CSVs with only the ID and the columns that
   change. `data/bread/Items.csv` might be just `ID,Name,Description`. Every
   number, price and condition still comes from the main file, so the two
   editions cannot drift apart. IDs never change, so one save works in both.
2. **`assets/bread/` and `audio/bread/`** mirror the normal folders. When the
   game loads a picture or a sound, it looks in the bread folder first and
   falls back to the normal one. Our rule that every picture stays in layers
   helps here: often only the bottle layer needs a bread version.
3. **Words in the code** (the ~98 strings) move into one `Words.csv`, with a
   beer column and a bread column. This is also the first step towards a
   German translation.
4. **One setting, `edition`**, read at start-up: from a launch argument
   (`--edition=bread`), from Settings, or from a first-launch question.
5. **A check tool** (like `art_status.py`) lists every row, picture and sound
   that still shows beer in the bread edition, so we always know what is
   left.

The engine work (steps 1 to 4) is small: one place that resolves a file
path, plus moving the strings. The big job is the content: about 300 rows of
names and text, 60 to 80 pictures and 15 sounds.

### When to do it

- **Now, for free:** keep IDs neutral, keep new player-facing words out of
  the code, and keep the beer part of each new picture on its own layer.
- **Later, after the content settles:** write the bread rows and draw the
  bread art in one pass. Done now, every new beer row would have to be
  written twice while things are still changing daily.

---

## 5. The store: how "two games for one purchase" works

Checked against the Steamworks documentation on 9 Oct
([packages](https://partner.steamgames.com/doc/store/application/packages),
[applications](https://partner.steamgames.com/doc/store/application)).
Assumes Steam, since the game is played on a Steam Deck.

**Option A: one game, two launch choices.** One store page, one library
entry. Steam's launch options ask "Play Sturmball" or "Play Sturmball:
Brotzeit" when you press Play. No extra fee. The store page, trailer and age
rating show the beer edition.

**Option B: two games in the library.** A second app ("Sturmball:
Brotzeit") with the same build and `--edition=bread` set. Steam packages can
hold more than one app, so adding it to the main game's package means one
purchase puts both in the library. It needs its own Steam Direct fee
(US$100), and it gets its own store page, so it could also be sold alone,
with its own screenshots and its own age rating.

**The age rating matters here.** Ratings boards mark alcohol (PEGI's
"Drugs" descriptor covers alcohol, ESRB has "Use of Alcohol"). Under Option
A, the only page a player sees is the beer one. If the point is that people
who avoid alcohol games can find and buy Sturmball without seeing beer
first, only Option B gives them a page of their own.

On consoles every edition is its own product and rating anyway, so
Option B is the shape we would end up with there too.

**Recommendation:** build the in-game switch, start with Option A because it
costs nothing, and add Option B when the store page goes up if the bread
edition should be found and bought by itself. The game is the same build in
both cases.

---

## 6. Questions only Anthony can answer

These are also in `data/Questions.csv` (Q225 to Q229).

1. **Pure reskin, or different rules?** My default: identical rules and
   numbers, only names, words, art and sound change.
2. **Two library entries (Option B) or one game with a launch choice
   (Option A)?** Default: A first, B later if wanted.
3. **One save for both, switchable in Settings?** Default: yes, one save;
   the edition can be changed any time.
4. **How far does it go?** Only drinks, or also the beer-hall look, drunk
   faces, the crowd's steins, the Pub? Default: anything that shows or names
   alcohol is replaced; Bavaria and Oktoberfest stay.
5. **The name of the bread edition.** Draft: "Sturmball: Brotzeit".
