extends SceneTree

# =============================================================
#  CHOOSE, THEN LOCK IN — filmed (24 Oct 2026)
#
#  Anthony: "When I hit a little outside of the Items, it skipped, allow the
#  player to go back ... and change them". This opens a friendly, gets to the
#  first draft (as tools/draft_shot.gd does), gives the first card ALREADY
#  DRANK!, then clicks with the real mouse: card one (chosen), card two
#  (changed his mind), LOCK IN. Frames every 0.1 s in user://lock_in/ for a
#  GIF; the next tier's row must have no ALREADY DRANK! left.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --path . --script res://tools/lock_in_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

var _n := 0


func _initialize() -> void:
	seed(20260922)
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 10:
		await process_frame

	var scene := current_scene
	if scene == null:
		print("[draft] the match did not open")
		quit(1)
		return

	# ---- past the team sheet ----
	for i in 200:
		await create_timer(0.2, true, false, true).timeout
		scene = current_scene
		if scene == null:
			continue
		var sheet = scene.get("_sheet")
		if sheet == null or not is_instance_valid(sheet):
			break
		if bool(sheet.get("_opened")):
			sheet.call("_go")
			break
	# ---- the line-ups walk out; photograph them, then skip ----
	for i in 60:
		await create_timer(0.1, true, false, true).timeout
		var parade = _find_parade(current_scene)
		if parade != null:
			await create_timer(1.6, true, false, true).timeout
			_shoot("d_02_lineup_yours")
			await create_timer(2.4, true, false, true).timeout
			_shoot("d_03_lineup_theirs")
			parade.call("skip")
			break
	await create_timer(1.5, true, false, true).timeout

	# ---- AUTO on, so the clash answers itself ----
	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)

	scene.call("trigger_playmaker_event")

	# ---- wait for the clash to be over, then take AUTO off ----
	#
	# `player_attacks_this_round` is settled by the clash, and the draft
	# begins on the next line, so the first frame on which the card row has
	# children is the first frame of the draft.
	var off := false
	for i in 3000:
		await create_timer(0.1, true, false, true).timeout
		if not is_instance_valid(scene):
			break
		var row = scene.get("card_container")
		if row != null and row.get_child_count() >= 3:
			if not off:
				MatchHUD.set_auto_pick(state, false)
				if scene.has_method("_on_auto_pick_changed"):
					scene.call("_on_auto_pick_changed", false)
				off = true
				# Let the row settle after the cards unlock.
				await create_timer(0.5, true, false, true).timeout
			break

	if not off:
		print("[draft] no cards appeared — the clash may still be waiting")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute("user://lock_in")
	var row: Control = scene.get("card_container")
	var cards: Array = []
	# The row is built again once the YOU ARE ... call has gone; wait for it.
	await create_timer(5.0, true, false, true).timeout
	# A Star pick shows one card; take it and wait for a row of a tier.
	for tries in 40:
		cards.clear()
		for child in row.get_children():
			if child is PlayerCardUI and not child.is_queued_for_deletion():
				cards.append(child)
		if cards.size() >= 2:
			break
		if cards.size() == 1 and not bool(scene.get("_pick_in_progress")):
			scene.call("_on_card_selected", cards[0].current_data)
		await create_timer(0.5, true, false, true).timeout
	await create_timer(1.0, true, false, true).timeout
	print("[lock in] %d cards on the table" % cards.size())
	# Wait for a row that stays put for two seconds (the draft can skip an
	# empty tier and lay the next row out again).
	var still := 0
	var seen: Node = null
	while still < 20:
		await create_timer(0.1, true, false, true).timeout
		var now := _cards(row)
		var head: Node = now[0] if now.size() >= 2 else null
		still = still + 1 if head != null and head == seen else 0
		seen = head
	var first: PlayerCardUI = _cards(row)[0]
	scene.get("drank_this_match")[BrewDB.card_key(first.current_data)] = true
	scene.call("_redraw_offered_cards")
	await _film(1.0)
	await _click(_cards(row)[0].get_global_rect().get_center())
	await _film(1.2)
	await _click(_cards(row)[1].get_global_rect().get_center())
	await _film(1.2)
	var second: PlayerCardUI = _cards(row)[1]
	var button := second.get_node_or_null("LockIn") as Control
	print("[lock in] chosen: %s, LOCK IN shown: %s" % [second.chosen, button != null])
	if button != null:
		await _click(button.get_global_rect().get_center())
	await _film(3.0)
	var marks := 0
	for child in row.get_children():
		if child is PlayerCardUI and not child.is_queued_for_deletion() \
				and child.find_child("DrankMark", true, false) != null:
			marks += 1
	print("[lock in] next row: %d cards still say ALREADY DRANK!" % marks)
	print("[lock in] %d frames in %s" % [_n, ProjectSettings.globalize_path("user://lock_in")])
	quit(0)


func _cards(row: Node) -> Array:
	var out: Array = []
	for child in row.get_children():
		if child is PlayerCardUI and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _click(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await _film(0.4)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)
		await process_frame


func _film(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await create_timer(0.1, true, false, true).timeout
		root.get_texture().get_image().save_png("user://lock_in/f_%03d.png" % _n)
		_n += 1
		left -= 0.1


func _find_parade(node: Node):
	if node == null:
		return null
	if node is LineUpParade:
		return node
	for child in node.get_children():
		var hit = _find_parade(child)
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


func _shoot(_shot_name: String) -> void:
	pass
