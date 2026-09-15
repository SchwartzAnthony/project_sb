# main_scene.gd — no hand-edits any more

**This document used to list six edits for you to type in by hand. Ignore all
of that. It is done.**

The `main_scene.gd` in this delivery already contains every one of those six
edits, plus the whistle and formation fixes described in
**STAR_PLAYERS_AND_THE_WHISTLE.md**.

## What to do

Copy `main_scene.gd` over the one in your project, wherever it lives
(`res://src/formations/` or `res://src/match/` — both are fine, nothing
depends on the folder).

**Do not move `main_scene.tscn`.** Only the `.gd` file is replaced. The scene
file is untouched and still expects the same nodes it always did:

```
SelectionUI/CardContainer
SelectionUI/StartDraftButton
SelectionUI/TimerLabel
SelectionUI/EventAnnouncement
```

## What is in it now

| | |
|---|---|
| Team builder hand-off | Reads your built team and spawns exactly those cards |
| Auto-kickoff | Coming from the builder skips the "choose your Star" row |
| HOLD UP! whistle | Play stops before the banner, restarts only once the new Star is in position |
| Star badges | Put on the kickoff cards; the units carry their own |
| Enemy class | Avoids the classes you were offered and turned down |
| Line-up print | Both squads listed in the Output panel at kickoff |
| Shared geometry | Both teams laid out against one snapshot of the pitch |

## If you had already applied the six edits by hand

Copy the new file over anyway. It is the same work, done properly, plus the
fixes. There is nothing to merge and nothing to undo.
