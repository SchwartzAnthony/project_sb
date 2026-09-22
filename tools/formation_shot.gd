extends SceneTree

# =============================================================
#  THE WHOLE PITCH, PHOTOGRAPHED EVERY FEW SECONDS
#
#  The view you get when you sit and watch a match: the camera pulled all the
#  way out so both goals are on screen, photographed through ordinary waiting
#  play. This is the picture that shows whether the two sides are standing in
#  pairs, whether anybody goes near a touchline, and whether the shape moves.
#
#  `tools/shape_check.gd` puts numbers on the same thing. Use both: the
#  numbers say whether it got better, the pictures say whether it looks right.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/formation_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const SHOTS := 10
const GAP := 3.0


func _initialize() -> void:
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 6:
		await process_frame

	var scene := current_scene
	if scene == null:
		print("[form] the match did not open")
		quit(1)
		return

	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)
	for i in 40:
		var sheet = scene.get("_sheet")
		if sheet == null or not is_instance_valid(sheet):
			break
		if bool(sheet.get("_opened")):
			sheet.call("_go")
			break
		await create_timer(0.2, true, false, true).timeout

	# ---- pull the camera all the way out and hold it there ----
	#
	# The match camera follows the ball and zooms in for the drama, which is
	# right for playing and useless for judging a formation. It is switched
	# off and parked over the middle of the pitch for the whole run.
	var play: Rect2 = scene.call("get_play_rect")
	var camera = scene.get("camera")
	if camera != null and is_instance_valid(camera):
		camera.set_process(false)
		camera.set_physics_process(false)
		camera.global_position = play.position + play.size * 0.5
		var window := Vector2(
			float(DisplayServer.window_get_size().x),
			float(DisplayServer.window_get_size().y))
		var fit := minf(window.x / maxf(play.size.x, 1.0),
			window.y / maxf(play.size.y, 1.0)) * 0.94
		camera.zoom = Vector2(fit, fit)

	for shot in SHOTS:
		await create_timer(GAP, true, false, true).timeout
		if not is_instance_valid(scene):
			break
		if camera != null and is_instance_valid(camera):
			camera.global_position = play.position + play.size * 0.5
		await process_frame
		var units: Array = scene.call("_all_units")
		var pairs := _level_pairs(units)
		var name := "f_%02d" % shot
		root.get_texture().get_image().save_png("user://%s.png" % name)
		print("[form] %s.png   %d players, %d standing level with an opponent"
			% [name, units.size(), pairs])

	print("[form] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


## The same test shape_check.gd uses, printed beside each picture so a number
## and a picture always agree.
func _level_pairs(units: Array) -> int:
	var pairs := 0
	for i in units.size():
		for j in range(i + 1, units.size()):
			if units[i].is_enemy == units[j].is_enemy:
				continue
			var a: Vector2 = units[i].global_position
			var b: Vector2 = units[j].global_position
			if a.distance_to(b) < 120.0 and absf(a.y - b.y) < 26.0:
				pairs += 1
	return pairs


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
