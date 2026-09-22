extends SceneTree

# =============================================================
#  THE OUT-OF-BOUNDS SEQUENCE, PHOTOGRAPHED
#
#  Four pictures, one per beat that has something to look at:
#
#      o_00_kick_out    the ball on its way over the touchline
#      o_01_window      the animation window: who put it out
#      o_02_walk_up     the thrower standing OUTSIDE the line
#      o_03_choice      the screen where the coin used to be
#
#  AUTO is deliberately OFF for the choice, so the picture is of the two
#  buttons rather than of a screen that answered itself.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/throw_in_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	seed(20260924)
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 10:
		await process_frame

	var pressed := false
	for i in 300:
		await create_timer(0.2, true, false, true).timeout
		if current_scene == null:
			continue
		var sheet = current_scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet):
			if bool(sheet.get("_opened")) and not pressed:
				pressed = true
				sheet.call("_go")
			continue
		break
	for i in 120:
		await create_timer(0.1, true, false, true).timeout
		var parade = _find(current_scene, "LineUpParade")
		if parade == null:
			break
		parade.call("skip")
	for i in 300:
		await create_timer(0.1, true, false, true).timeout
		if current_scene != null and int(current_scene.get("current_state")) == 1:
			break
	await create_timer(0.8, true, false, true).timeout

	var scene := current_scene
	if scene == null:
		print("[throw] the match went away")
		quit(1)
		return

	# ---- make a round happen, and photograph its opening ----
	#
	# AUTO stays OFF: the whole point of the last picture is the two buttons.
	scene.call("trigger_playmaker_event")

	var beats := OutOfBoundsBook.steps()
	print("[throw] %d beat(s), %.1fs before the picks." % [beats.size(), OutOfBoundsBook.total_seconds()])

	# ============ POLL FOR THE BEAT, DO NOT TIME IT ============
	#
	# The first version worked out when each beat would happen from the
	# Seconds column and slept. Saving a 1920x1080 PNG takes long enough to
	# matter, so by the third picture the tool was a second behind the game
	# and photographed the wrong beat — and then reported that nobody had
	# walked over, because nobody had walked over YET.
	#
	# Watching for the thing itself cannot drift. Same lesson as the coin
	# clash, and it cost a run here too.
	for i in 200:
		await create_timer(0.05, true, false, true).timeout
		if scene.get("ball") != null and bool(scene.get("ball").call("is_shooting")):
			break
	_shoot("o_00_kick_out")

	for i in 200:
		await create_timer(0.05, true, false, true).timeout
		var window = _find(current_scene, "AnimWindow")
		if window != null and bool(window.call("is_open")):
			await create_timer(0.5, true, false, true).timeout
			break
	_shoot("o_01_window")

	for i in 400:
		await create_timer(0.05, true, false, true).timeout
		var walked = scene.get("_thrower")
		if walked != null and is_instance_valid(walked):
			# Let the walk finish before photographing where he ended up.
			await create_timer(1.3, true, false, true).timeout
			break
	_shoot("o_02_walk_up")
	_report(scene)

	# ---- and the choice, once the picks have opened it ----
	for i in 400:
		await create_timer(0.1, true, false, true).timeout
		var view = _find(current_scene, "ThrowInView")
		if view != null:
			await create_timer(0.7, true, false, true).timeout
			_shoot("o_03_choice")
			view.call("_choose", true)
			break

	print("[throw] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


## Where the thrower ended up, against where the ball left the pitch. A
## picture cannot tell you whether he is actually OUTSIDE the line.
func _report(scene: Node) -> void:
	var thrower = scene.get("_thrower")
	var spot: Vector2 = scene.get("_throw_spot")
	var rect: Rect2 = scene.call("get_play_rect")
	if thrower == null or not is_instance_valid(thrower):
		print("[throw] ! nobody walked over to take it.")
		return
	var out_by := 0.0
	if spot.y <= rect.get_center().y:
		out_by = rect.position.y - thrower.global_position.y
	else:
		out_by = thrower.global_position.y - rect.end.y
	print("[throw] %s stands %.0f px outside the line (asked for %.0f)." % [
		thrower.data.player_name if thrower.data != null else "?",
		out_by, CardDatabase.get_db().tune_float("throw_in_inset", 26.0)])
	if out_by < 1.0:
		print("[throw] ! he is ON the pitch. A throw-in is taken from off it.")


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
	print("[throw] %s.png" % shot_name)
