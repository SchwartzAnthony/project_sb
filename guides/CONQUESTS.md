# Conquests (Draft Mode) — the idea, parked

Anthony, 9 Oct 2026. **Not built.** The only thing in the game is the torn
banner with the black infinity on the base's top row, and the "not open yet"
note it opens (`base_screen.gd` `_conquests_soon`, words in `Language.csv`
`conquests_*`). It is there so the idea is not forgotten. More detail to come
from Anthony.

## Two kinds of play

| | Season / Tournament (what exists) | Conquests (this) |
|---|---|---|
| What it is | The story mode. Collect, upgrade, beat opponents, become the crown town, the peak of fighting the mythological invasions. Goes through the characters. | The replayable mode. A roguelite run. |
| How it ends | You win the story. | You see how far you get. |
| What you keep | Everything you unlock. | A high score, shown on the main menu board (like Megabonk). |

## The run

- **A mini version of every system on the base.** You start by building new
  towns that you control, and expand them into the realm of the Myths.
- **Traditional roguelite map:** go through the maps, node by node.
- **The goal:** reach the source of the Myths' power, the twisted immortal
  realm deity that is selling itself to keep its infinite realm going.

## The draft

- **Your draft comes from your unlocks in the other modes.** What you have
  earned in the story is what you can be offered.
- **Available early on.**
- **The sacrifice:** to use a player in Conquests, you "sacrifice" them to the
  infinite realm. From then on they can be drafted in this mode indefinitely.

## The banner

A flag on the top row with the others, but **a black infinity symbol on it,
and looking really torn and old.** Today's stand-in: the shared PixelLab
banner cloth, aged by `tools/tear_cloth.py` (bleached to bone, ragged sides,
moth holes, a rip, half the stitches gone), with a script-drawn infinity.
`tools/make_banners.py` builds it like every other banner. PixelLab should
redraw both (ArtOrders.csv `conquests_banner`).

## Open questions (in Questions.csv)

- Q223: does a sacrificed player leave the story mode, or stay in both?
- Q224: which base systems get a mini version first?
