extends SceneTree

# =============================================================
#  SCREENSHOTS OF THE FIELD AND ITS SURROUNDINGS
#
#  Opens a friendly, waits for the wide shot, and saves two pictures: the
#  ground as it is, and the same with the zone map (Z) switched on, so you
#  can see the white lines sit exactly on the edge of the player zones.
#  It also prints the play rectangle in PITCH IMAGE pixels, which is the
#  number tools/make_pitch.py needs to draw the lines in the right place.
#
#      godot --path . --resolution 1920x1080 --script res://tools/field_shot.gd
#
#  Add  -- full-house  to the end to also draw the Full House fans (the
#  crowd row of Stadium.csv) without unlocking anything in your save.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

var _scene: Node


func _initialize() -> void:
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 4:
		await process_frame
	_scene = current_scene
	if _scene == null:
		print("[field] the match did not open")
		quit(1)
		return

	# Get past the team sheet so the match is laid out.
	for i in 30:
		var sheet = _scene.get("_sheet")
		if sheet == null or not is_instance_valid(sheet):
			break
		if bool(sheet.get("_opened")):
			sheet.call("_go")
			break
		await _wait(0.3)
	# Skip the line-up reveal the way a player would, then let it settle.
	for i in 6:
		await _wait(0.8)
		var press := InputEventKey.new()
		press.keycode = KEY_ESCAPE
		press.pressed = true
		Input.parse_input_event(press)
	await _wait(3.0)

	var play: Rect2 = _scene.call("get_play_rect")
	var pitch: Rect2 = _scene.call("get_pitch_rect")
	var scale := Vector2(2560.0, 1440.0) / pitch.size
	var inside := Rect2((play.position - pitch.position) * scale, play.size * scale)
	print("[field] pitch on screen %s" % pitch)
	print("[field] zones on screen %s" % play)
	print("[field] zones in the pitch image: x %.0f..%.0f  y %.0f..%.0f  (%.4f / %.4f of the image)" % [
		inside.position.x, inside.end.x, inside.position.y, inside.end.y,
		inside.position.x / 2560.0, inside.position.y / 1440.0])

	if "full-house" in OS.get_cmdline_user_args():
		_show_the_crowd()
		await _wait(0.3)
	_snap("ground")
	var overlay = _scene.get("zone_overlay")
	if overlay != null:
		overlay.set("detail", true)
		overlay.call("queue_redraw")
	await _wait(1.5)
	_snap("zones")
	print("[field] done")
	quit(0)


## The same team the match screenshots use (tools/match_shot.gd).
func _pick_a_team() -> void:
	var db := CardDatabase.get_db()

	# ============ A CLASS THAT HAS EMBLEMS, IF THERE IS ONE ============
	#
	# It used to take the first Star in the whole database, which is a
	# BasicTeam card — the Normal class, which has no Emblems file at all. So
	# every picture came out of a match with no emblem bar in it, and the bar
	# could have been broken for a month without one screenshot noticing.
	#
	# Same lesson as the base screenshot tool last round: a tool has to
	# photograph the thing you are trying to look at, not whatever turns up
	# first in the list.
	var wanted := ""
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		if entry.emblems.is_empty() or entry.stars.is_empty():
			continue
		wanted = entry.unit_type
		break
	if wanted == "":
		for card in db.players:
			if card.is_star():
				wanted = card.unit_type
				break
	if wanted == "":
		return
	print("[shot] class: %s" % wanted)
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


## The Full House layer, laid exactly over the village (same size, same
## centre), only for this picture.
func _show_the_crowd() -> void:
	var back := _scene.get_node_or_null("Stadium_background") as Sprite2D
	var crowd := load("res://assets/field/stadium_crowd.png") as Texture2D
	if back == null or crowd == null:
		print("[field] no village layer to put the crowd on")
		return
	var sprite := Sprite2D.new()
	sprite.texture = crowd
	sprite.scale = back.scale
	sprite.z_index = -30
	_scene.add_child(sprite)
	sprite.global_position = back.global_position
	print("[field] Full House fans drawn for this picture")


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _snap(label: String) -> void:
	var picture := root.get_viewport().get_texture().get_image()
	if picture == null:
		return
	var path := "user://field_%s.png" % label
	picture.save_png(path)
	print("[field] saved %s" % ProjectSettings.globalize_path(path))
