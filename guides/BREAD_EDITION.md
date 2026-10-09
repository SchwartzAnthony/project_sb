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
   editions cannot drift apart. IDs never change, so a save exported from
   one edition can be imported into the other.
2. **`assets/bread/` and `audio/bread/`** mirror the normal folders. When the
   game loads a picture or a sound, it looks in the bread folder first and
   falls back to the normal one. Our rule that every picture stays in layers
   helps here: often only the bottle layer needs a bread version.
3. **Words in the code** (the ~98 strings) move into one `Words.csv`, with a
   beer column and a bread column. This is also the first step towards a
   German translation.
4. **One setting, `edition`**, read at start-up from a launch argument
   (`--edition=bread`), which the Brotzeit app on Steam always passes. Each
   edition keeps **its own saves** (for example `user://bread/`), and
   Settings gets **Export save** and **Import save** so a player can carry
   progress across.
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

**Decision (Anthony, 9 Oct): Option B.** "Sturmball: Brotzeit" is its own
Steam app with its own store page and age rating, in the main game's package
so one purchase gives both. Same build, with `--edition=bread` set.

---

## 6. Anthony's decisions (9 Oct 2026)

Also recorded in `data/Questions.csv` (Q225 to Q229).

1. **Pure reskin.** Same rules and numbers; only names, words, art and
   sound change.
2. **Option B.** A second Steam app, in the same package as the main game.
3. **Separate saves**, with export and import between editions.
4. **Everything** that shows or names alcohol is replaced: drinks, the
   beer-hall UI look, drunk portraits, the crowd's steins, the Pub.
   Bavaria and Oktoberfest stay.
5. **Name: "Sturmball: Brotzeit".**

---

## 7. Languages and where to sell which edition

Researched 9 Oct 2026. **Checked** means a source says it. **Inferred** is
my own reading, to be confirmed before launch.

### Which languages

Share of Steam users by their main language in 2024, as Valve reported at
GDC 2025 ([WN Hub](https://wnhub.io/news/stores-and-publishing/item-47433)):
Simplified Chinese 33.7%, English 33.5%, Russian 8.2%, Spanish 4.6%,
Brazilian Portuguese 2.8%, German 2.5%, Korean 2.2%, French 2.1%,
Japanese 1.7%, Turkish 1.7%, Traditional Chinese 1%. **Checked.**

Recommended order for Sturmball:

| # | Language | Why |
|---|---|---|
| 1 | English | Already done. |
| 2 | German | The game is Bavarian. Its jokes and names (Anstoß Helles, Abstauber, Brotzeit) are German puns, so German is nearly free and plays best. Also the home market. *Inferred.* |
| 3 | Simplified Chinese | A third of Steam, and auto-battlers have a big following there. *Share checked; genre fit inferred.* |
| 4 | Russian | 8% of Steam and cheap to translate ([Alconost](https://alconost.com/en/blog/steam-language-mix-indies)). |
| 5 | Brazilian Portuguese, Spanish | Growing and under-served ([Alconost](https://alconost.com/en/blog/steam-language-mix-indies)). |
| 6 | French, Japanese, Korean | Next tier, after launch if wishlists ask for them. |
| For Brotzeit | Turkish, Arabic, Indonesian | Small on Steam overall, but these are the players the bread edition is for. Store page first, the game later if they buy. *Inferred.* |

Two notes:
- **Start with the store page.** Translating only the store page in 2 or 3
  languages is the cheapest step and can bring 30 to 50% more interest from
  those markets ([Alconost](https://alconost.com/en/blog/steam-language-mix-indies)).
- **Use people, not machine translation.** Sturmball is full of puns and
  Bavarian words, which is where machine translation does worst (same
  source). The `Words.csv` step in section 4 is also what makes a
  translation possible: Godot reads translations from a CSV, so a language
  is one more column.

### Where only Brotzeit should be sold

**No country I could find bans a game just for showing beer.** The Gulf
regulators refuse games for nudity, gambling, religious content and
"material contrary to cultural and social norms"
([GCC guide](https://salmangul.com/gaming-regulation-age-rating-gcc/));
older Saudi bans also named "substance use"
([Niko Partners](https://nikopartners.com/grand-theft-approval-a-turning-point-for-mena-game-regulations/)).
A game they refuse to rate is effectively banned there
([Gmedia](https://en.wikipedia.org/wiki/General_Authority_of_Media_Regulation)).
Steam does hide games in single countries over ratings: Brave x Junction is
blocked on Steam in Germany, China and Saudi Arabia for "regional rating
restrictions" ([RPG Site](https://www.rpgsite.net/news/18742-brave-x-junction-still-not-available-for-switch-in-the-west-pc-steam-in-germany-china-saudi-arabia)).
**Checked.**

So my recommendation, **inferred** from the above:

| Where | Beer edition | Brotzeit |
|---|---|---|
| **Saudi Arabia, Kuwait** (alcohol is illegal there) | Not sold at launch; ask Gmedia for a rating later | Sold |
| **UAE, Qatar, Bahrain, Oman** | Sold, unless a rating comes back refused | Sold, and shown first on the store page |
| **Indonesia, Malaysia** | Sold | Sold, and the edition to advertise |
| **Iran** | Steam does not sell there | — |
| **Everywhere else** (Germany, the US, Europe, Japan, Brazil …) | Sold | Sold |

Two practical points:
- **Germany is fine.** The USK has no problem with beer; the Bavarian
  theme is a plus there. *Inferred.*
- **Indonesia:** from January 2026 a game needs an IGRS rating, filed
  through an Indonesian representative, or it can be blocked
  ([Wikipedia](https://en.wikipedia.org/wiki/Indonesia_Game_Rating_System)).
  This applies to both editions. **Checked.**

Before launch, a rating check per country (IARC on Steam, Gmedia for Saudi
Arabia) gives the real answer. This table is where to start.
