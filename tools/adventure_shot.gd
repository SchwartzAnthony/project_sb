extends SceneTree

# =============================================================
#  SCREENSHOTS OF A REAL ADVENTURE FIGHT
#
#  Opens the actual Adventure scene, hurries it along to the first wave,
#  picks a target so the card window comes up, and saves the screen at each
#  step. It is how the LAYOUT gets checked — a bar cut off at the bottom of
#  the screen is not something a parse check or a soak test can ever see.
#
#      xvfb-run godot --rendering-driver opengl3 \
#          --resolution 1920x1080 --script res://tools/adventure_shot.gd
#
#  The shots land in user:// and the real path is printed. It is a tool, not
#  part of the game, and nothing loads it.
# =============================================================

var _scene: AdventureScene
var _shot := 0


func _initialize() -> void:
	await process_frame
	_pick_a_real_team()
	change_scene_to_file("res://src/adventure/adventure_scene.tscn")
	await process_frame
	await process_frame

	_scene = _find_scene()
	if _scene == null:
		print("[shot] the Adventure scene did not open")
		quit(1)
		return

	# --- 1. the run itself ---
	await _wait(1.2)
	_snap("running")

	# --- 2. hurry the first wave along ---
	_scene._spawn_wave()
	_scene._close_in()
	await _wait(2.5)
	_snap("wave-arriving")

	# --- 3. the fight ---
	var fight := await _wait_for_fight()
	if fight == null:
		print("[shot] no encounter opened")
		quit(1)
		return

	await _wait(0.8)
	_snap("combat-focus")          # the bar, and the icons across the top

	# --- 4. choose a target, which brings the card window up ---
	fight._choose_focus(0)
	await _wait(0.8)
	_snap("combat-draft-tier-1")   # the card window and the bar together

	# --- 5. draft through the tiers, shooting each ---
	for i in 4:
		if fight.step != AdventureEncounter.Step.DRAFT:
			break
		var tier: String = fight._current_tier()
		if tier == "":
			break
		var ready_now := fight.run.available_in(tier, fight.db)
		if ready_now.is_empty():
			break
		fight._pick_card(ready_now[0])
		await _wait(0.7)
		_snap("combat-after-tier-%s" % tier)

	# --- 6. let the move resolve and watch the build-up ---
	for i in 6:
		await _wait(1.0)
		_snap("resolving-%d" % i)

	print("[shot] done")
	quit(0)


## A REAL TEAM, the way the team builder would hand one over — so the shots
## show the game as it is played rather than the stand-in squad the scene
## falls back to when it is opened on its own.
func _pick_a_real_team() -> void:
	var db := CardDatabase.get_db()
	var wanted := ""
	for card in db.players:
		if card.unit_type.strip_edges().to_lower() == "lorelei":
			wanted = card.unit_type
			break
	if wanted == "":
		return

	var roster := db.roster_for_class(wanted)
	var picked := TeamSelection.new()
	picked.unit_type = wanted
	picked.star_tier = db.star_tier_for_class(wanted)
	var stars := db.stars_for_class(wanted)
	picked.star_bundle = stars
	picked.active_star = stars[0] if not stars.is_empty() else null

	for tier in TierLadder.TIERS:
		if tier == picked.star_tier:
			continue
		var made := TierLadder.build(roster, tier, db, false)
		picked.regulars[tier] = made["cards"]
	TeamSelection.store(self, picked)


func _find_scene() -> AdventureScene:
	for child in root.get_children():
		if child is AdventureScene:
			return child as AdventureScene
	return null


func _wait_for_fight() -> AdventureEncounter:
	for i in 40:
		await _wait(0.25)
		if _scene == null or not is_instance_valid(_scene):
			return null
		for child in _scene.get_children():
			if child is AdventureEncounter:
				return child as AdventureEncounter
	return null


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _snap(label: String) -> void:
	var view := root.get_viewport()
	if view == null:
		return
	var picture := view.get_texture().get_image()
	if picture == null:
		return
	var path := "user://shot_%02d_%s.png" % [_shot, label]
	_shot += 1
	picture.save_png(path)
	print("[shot] %s" % ProjectSettings.globalize_path(path))
