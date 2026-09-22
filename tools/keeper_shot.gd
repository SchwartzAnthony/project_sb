extends SceneTree

# =============================================================
#  THE KEEPER'S NUMBER, PHOTOGRAPHED
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

	# ---- the pitch, with both keepers saying their band ----
	#
	# FROZEN FIRST, because the camera follows the ball during live play and
	# the keepers are the two things furthest from it — the first version of
	# this photographed the centre circle and no keeper at all. A freeze puts
	# the camera on its wide shot, which is the view the whole pitch is in.
	scene.call("freeze_play", true)
	await create_timer(1.2, true, false, true).timeout
	_shoot("k_02_pitch")
	scene.call("freeze_play", false)
	print("[keeper] on the pitch: theirs says %s, yours says %s" % [
		keeper.call("chance_band"), keepers[false].call("chance_band")])

	# ---- the cut-away against a full keeper ----
	var view = scene.get("shootout")
	if view == null:
		print("[keeper] this match has no shootout view")
		quit(0)
		return
	await _cut_away(scene, view, keeper, keeper.get("max_stamina"), 4, "k_00_shootout_fresh")

	# ---- and against an empty one ----
	await _cut_away(scene, view, keeper, 0, 4, "k_01_shootout_broken")

	print("[keeper] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


## Open the cut-away with the keeper set to `stamina`, photograph it, and skip
## it. The stamina is SET rather than shot down to, so the two pictures differ
## in exactly one number and nothing else.
func _cut_away(scene: Node, view, keeper, stamina: int, power: int, shot_name: String) -> void:
	keeper.set("current_stamina", stamina)
	if keeper.has_method("_refresh_plate"):
		keeper.call("_refresh_plate")

	var shooter = null
	for unit in scene.call("_all_units"):
		if not bool(unit.get("is_enemy")) and unit.get("data") != null:
			shooter = unit
			break

	view.call("play_shot", {
		"shooter_card": shooter.get("data") if shooter != null else null,
		"shooter_is_player": true,
		"shot_power": power,
		"keeper_data": keeper.get("data"),
		"keeper_stamina": stamina,
		"keeper_max": keeper.get("max_stamina"),
	})
	print("[keeper] %s: %d stamina, a power-%d shot is %s" % [shot_name, stamina, power,
		ShotOdds.as_text(stamina, keeper.get("max_stamina"), power)])
	await create_timer(1.1, true, false, true).timeout
	_shoot(shot_name)
	view.call("skip")
	await create_timer(2.0, true, false, true).timeout


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
