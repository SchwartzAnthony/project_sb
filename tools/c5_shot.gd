extends SceneTree

# =============================================================
#  THE C5 QUESTIONS, PHOTOGRAPHED  (round AC)
#
#      SOAK_CLASS=Lorelei xvfb-run -a godot --path . --rendering-driver opengl3 \
#          --resolution 1920x1080 --script res://tools/c5_shot.gd
#
#  A real match with AUTO on, except that AUTO is told to ASK about the
#  Reveal and the exhaust swap - so the "Reveal it?" window and the lit
#  exhaust zone come up. Each window answers itself after 2.5 seconds
#  (choice_window_seconds, for this run only). Every time one is open it is
#  photographed: c5_000.png ... A tool; nothing loads it.
# =============================================================

const RUN_SECONDS := 240.0
const MAX_SHOTS := 16


func _initialize() -> void:
	seed(20261003)
	await process_frame
	# In the TEST ENVIRONMENT, so the "ask me" flags set below never reach
	# the real save (round AD: they did once, and every soak after it waited
	# for an answer nobody gave).
	TestEnvironment.enter(self)
	var db := CardDatabase.get_db()
	db.tuning[CardDatabase._normalise("choice_window_seconds")] = "2.5"
	var wanted := OS.get_environment("SOAK_CLASS")
	if wanted == "":
		wanted = "Lorelei"
	var roster := db.roster_for_class(wanted)
	var picked := TeamSelection.new()
	picked.unit_type = wanted
	picked.star_tier = db.star_tier_for_class(wanted)
	var stars := db.stars_for_class(wanted)
	picked.star_bundle = stars
	picked.active_star = stars[0] if not stars.is_empty() else null
	for tier in TierLadder.TIERS:
		if tier != picked.star_tier:
			picked.regulars[tier] = TierLadder.build(roster, tier, db, false)["cards"]
	TeamSelection.store(self, picked)
	MatchMode.choose(self, "friendly")
	var state := GameState.fetch(self)
	for kind in ["reveal", "exhaust"]:
		state.set_flag("auto_asks_" + kind, true)
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 10:
		await process_frame
	for i in 300:
		await create_timer(0.2, true, false, true).timeout
		var scene := current_scene
		if scene == null:
			continue
		var sheet = scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet):
			if bool(sheet.get("_opened")):
				sheet.call("_go")
			continue
		var parade = _find(scene, "LineUpParade")
		if parade != null:
			parade.call("skip")
			continue
		break
	var scene := current_scene
	MatchHUD.set_auto_pick(scene.get("state"), true)
	scene.call("_on_auto_pick_changed", true)
	GameSpeed.set_speed(4.0)
	var st = scene.get("state")
	for kind in ["reveal", "exhaust"]:
		st.set_flag("auto_asks_" + kind, true)
	print("[c5 shot] asks reveal: %s" % st.has_flag("auto_asks_reveal"))
	# The AUTO menu opens when AUTO goes on - answer it with what is set.
	var started := Time.get_ticks_msec()
	var shots := 0
	var last_title := ""
	while float(Time.get_ticks_msec() - started) / 1000.0 < RUN_SECONDS and shots < MAX_SHOTS:
		await create_timer(0.4, true, false, true).timeout
		var w = _find(root, "ChoiceWindow")
		if w != null:
			GameSpeed.set_speed(1.0)
			var title := _title_of(w)
			if title != last_title or shots % 3 == 0:
				root.get_texture().get_image().save_png("user://c5_%03d.png" % shots)
				print("[c5 shot] %d  %s" % [shots, title])
				shots += 1
			last_title = title
		else:
			last_title = ""
			GameSpeed.set_speed(4.0)
	print("[c5 shot] %d picture(s) in %s" % [shots, ProjectSettings.globalize_path("user://")])
	quit(0)


func _title_of(node: Node) -> String:
	for child in node.get_children():
		if child is Label and String((child as Label).text).length() > 3:
			return (child as Label).text
		var deeper := _title_of(child)
		if deeper != "":
			return deeper
	return ""


func _find(node: Node, wanted: String):
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child in node.get_children():
		var hit = _find(child, wanted)
		if hit != null:
			return hit
	return null
