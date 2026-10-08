extends SceneTree

# =============================================================
#  THE GREY, FILMED  (round AN, 8 Oct)
#
#  Plays a friendly on AUTO and saves a frame every few frames from the
#  open play before the first PLAY MAKER, through it, to the open play after
#  it - so a GIF shows players greyed ONLY during the Play Maker, and
#  everyone back in colour once it ends.
#
#      godot --rendering-driver opengl3 --resolution 1280x720 \
#          --path . --script res://tools/play_maker_film.gd
#
#  FILM_PLAIN=1 plays it with the Match Maker's "No Extra Abilities" on.
#  Frames go to user://play_maker_film/ with a frames.txt that says, per
#  frame, whether a Play Maker was live. tools/make_film_gif.py makes the GIF.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const SHOOT_EVERY := 0.25        # real seconds between frames
const AFTER_SECONDS := 6.0       # open play filmed after the Play Maker
const GIVE_UP_SECONDS := 400.0

var _dir := "user://play_maker_film"
var _log: Array[String] = []


func _initialize() -> void:
	seed(20261008)
	await process_frame
	CardDatabase.get_db().tuning[CardDatabase._normalise("choice_window_seconds")] = "1"
	var plain := OS.get_environment("FILM_PLAIN") == "1"
	_pick_a_team()
	MatchMode.choose(self, "friendly", plain)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir + "/" + f)
	change_scene_to_file("res://src/formations/main_scene.tscn")

	var scene: Node = null
	var pressed := false
	for i in 400:
		await create_timer(0.2, true, false, true).timeout
		scene = current_scene
		if scene == null:
			continue
		var sheet = scene.get("_sheet")
		if not pressed:
			if sheet != null and is_instance_valid(sheet) and bool(sheet.get("_opened")):
				sheet.call("_go")
				pressed = true
			continue
		var parade := scene.find_child("LineUpParade", true, false)
		if parade != null:
			parade.call("skip")
			continue
		if int(scene.get("current_state")) == 1:   # PLAYING
			break
	if scene == null or not pressed:
		print("[film] the match never opened")
		quit(1)
		return

	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)
	GameSpeed.set_speed(1.0)

	var started := Time.get_ticks_msec()
	var seen_live := false
	var ended_at := -1.0
	var index := 0
	while true:
		await create_timer(SHOOT_EVERY, true, false, true).timeout
		var ran := float(Time.get_ticks_msec() - started) / 1000.0
		if not is_instance_valid(scene) or ran > GIVE_UP_SECONDS:
			break
		var live := PlayerUnit.play_maker_live
		if live:
			seen_live = true
		elif seen_live and ended_at < 0.0:
			ended_at = ran
		_shoot(index, live, seen_live)
		index += 1
		if ended_at >= 0.0 and ran - ended_at > AFTER_SECONDS:
			break
	var file := FileAccess.open(_dir + "/frames.txt", FileAccess.WRITE)
	file.store_string("\n".join(_log))
	file.close()
	print("[film] %d frame(s), Play Maker seen: %s, in %s" % [index, seen_live,
		ProjectSettings.globalize_path(_dir)])
	quit(0)


func _shoot(index: int, live: bool, seen: bool) -> void:
	var stage := "during" if live else ("after" if seen else "before")
	_log.append("%03d %s" % [index, stage])
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("%s/f_%03d.png" % [_dir, index])


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
