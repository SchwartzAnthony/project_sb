extends SceneTree

# =============================================================
#  THE GOALIE WINDOW, FILMED (24 Oct 2026): keeper_shot.gd, but the cut-away
#  is photographed every 0.12 s from opening to closing (kd_NN.png), one shot
#  from each side, for a GIF of the drawn keeper's dive.
#
#  THE KEEPER'S NUMBER, PHOTOGRAPHED (keeper_shot.gd)
#
#  Two pictures, because the chance of scoring is shown in two places and
#  they say different things on purpose:
#
#      k_00_shootout_fresh   the cut-away against a FULL keeper
#      k_01_shootout_broken  the cut-away against an EMPTY one — 100%
#      k_02_pitch            the band under each keeper on the grass
#
#  The cut-away knows the shot power, so it shows ONE number and that number
#  is the one about to be rolled. The pitch does not know yet, so it shows a
#  band — and the band collapses to a flat 100% when the keeper is empty.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/keeper_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	seed(20260923)
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 10:
		await process_frame

	# ---- past the sheet, the line-ups and the kick-off ----
	var pressed := false
	for i in 300:
		await create_timer(0.2, true, false, true).timeout
		if current_scene == null:
			continue
		var sheet = current_scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet):
			# ONCE. Pressing START on every poll is what turned up the
			# double-kick-off bug — see _on_kick_off_wanted() in main_scene.
			if bool(sheet.get("_opened")) and not pressed:
				pressed = true
				sheet.call("_go")
			continue
		# SKIP, AND THEN KEEP CHECKING. The parade puts your side up, then
		# theirs, and `skip` on the first one does not stop the second from
		# being built — which is how the first run of this tool photographed
		# the cut-away through a team sheet.
		var parade = _find(current_scene, "LineUpParade")
		if parade != null:
			parade.call("skip")
			continue
		break
	for i in 100:
		await create_timer(0.1, true, false, true).timeout
		var still = _find(current_scene, "LineUpParade")
		if still == null:
			break
		still.call("skip")
	for i in 300:
		await create_timer(0.1, true, false, true).timeout
		if current_scene != null and int(current_scene.get("current_state")) == 1:
			break
	await create_timer(0.8, true, false, true).timeout

	var scene := current_scene
	if scene == null:
		print("[keeper] the match went away")
		quit(1)
		return

	var keepers: Dictionary = scene.get("goalies")
	var keeper = keepers.get(true)      # the enemy keeper, the one you shoot at
	if keeper == null:
		print("[keeper] no keeper on the pitch")
		quit(1)
		return

	var view = scene.get("shootout")
	await _film(scene, view, keeper, true, 0)
	await _film(scene, view, keepers[false], false, 40)
	print("[keeper] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


func _film(scene: Node, view, keeper, mine: bool, first: int) -> void:
	var shooter = null
	for unit in scene.call("_all_units"):
		if bool(unit.get("is_enemy")) != mine and unit.get("data") != null:
			shooter = unit
			break
	view.call("play_shot", {
		"shooter_card": shooter.get("data") if shooter != null else null,
		"shooter_is_player": mine,
		"shot_power": 12,
		"keeper_data": keeper.get("data"),
		"keeper_stamina": keeper.get("current_stamina"),
		"keeper_max": keeper.get("max_stamina"),
	})
	for i in 32:
		await create_timer(0.12, true, false, true).timeout
		_shoot("kd_%02d" % (first + i))
		if not bool(view.call("is_running")):
			break
	await create_timer(1.0, true, false, true).timeout


func _find(node: Node, wanted: String):
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child in node.get_children():
		var hit = _find(child, wanted)
		if hit != null:
			return hit
	return null


func _pick_a_team() -> void:
	var db := CardDatabase.get_db()
	var wanted := ""
	for card in db.players:
		if card.is_star():
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
		picked.regulars[tier] = TierLadder.build(roster, tier, db, false)["cards"]
	TeamSelection.store(self, picked)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[keeper] %s.png" % shot_name)
