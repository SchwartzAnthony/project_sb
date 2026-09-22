extends SceneTree

# =============================================================
#  THE TEAM SHEET, PHOTOGRAPHED
#
#  Six Stars, three a side, with what each of them does printed underneath in
#  two tagged lines — ATK in the warm colour, DEF in the cool one, the same
#  two the strip above the cards uses.
#
#  This replaces tools/sheet_hover_shot.gd, which photographed a hover panel
#  that no longer exists: the abilities were printed AND hovered, which is
#  the same sentence twice and one of them hidden behind a mouse.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/sheet_shot.gd
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

	# Wait for the sheet to finish opening, then photograph it. It is NOT
	# pressed — the picture is the point.
	var sheet = null
	for i in 200:
		await create_timer(0.2, true, false, true).timeout
		if current_scene == null:
			continue
		sheet = current_scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet) and bool(sheet.get("_opened")):
			break
		sheet = null

	if sheet == null:
		print("[sheet] the team sheet never opened")
		quit(1)
		return

	await create_timer(0.6, true, false, true).timeout
	_shoot("t_00_team_sheet")

	# And a count, because the picture cannot tell you whether a Star with no
	# ability got its "None" line or simply got nothing.
	var lines := _count_ability_lines(sheet)
	print("[sheet] %d ability line(s) printed. Six Stars should give twelve." % lines)
	if lines % 2 != 0:
		print("[sheet] ! an odd number — somebody is missing a side.")

	print("[sheet] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


## An ability line is an HBox holding the tag and the sentence, so counting
## the tags counts the lines.
func _count_ability_lines(node: Node) -> int:
	var found := 0
	var label := node as Label
	if label != null and label.text in ["ATK", "DEF",
			Loc.text("atk_tag", "ATK"), Loc.text("def_tag", "DEF")]:
		found += 1
	for child in node.get_children():
		found += _count_ability_lines(child)
	return found


func _pick_a_team() -> void:
	var db := CardDatabase.get_db()
	# A CLASS WHOSE STARS ACTUALLY DO SOMETHING. The first class with a Star
	# is usually the journeymen, whose sheet is six lines of "None" — which
	# proves the None case and nothing else. This prefers a class with a real
	# ability on it, so the picture shows a long sentence wrapping under a tag.
	var wanted := ""
	var fallback := ""
	for card in db.players:
		if not card.is_star():
			continue
		if fallback == "":
			fallback = card.unit_type
		if String(card.active_attack_ability()).strip_edges() != "" \
				or String(card.active_defend_ability()).strip_edges() != "":
			wanted = card.unit_type
			break
	if wanted == "":
		wanted = fallback
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
	print("[sheet] %s.png" % shot_name)
