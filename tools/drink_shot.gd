extends SceneTree

# =============================================================
#  A PLAYER DRINKING IN A REAL MATCH  (round AN, 10 Oct)
#
#  Opens a friendly with The Club, kicks off, then uses a Small Bottle from
#  the bag on one Club player the way the bag does (main_scene
#  _use_on_card), and saves the screen round that player every tenth of a
#  second while he drinks (PitchAnims.csv drink).
#
#      godot --path . --resolution 1920x1080 --script res://tools/drink_shot.gd
#
#  Frames land in user://drink_shot/. DRINK_SHOT_ITEM picks another item
#  (default small_bottle). A tool, not part of the game.
# =============================================================

var _scene: Node
var _shot := 0


func _initialize() -> void:
	await process_frame
	# A throwaway save, so the bottle and the drunk meter never touch yours.
	GameState.SAVE_PATH = "user://drink_shot_throwaway.json"
	seed(7)
	_pick_the_club()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 4:
		await process_frame
	_scene = current_scene
	if _scene == null:
		print("[drink_shot] the match did not open")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://drink_shot"))
	for i in 30:
		await _wait(0.3)
		var sheet = _scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet) and bool(sheet.get("_opened")):
			sheet.call("_go")
			break
	for i in 6:
		await _wait(0.5)
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		Input.parse_input_event(key)
	await _wait(4.0)

	var drinker: PlayerUnit = null
	for unit in _units():
		var u := unit as PlayerUnit
		if u.is_enemy or u.data == null or not u.pitch_sheet or u.has_ball():
			continue
		# Prefer a look whose sheet has the drink drawn (not the Stand-in).
		var drawn: bool = int(PitchSprite.anim("drink").get("row", 0)) + 8 <= u.artwork.vframes
		if drinker == null or drawn:
			drinker = u
		if drawn:
			break
	if drinker == null:
		print("[drink_shot] no Club player on a pitch sheet")
		quit(1)
		return
	var item_id := OS.get_environment("DRINK_SHOT_ITEM")
	if item_id == "":
		item_id = "small_bottle"
	var entry := AdventureDB.get_db().item(item_id)
	var state: GameState = _scene.get("state")
	state.add_count(item_id, 1)
	for i in 5:
		await _wait(0.1)
		await _snap(drinker)
	_scene.call("_use_on_card", drinker.data, entry)
	print("[drink_shot] %s drinks %s, drinking=%s" % [
		drinker.data.player_name, item_id, drinker.is_drinking()])
	for i in 30:
		await _wait(0.1)
		await _snap(drinker)
		if i % 5 == 0:
			print("[drink_shot] t=%.1f at %s drinking=%s frame=%d" % [
				i * 0.1, drinker.global_position.round(), drinker.is_drinking(),
				drinker.artwork.frame])
	print("[drink_shot] done, %d frames" % _shot)
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


func _snap(who: Node2D) -> void:
	# The match's own announcement covers the pitch; hide it for the film.
	var words = _scene.get("event_announcement")
	if words != null and is_instance_valid(words):
		words.hide()
	await process_frame
	var picture := root.get_viewport().get_texture().get_image()
	# The window may be smaller than the 1920 x 1080 the game is laid out in.
	var shrink := float(picture.get_width()) / root.get_visible_rect().size.x
	var at := who.get_global_transform_with_canvas().origin * shrink
	var size := Vector2i(int(260 * shrink), int(170 * shrink))
	var corner := Vector2i(
		clampi(int(at.x) - size.x / 2, 0, picture.get_width() - size.x),
		clampi(int(at.y) - size.y / 2 - int(15 * shrink), 0, picture.get_height() - size.y))
	picture.get_region(Rect2i(corner, size)).save_png("user://drink_shot/f_%03d.png" % _shot)
	_shot += 1
