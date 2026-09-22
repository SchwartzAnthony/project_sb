extends SceneTree

# =============================================================
#  THE DRAFT, PHOTOGRAPHED — the cards, the banner, the reveal
#
#  The moment the game is actually played in: four cards on the grass, the
#  ATTACKING / DEFENDING strip above them, and whatever has been played face
#  up above that.
#
#  Getting there is fiddly, which is why this exists:
#
#    AUTO ON  to get through the coin clash, which otherwise waits for a
#             human to call a number and the tool sits there until it is
#             killed;
#    AUTO OFF the instant the draft opens, so the cards STAY on the table
#             instead of being picked half a second later.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/draft_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

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
	for i in 400:
		await create_timer(0.1, true, false, true).timeout
		if not is_instance_valid(scene):
			break
		var row = scene.get("card_container")
		if row != null and row.get_child_count() > 0:
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

	print("[draft] you are %s this round" % (
		"ATTACKING" if bool(scene.get("player_attacks_this_round")) else "DEFENDING"))
	for i in 8:
		await process_frame
	_shoot("d_00_draft")

	# ---- and with a card face up above it ----
	var db := CardDatabase.get_db()
	var shown = _with_reveal(db)
	if shown != null:
		scene.call("_put_on_the_table", shown, true)
		for i in 8:
			await process_frame
		_shoot("d_01_draft_reveal")

	print("[draft] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


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


func _with_reveal(db: CardDatabase):
	for card in db.players:
		for ability_id in [card.active_attack_ability(), card.active_defend_ability()]:
			var ability: AbilityData = db.get_ability(String(ability_id))
			if ability != null and ability.trigger == "reveal":
				return card
	# Nothing with a reveal ability — any card will do for a layout check.
	return db.players[0] if not db.players.is_empty() else null


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
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[draft] %s.png" % shot_name)
