extends SceneTree

# =============================================================
#  FRAMES OF THE WAY INTO A MATCH  (round AN)
#
#  Opens the base, then asks for a match exactly as a button does
#  (ScenePaths.go_to), and saves the screen every tenth of a second: the
#  fade to black, the ball rolling into the goal, the team sheet behind it.
#
#      godot --path . --resolution 1920x1080 --script res://tools/loading_shot.gd
#
#  Frames land in user://loading_shot/. A tool, not part of the game.
# =============================================================

const FRAMES := 60


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute("user://loading_shot")
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file(ScenePaths.BASE)
	for i in 30:
		await process_frame
	var started := Time.get_ticks_msec()
	ScenePaths.go_to(self, ScenePaths.MATCH)
	for i in FRAMES:
		await create_timer(0.1, true, false, true).timeout
		var picture := root.get_viewport().get_texture().get_image()
		picture.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		picture.save_png("user://loading_shot/f_%03d.png" % i)
		print("[shot] %03d at %d ms, curtain up: %s" % [i,
			Time.get_ticks_msec() - started, MatchLoader.is_up(self)])
	print("[shot] done")
	quit(0)


func _pick_a_team() -> void:
	var db := CardDatabase.get_db()
	for card in db.players:
		if not card.is_star():
			continue
		var wanted := card.unit_type
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
		return
