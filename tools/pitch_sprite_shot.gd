extends SceneTree

# =============================================================
#  THE ISOMETRIC PLAYERS IN A REAL MATCH  (round AN)
#
#  Opens a match with The Club (whose players wear the isometric pitch
#  sheets, data/PitchSprites.csv), presses START, and saves the screen every
#  tenth of a second round the ball, so the frames can be put together into
#  a GIF (tools/frames_to_gif.py).
#
#      godot --path . --resolution 1920x1080 --script res://tools/pitch_sprite_shot.gd
#
#  Frames land in user://pitch_shot/. A tool, not part of the game.
# =============================================================

var _scene: Node
var _shot := 0


func _initialize() -> void:
	await process_frame
	_pick_the_club()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 4:
		await process_frame
	_scene = current_scene
	if _scene == null:
		print("[pitch_shot] the match did not open")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://pitch_shot"))

	for i in 30:
		await _wait(0.3)
		var sheet = _scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet) and bool(sheet.get("_opened")):
			sheet.call("_go")
			break
	# Skip the line-up parade the way a player would.
	for i in 6:
		await _wait(0.5)
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		Input.parse_input_event(key)
	var settle := float(OS.get_environment("PITCH_SHOT_WAIT")) if OS.get_environment("PITCH_SHOT_WAIT") != "" else 5.0
	await _wait(settle)
	_snap_whole("wide")
	var iso := 0
	var all := 0
	for unit in _units():
		all += 1
		if bool(unit.get("pitch_sheet")):
			iso += 1
	print("[pitch_shot] %d of %d players on pitch sheets" % [iso, all])
	var seconds := float(OS.get_environment("PITCH_SHOT_SECONDS")) if OS.get_environment("PITCH_SHOT_SECONDS") != "" else 8.0
	var frames := int(seconds / 0.1)
	for i in frames:
		await _wait(0.1)
		_snap_ball()
	print("[pitch_shot] done, %d frames" % _shot)
	quit(0)


func _pick_the_club() -> void:
	var db := CardDatabase.get_db()
	var wanted := "Normal"
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


func _units() -> Array:
	var found: Array = []
	var stack: Array = [_scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is PlayerUnit:
			found.append(node)
		stack.append_array(node.get_children())
	return found


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _snap_whole(label: String) -> void:
	var picture := root.get_viewport().get_texture().get_image()
	picture.save_png("user://pitch_shot/%s.png" % label)


func _snap_ball() -> void:
	var picture := root.get_viewport().get_texture().get_image()
	var b = _scene.get("ball")
	var at := Vector2(picture.get_width(), picture.get_height()) * 0.5
	if b != null and is_instance_valid(b):
		at = (b as Node2D).get_global_transform_with_canvas().origin
	var size := Vector2i(960, 540)
	var corner := Vector2i(
		clampi(int(at.x) - size.x / 2, 0, picture.get_width() - size.x),
		clampi(int(at.y) - size.y / 2, 0, picture.get_height() - size.y))
	var crop := picture.get_region(Rect2i(corner, size))
	crop.save_png("user://pitch_shot/f_%03d.png" % _shot)
	_shot += 1
