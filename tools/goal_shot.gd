extends SceneTree

# =============================================================
#  THE GOAL CELEBRATION, PHOTOGRAPHED
#
#  Waiting for a real goal means playing a real match and hoping — and a
#  celebration you can only see by scoring is a celebration you will tune
#  four times an evening instead of forty.
#
#  So this opens a match, gets past the team sheet and the line-ups, and
#  then CALLS THE CELEBRATION DIRECTLY with a real card out of your own
#  spreadsheets. Every beat is the beat the match would run, read from
#  Celebration.csv, in order, with your Seconds.
#
#  It photographs it four times: the slide, the huddle, the window and the
#  confetti over all of it.
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/goal_shot.gd
#
#  IT DOES NOT SKIP. `celebration_skippable` is left alone on purpose — the
#  point of the pictures is the timing you wrote down.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	seed(20260922)
	await process_frame
	# A REAL SIDE OUT OF YOUR OWN SPREADSHEETS. Without this the match runs
	# with a scratch team, which has no cards on it — and a celebration of
	# nobody is not a picture of anything.
	_pick_a_team()
	MatchMode.choose(self, "friendly")
	change_scene_to_file("res://src/formations/main_scene.tscn")
	for i in 10:
		await process_frame

	var scene := current_scene
	if scene == null:
		print("[goal] the match did not open")
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

	# ---- past the line-ups ----
	for i in 60:
		await create_timer(0.1, true, false, true).timeout
		var parade = _find(current_scene, "LineUpParade")
		if parade != null:
			parade.call("skip")
			break

	# ---- AND PAST THE KICK-OFF ----
	#
	# This cost me a run. The countdown freezes the pitch and zooms the camera
	# in on the centre circle, so a celebration fired during it is photographed
	# through a close-up with the word START across the middle of it. Waiting
	# for the match to actually be PLAYING is the fix.
	for i in 300:
		await create_timer(0.1, true, false, true).timeout
		if current_scene == null:
			continue
		if int(current_scene.get("current_state")) == 1:   # MatchState.PLAYING
			break
	await create_timer(0.8, true, false, true).timeout

	scene = current_scene
	if scene == null or not is_instance_valid(scene):
		print("[goal] the match went away")
		quit(1)
		return

	var beats := CelebrationBook.steps_for(true)
	if beats.is_empty():
		print("[goal] Celebration.csv has no steps — there is nothing to photograph.")
		quit(0)
		return
	print("[goal] %d beat(s), %.1fs of celebration." % [
		beats.size(), CelebrationBook.total_seconds(true)])

	# ---- somebody to score it ----
	var scorer = _a_player_of_yours(scene)
	if scorer == null:
		print("[goal] nobody on the pitch to score it")
		quit(1)
		return
	scene.set("player_score", int(scene.get("player_score")) + 1)
	if scene.has_method("_update_score_label"):
		scene.call("_update_score_label")

	# ---- and the celebration, timed against the spreadsheet ----
	#
	# Fired rather than awaited, so the pictures are taken WHILE it runs.
	# The four moments are worked out from the rows themselves, so adding a
	# beat moves the camera rather than breaking the tool.
	scene.call("_celebrate_goal", scorer, true)

	await _at(_when(beats, "slide", 0.55))
	_shoot("g_00_slide")
	# AFTER the swarm, not during it: they are still running at 0.9 of the
	# way through and the picture is of nine men in transit rather than of a
	# huddle. The `wait` row that follows is exactly the settling beat.
	await _at(_when(beats, "swarm", 1.0) + 0.25)
	_shoot("g_01_huddle")
	# MEASURED AFTER THE PICTURE, and after a settle: saving a 1920x1080 PNG
	# takes long enough to matter, and the numbers are about where the men
	# end up, not about how fast this machine writes files.
	await create_timer(1.5, true, false, true).timeout
	_clock += 1.5
	_measure_the_ring(scene, scorer)
	# POLL FOR THE WINDOW, DO NOT TIME IT. On a machine with no graphics card
	# this runs at three frames a second and any computed time is wrong by
	# the second picture — the first version of this photographed an empty
	# pitch and I spent a while looking for a window that had not opened yet.
	var panel = null
	for i in 400:
		await create_timer(0.05, true, false, true).timeout
		panel = _find(current_scene, "AnimWindow")
		if panel != null and bool(panel.call("is_open")):
			break
	await create_timer(0.6, true, false, true).timeout
	_shoot("g_02_window")
	# The second panel of the slideshow: wait out the first window row.
	await create_timer(maxf(0.4, _seconds_of(beats, "window") * 0.9), true, false, true).timeout
	_shoot("g_03_window_two")

	print("[goal] pictures in %s" % ProjectSettings.globalize_path("user://"))
	quit(0)


## How many seconds into the celebration a beat of this kind is, `through` of
## the way into it. `skip` passes over that many earlier beats of the same
## kind, which is how the second window panel is found.
## How long the FIRST beat of this kind lasts.
func _seconds_of(beats: Array[Dictionary], kind: String) -> float:
	for beat in beats:
		if String(beat["do"]) == kind:
			return float(beat["seconds"])
	return 1.0


func _when(beats: Array[Dictionary], kind: String, through: float,
		skip: int = 0) -> float:
	var clock := 0.0
	var seen := 0
	for beat in beats:
		var seconds := float(beat["seconds"])
		if String(beat["do"]) == kind:
			if seen == skip:
				return clock + seconds * through
			seen += 1
		clock += seconds
	# No beat of that kind — the end of the list is the honest answer.
	return clock


## Wait until `mark` seconds after the celebration started. Absolute rather
## than relative, so four waits in a row do not drift.
var _clock := 0.0

func _at(mark: float) -> void:
	var wait := mark - _clock
	if wait <= 0.0:
		await process_frame
		return
	await create_timer(wait, true, false, true).timeout
	_clock = mark


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


func _a_player_of_yours(scene: Node):
	var units = scene.call("_all_units")
	print("[goal] %d units on the pitch." % units.size())
	var best = null
	for unit in units:
		if bool(unit.get("is_enemy")):
			continue
		if unit.get("data") == null:
			continue
		# The furthest forward, because that is who would have scored it.
		if best == null or unit.global_position.x > best.global_position.x:
			best = unit
	return best


## ============ IS IT ACTUALLY A RING? ============
##
## A screenshot of a huddle is nine sprites near each other, and "near each
## other" is exactly the kind of thing the eye will accept while the numbers
## say something else. So the numbers get printed: every team-mate's distance
## from the scorer, against the radius Tuning.csv asked for.
func _measure_the_ring(scene: Node, scorer) -> void:
	var db := CardDatabase.get_db()
	var wanted := db.tune_float("celebration_swarm_radius", 110.0)
	print("[goal] %.0f frames a second while it ran." % Engine.get_frames_per_second())

	var gaps: Array[float] = []
	for unit in scene.call("_all_units"):
		if unit == scorer:
			continue
		if bool(unit.get("is_enemy")) != bool(scorer.get("is_enemy")):
			continue
		gaps.append(unit.global_position.distance_to(scorer.global_position))
	if gaps.is_empty():
		return

	gaps.sort()
	var total := 0.0
	for gap in gaps:
		total += gap
	print("[goal] the ring: %d men, %.0f px asked for, %.0f average, %.0f nearest, %.0f furthest"
		% [gaps.size(), wanted, total / float(gaps.size()), gaps[0], gaps[-1]])
	if gaps[-1] > wanted * 1.5:
		print("[goal] ! somebody is %.0f px out — give the swarm row more Seconds." % gaps[-1])


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


## Headless has no window to photograph, and that is a legitimate way to run
## this: the ring measurement is the half of the tool that does not need a
## picture, and headless runs at a frame rate that does not confuse it.
func _shoot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://%s.png" % shot_name)
	print("[goal] %s.png" % shot_name)
