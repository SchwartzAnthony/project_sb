# Hand-edits to `main_scene.gd`

Five small edits. Nothing is deleted — every one of them is either a new line
or a new block dropped in next to code that stays exactly as it is.

**Open** `res://src/formations/main_scene.gd` in the Godot editor.

If a match is started **without** going through the team builder (you pressed
Quick Match, or ran `main_scene.tscn` directly), every one of these changes
sits out of the way and the old random kickoff runs as before. Nothing you
already have stops working.

---

## Edit 1 — remember the chosen team

**Find** this line (it is around line 85, in the block of `var` declarations):

```gdscript
var _freeze_depth: int = 0
```

**Add underneath it:**

```gdscript
## Tier -> the three regulars picked in the team builder. Empty means
## "nobody chose", and spawn_team falls back to a random roster.
var chosen_regulars: Dictionary = {}
```

---

## Edit 2 — start the match automatically when a team was built

**Find** the end of `_ready()` — these are the last four lines of it:

```gdscript
	event_announcement.hide()
	timer_label.text = "00:00"
	start_draft_button.show()
	start_draft_button.pressed.connect(_on_start_draft_pressed)
```

**Add underneath them, still inside `_ready()`** (keep the one tab of indent):

```gdscript

	# Came from the team builder? Then the Star is already chosen — blow the
	# whistle instead of asking again. One frame's wait lets the window finish
	# sizing, so the formation lands inside the visible pitch.
	if TeamSelection.fetch(get_tree()) != null:
		start_draft_button.hide()
		await get_tree().process_frame
		_on_start_draft_pressed()
```

---

## Edit 3 — use the chosen Star instead of drafting one

**Find** this whole function (around line 249):

```gdscript
func _on_start_draft_pressed() -> void:
	start_draft_button.hide()
	current_state = MatchState.DRAFTING
	draft_phases.assign(["Star"])
	current_phase_index = 0
	print("Kickoff — choose your Star Player.")
	start_next_draft_phase()
```

**Replace it with:**

```gdscript
func _on_start_draft_pressed() -> void:
	start_draft_button.hide()

	# The team builder already settled the class, the Star and the 9 regulars.
	var picked := TeamSelection.fetch(get_tree())
	if picked != null and picked.active_star != null:
		_apply_team_selection(picked)
		return

	current_state = MatchState.DRAFTING
	draft_phases.assign(["Star"])
	current_phase_index = 0
	print("Kickoff — choose your Star Player.")
	start_next_draft_phase()
```

---

## Edit 4 — the new kickoff for a built team

**Find** the end of `_resolve_kickoff_star()` — these are its last two lines
(around line 283):

```gdscript
	print("Player class: %s  |  Star: %s (Tier %s)" % [
		chosen.unit_type, chosen.player_name, player_star_tier])
```

**Add this whole new function underneath**, with a blank line before it and
**no indent** — it is a new function, not part of the old one:

```gdscript

## Kick off with the exact team chosen in the team builder. This is the same
## work _resolve_kickoff_star() does, minus the drafting: the Star, the Star
## bundle and the 9 regulars all arrive already decided.
func _apply_team_selection(picked: TeamSelection) -> void:
	chosen_regulars = picked.regulars
	active_player_star = picked.active_star
	player_star_tier = picked.star_tier
	player_star_bundle = picked.star_bundle.duplicate()
	available_player_stars = picked.star_bundle.duplicate()
	available_player_stars.erase(picked.active_star)

	spawn_team(active_player_star, false)
	_choose_enemy_team(active_player_star.unit_type)
	_assign_goalie_data()

	for unit in _all_units():
		unit.clear_round_flags()
		if unit.data == active_player_star and not unit.is_enemy:
			unit.is_playmaker = true
			unit.set_highlight(true)

	give_ball_to(false)
	current_state = MatchState.PLAYING

	print("Your team — %s | Star: %s (Tier %s)" % [
		picked.unit_type, active_player_star.player_name, player_star_tier])
```

---

## Edit 5 — spawn the players you actually picked

**Find** these three lines inside `spawn_team()` (around line 352):

```gdscript
		var positions: Array = tiers[tier_key]
		var pool := filter_units_by_tier(roster, tier_key)
		pool.shuffle()
```

**Replace them with:**

```gdscript
		var positions: Array = tiers[tier_key]
		var pool := filter_units_by_tier(roster, tier_key)
		pool.shuffle()

		# Your side fields exactly the cards chosen in the team builder.
		# The enemy keeps drawing at random, so it stays a fresh opponent.
		if not is_enemy and chosen_regulars.has(tier_key):
			var built: Array[PlayerData] = []
			built.assign(chosen_regulars[tier_key])
			if not built.is_empty():
				pool = built
```

---

## Edit 6 — freeze the pitch while you pick your next Star

This is the "stop kicking the ball during the second and last Star pick" fix.

**Find** these three lines at the end of `trigger_hold_up_event()` (around
line 936):

```gdscript
	draft_phases.assign(["StarChoice"])
	current_phase_index = 0
	start_next_draft_phase()
```

**Replace them with:**

```gdscript
	# Hold the pitch still while you choose. Everything unfreezes again in
	# _on_draft_complete().
	freeze_play(true)

	draft_phases.assign(["StarChoice"])
	current_phase_index = 0
	start_next_draft_phase()
```

**Then find** `_on_draft_complete()` (around line 1130):

```gdscript
func _on_draft_complete() -> void:
	# Kickoff / HOLD UP! drafts have no combat — just restart the clock.
	if not round_in_progress:
		current_state = MatchState.PLAYING
		print("Draft complete — clock running.")
		return
```

**Replace that first block with:**

```gdscript
func _on_draft_complete() -> void:
	# Kickoff / HOLD UP! drafts have no combat — just restart the clock.
	if not round_in_progress:
		freeze_play(false)
		current_state = MatchState.PLAYING
		print("Draft complete — clock running.")
		return
```

> **Why both halves matter:** `freeze_play` counts calls rather than flipping a
> switch, so every `true` needs its matching `false`. Add one without the
> other and the pitch either never stops or never starts again.

---

## Checking it worked

Press **F5** and walk the whole flow:

| Step | What you should see |
|---|---|
| Main menu | Start Game / Quick Match / Quit, and a card count along the bottom |
| Start Game | Class list on the left, three Stars and a formation on the right |
| Click a Star card | Its full card, with the ability spelled out in a sentence |
| LOCK IN | Tier I–IV down the left, your Star's tier locked, collection on the right |
| READY | The match starts with **exactly** the players you slotted |
| First HOLD UP! | Everyone stops dead while you pick — no running, no kicking |
| After picking | Play resumes |

The Output panel prints your line-up at kickoff, so you can check the names
against what you built:

```
[team] Kicking off with:
Tier I: Emberling, Cinderfoot, Ashling
Tier II: ...
Tier III: Brandteufel (Stars)
Tier IV: ...
```

If a player on the pitch is not one you picked, Edit 5 has not taken — check
the indenting on that block.
