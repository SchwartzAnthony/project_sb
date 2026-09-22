extends SceneTree

# =============================================================
#  THE TEAM SHEET'S HOVER PANEL, PHOTOGRAPHED
#
#  The lines under a Star on the team sheet are cut to fit three of them
#  across a screen. Hovering the portrait opens a panel beside it with both
#  abilities in full — or the word None.
#
#  A hover is the one thing a normal screenshot cannot catch, so this opens
#  the panel by hand and photographs it, on the LEFT column and on the RIGHT,
#  because the right-hand one has to flip to the other side of the portrait
#  or it hangs off the screen.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/sheet_hover_shot.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	seed(20260921)
	await process_frame
	# A SIDE HAS TO BE CHOSEN FIRST. Without one the match assembles a
	# scratch team on its own and never puts a team sheet up, which reads
	# exactly like `team_sheet` being false and is not.
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 10:
		await process_frame

	var scene := current_scene
	if scene == null:
		print("[hover] the match did not open")
		quit(1)
		return

	# Wait for the sheet to finish filling. It holds for START, so it stays
	# up as long as this needs it to.
	var sheet = null
	for i in 200:
		await create_timer(0.2, true, false, true).timeout
		# RE-READ THE SCENE EVERY TIME. change_scene_to_file() swaps it in on
		# a later frame, so a reference taken up front can be the OLD scene,
		# already freed — which reads as "there is no team sheet" and sent me
		# looking in entirely the wrong place.
		scene = current_scene
		if scene == null:
			continue
		var found = scene.get("_sheet")
		if found != null and is_instance_valid(found):
			sheet = found
			if bool(found.get("_opened")):
				break
	if sheet == null or not is_instance_valid(sheet):
		print("[hover] no team sheet — is `team_sheet` false in Tuning.csv?")
		quit(1)
		return

	# Every portrait on the sheet, left to right. The hover is a Control laid
	# over the picture, so these are what the mouse would be on.
	var spots: Array = []
	_collect(sheet, spots)
	print("[hover] %d portrait(s) on the sheet" % spots.size())
	if spots.is_empty():
		print("[hover] none found — team_sheet_stars may be 0")
		quit(1)
		return

	var shot := 0
	for which in [0, spots.size() - 1]:
		var at: Control = spots[which]
		var card = at.get_meta("card", null)
		if card == null:
			continue
		sheet.call("_open_reader", card, at)
		for j in 10:
			await process_frame
		_shoot("h_%02d_%s" % [shot, "left" if which == 0 else "right"])
		shot += 1

	print("[hover] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


## Every hover Control on the sheet, in the order they were built. They carry
## the card they belong to as metadata so this does not have to guess.
func _collect(from: Node, into: Array) -> void:
	if from is Control and from.has_meta("card"):
		into.append(from)
	for child in from.get_children():
		_collect(child, into)


## The first class in your CSVs that has Star players, built into a legal
## side. Copied from the other tools that need a real team.
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
	print("[hover] %s.png" % shot_name)
