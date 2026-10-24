extends SceneTree

# =============================================================
#  THE FREE KICK NUMBER GAME, WHEEL LOOK, FILMED (24 Oct 2026)
#
#  Starts a friendly, puts the number call up over the pitch and photographs
#  it every 0.1 s (cw_NN.png in user://clash_wheel/): the call, the wheel
#  spinning, the stop, the reveal and the burst. The call is made on the
#  number the wheel will stop on, so the exact-call burst is in the film.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/clash_wheel_shot.gd
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
		quit(1)
		return
	scene.call("freeze_play", true)
	var rps = scene.get("rps")
	rps.set("spin_seconds", 1.8)
	DirAccess.make_dir_recursive_absolute("user://clash_wheel")
	rps.call("start")
	rps.call("set_locked", false)
	var frame := 0
	for i in 8:
		await process_frame
	_shoot("cw_%03d" % frame); frame += 1
	await create_timer(0.4, true, false, true).timeout
	# Where will it stop? _pick draws their number (one randi), _land the stop.
	seed(4242)
	randi()
	var stop := 1 + randi() % 10
	seed(4242)
	rps.call("_pick", stop)
	for i in 70:
		await create_timer(0.1, true, false, true).timeout
		_shoot("cw_%03d" % frame); frame += 1
	quit(0)


func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://clash_wheel/%s.png" % shot_name)


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
