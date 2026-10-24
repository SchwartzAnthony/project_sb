extends SceneTree

# =============================================================
#  ALREADY DRANK CARDS, PHOTOGRAPHED  (24 Oct 2026)
#
#  Opens a friendly match, presses START on the team sheet, waits for the
#  first card row, marks the first two players as having drunk from the bag
#  and photographs the row (CardFace.csv drank_* rows).
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/drank_card_shot.gd
#
#  Pictures: user://drank_cards.png. A tool, not part of the game.
# =============================================================

func _initialize() -> void:
	seed(20261023)
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")

	# Wait for the cards. The team sheet holds for START, so press it.
	var scene: Node = null
	var row: Node = null
	var pressed := false
	for i in 900:
		await create_timer(0.1, true, false, true).timeout
		scene = current_scene
		if scene == null:
			continue
		var sheet = scene.get("_sheet")
		if not pressed and sheet != null and is_instance_valid(sheet) \
				and bool(sheet.get("_opened")):
			sheet.call("_go")
			pressed = true
		row = scene.get("card_container")
		if row != null and is_instance_valid(row) and row.get_child_count() > 0:
			break
	if row == null or row.get_child_count() == 0:
		print("[drank] no card row appeared")
		quit(1)
		return
	for i in 20:
		await process_frame

	var marked := 0
	for child in row.get_children():
		var card = child.get("current_data")
		if card != null and marked < 2:
			scene.drank_this_match[BrewDB.card_key(card)] = true
			marked += 1
	scene.call("_redraw_offered_cards")
	for j in 10:
		await process_frame
	root.get_texture().get_image().save_png("user://drank_cards.png")
	print("[drank] %s" % ProjectSettings.globalize_path("user://drank_cards.png"))
	quit(0)


## The first class with Star players, built into a legal side. The same as
## sheet_hover_shot.gd.
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
