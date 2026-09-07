# Integrating Field Bounds & Menu Updates into Main Scene

This document describes the code changes needed in `main_scene.gd` to fully integrate the new field bounds and menu systems.

---

## Change 1: Freeze Play During HOLD UP! Star Selection

**File:** `res://src/formations/main_scene.gd`

**Location:** `trigger_hold_up_event()` function (around line 913)

**What to do:**

Add a `freeze_play(true)` call before showing the star selection UI, and `freeze_play(false)` after the draft is complete.

**Current code:**
```gdscript
func trigger_hold_up_event() -> void:
	current_state = MatchState.DRAFTING
	current_cycle += 1
	rounds_this_cycle = 0
	round_in_progress = false
	round_player_picks.clear()
	round_enemy_picks.clear()

	abilities.begin_cycle()
	for unit in _all_units():
		unit.reset_for_new_cycle()

	# Enemy rotates its own Star at the same time.
	if not available_enemy_stars.is_empty():
		var new_enemy_star: PlayerData = available_enemy_stars.pick_random()
		available_enemy_stars.erase(new_enemy_star)
		_swap_star_on_pitch(new_enemy_star, true)
		active_enemy_star = new_enemy_star
		enemy_star_tier = new_enemy_star.get_tier_clean()

	print("HOLD UP!  Starting cycle %d" % current_cycle)
	await announce("HOLD UP!")

	draft_phases.assign(["StarChoice"])
	current_phase_index = 0
	start_next_draft_phase()
```

**Updated code:**
```gdscript
func trigger_hold_up_event() -> void:
	current_state = MatchState.DRAFTING
	current_cycle += 1
	rounds_this_cycle = 0
	round_in_progress = false
	round_player_picks.clear()
	round_enemy_picks.clear()

	abilities.begin_cycle()
	for unit in _all_units():
		unit.reset_for_new_cycle()

	# Enemy rotates its own Star at the same time.
	if not available_enemy_stars.is_empty():
		var new_enemy_star: PlayerData = available_enemy_stars.pick_random()
		available_enemy_stars.erase(new_enemy_star)
		_swap_star_on_pitch(new_enemy_star, true)
		active_enemy_star = new_enemy_star
		enemy_star_tier = new_enemy_star.get_tier_clean()

	print("HOLD UP!  Starting cycle %d" % current_cycle)
	await announce("HOLD UP!")

	# Pause on-pitch action while the player picks their next Star
	freeze_play(true)

	draft_phases.assign(["StarChoice"])
	current_phase_index = 0
	start_next_draft_phase()
```

**Also update** `_on_draft_complete()` (around line 1130) to unfreeze:

**Current code:**
```gdscript
func _on_draft_complete() -> void:
	# Kickoff / HOLD UP! drafts have no combat — just restart the clock.
	if not round_in_progress:
		current_state = MatchState.PLAYING
		print("Draft complete — clock running.")
		return

	round_in_progress = false
	resolve_round()
```

**Updated code:**
```gdscript
func _on_draft_complete() -> void:
	# Kickoff / HOLD UP! drafts have no combat — just restart the clock.
	if not round_in_progress:
		# Resume play after star selection
		freeze_play(false)
		current_state = MatchState.PLAYING
		print("Draft complete — clock running.")
		return

	round_in_progress = false
	resolve_round()
```

---

## Change 2: Using FieldBounds (Optional Enhancement)

If you want to use the `FieldBounds` helper class for more advanced field management, add this to main_scene.gd:

**At the top of the file, add the import:**
```gdscript
class_name MainScene
extends Node2D
```

**Add these member variables:**
```gdscript
var field_bounds: FieldBounds = null
```

**In `_ready()` after `spawn_goalies()`, initialize field bounds:**
```gdscript
func _ready() -> void:
	# ... existing code ...
	spawn_goalies()
	spawn_ball()
	
	# Initialize field bounds
	if field_sprite != null:
		field_bounds = FieldBounds.new(field_sprite,
			db.tune_float("field_width", 1280.0),
			db.tune_float("field_height", 720.0))
	
	# ... rest of existing code ...
```

**Update `get_pitch_rect()` to use FieldBounds:**
```gdscript
func get_pitch_rect() -> Rect2:
	if field_bounds != null:
		return field_bounds.get_play_rect()
	if field_sprite != null and field_sprite.texture != null:
		var size := field_sprite.texture.get_size() * field_sprite.global_scale
		var origin := field_sprite.global_position
		if field_sprite.centered:
			origin -= size / 2.0
		return Rect2(origin, size)
	return get_viewport_rect()
```

This is optional — the system works fine without FieldBounds since player_unit.gd already constrains to play_bounds.

---

## Change 3: Reading Field Configuration from Tuning.csv

The field configuration is **already read** by `get_play_rect()`, so no code changes are needed. The tuning rows you added automatically apply:

```
field_width,1280
field_height,720
field_position_x,0
field_position_y,0
field_margin,16
```

These control:
- How big the play area is
- Where it's positioned in the world
- How far players stay from the edges

---

## Summary of Changes Required

**Minimal** (required for freeze during HOLD UP!):
1. Add `freeze_play(true)` before showing star selection UI in `trigger_hold_up_event()`
2. Add `freeze_play(false)` in `_on_draft_complete()` (first branch)

**Enhanced** (optional, for advanced field control):
1. Add `FieldBounds` initialization in `_ready()`
2. Update `get_pitch_rect()` to use `FieldBounds`

---

## Testing the Changes

After making these modifications:

1. **Run a match**
2. **Complete one Cycle** (3 PLAY MAKERs)
3. **When HOLD UP! appears**, verify:
   - Players **stop moving** (freeze takes effect)
   - Ball **doesn't move**
   - Pick your next star player
   - On-pitch action **resumes** immediately after

4. **Check players stay in bounds**:
   - Players should not stand outside the field edge
   - Increase `field_margin` in Tuning.csv if they're too close to edges

---

## File Checklist

After making these changes:

- [ ] Updated `main_scene.gd` with freeze_play calls for HOLD UP!
- [ ] (Optional) Added FieldBounds initialization and usage
- [ ] Updated Tuning.csv with field bounds configuration
- [ ] Tested HOLD UP! star selection — on-pitch action pauses
- [ ] Tested player positions — all stay within field bounds
- [ ] Tested main menu — loads and buttons work

