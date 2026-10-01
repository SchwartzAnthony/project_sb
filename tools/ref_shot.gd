extends SceneTree

# =============================================================
#  THE REFEREE, PHOTOGRAPHED
#
#  The attention bar at three fills, and the referee's window for each of the
#  four things he can say. It opens the REAL match scene and uses the REAL
#  calls the match uses — `Referee.watch_round()` to fill the bar and
#  `RefWindow.show_it()` to bring him on — so a picture here is a picture of
#  the thing a player sees.
#
#  What it cannot do is wait for a real foul: at the Fouls.csv curve you have
#  today that is about one match in two, and a screenshot tool that works
#  half the time is not a tool. So the rounds are fed in by hand and
#  everything downstream of them is the game.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/ref_shot.gd
# =============================================================

var _shot := 0
var _scene: Node


func _initialize() -> void:
	await process_frame
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 6:
		await process_frame
	_scene = current_scene
	if _scene == null:
		print("[ref] the match did not open")
		quit(1)
		return

	var db := CardDatabase.get_db()
	print("[ref] on duty: %s" % Referee.on_duty(db)["name"])

	# Let the team sheet go by and the pitch settle.
	for i in 5:
		await _wait(0.7)
	var sheet = _scene.get("_sheet")
	if sheet != null and is_instance_valid(sheet):
		if sheet.has_method("force_open"):
			sheet.call("force_open")
		else:
			sheet.queue_free()
	await _wait(1.2)

	# ---- the bar, filling ----
	Referee.clear_heat()
	_scene.call("_refresh_ref_bar")
	await _wait(0.4)
	_snap("bar-empty")

	for step in 3:
		# THE SAME CALL THE MATCH MAKES at the end of every round.
		Referee.watch_round(false, 6, db)
		Referee.watch_round(true, 2, db)
		_scene.call("_refresh_ref_bar")
		await _wait(0.5)
		_snap("bar-%d" % (step + 1))

	# ---- and him ----
	var verdicts: Array[String] = ["free kick", "yellow", "red"]
	for verdict in verdicts:
		await RefWindow.show_it(_scene, db, verdict, "Unit Name", false)
		await _wait(0.1)
	print("[ref] the window was shown for each verdict.")

	# One more with the window actually up, caught mid-hold.
	RefWindow.show_it(_scene, db, "yellow", "Unit Name", false)
	await _wait(0.45)
	_snap("ref-yellow")
	await _wait(2.2)

	print("[ref] pictures in user://")
	quit()


func _pick_a_team() -> void:
	var db := CardDatabase.get_db()
	var wanted := ""
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		if entry.emblems.is_empty() or entry.stars.is_empty():
			continue
		wanted = entry.unit_type
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


func _wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout


func _snap(label: String) -> void:
	var view := root.get_viewport()
	if view == null:
		return
	var picture := view.get_texture().get_image()
	if picture == null:
		return
	var path := "user://r_%02d_%s.png" % [_shot, label]
	_shot += 1
	picture.save_png(path)
	print("[ref] %s" % path.get_file())
