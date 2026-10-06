extends SceneTree

# =============================================================
#  THE OPENING OF A NEW GAME, PLAYED THROUGH  (round AN)
#
#      godot --headless --path . --script res://tools/intro_check.gd
#
#  Plays what a new player sees, through the REAL screens, in a save of its
#  own (user://intro_check/) so your own saves are never touched:
#
#    1. the base opens on a brand-new save -> the prologue plays
#    2. the prologue ends -> back at the base -> the FIRST MATCH starts by
#       itself (Progression.csv kick_off_first_match, MatchModes.csv intro)
#    3. the first match: IntroSquad.csv - Koch and random players, no Stars
#    4. full time -> star-intro in the bar -> back at the base -> the
#       SECOND MATCH starts (intro2): the same players, Koch and the Stars
#    5. full time -> back to normal
#
#  It answers every story line and plays both matches on AUTO, fast. At the
#  end it prints PASS or FAIL for each step, and "NO TROUBLE" if all passed.
#  Run it WITHOUT --headless and it also saves screenshots to
#  user://intro_check/shot_*.png (the story, the team sheet, the pitch, the
#  coach's box).
# =============================================================

const DIR := "user://intro_check"
const GIVE_UP_SECONDS := 900.0

var _results: Array[String] = []
var _failed := false
var _first_names: Array[String] = []
var _talks := 0


func _initialize() -> void:
	seed(20261006)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var files: Array[String] = ["story_state.json", "teams.json"]
	for file_name in files:
		var path := DIR + "/" + file_name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameState.SAVE_PATH = DIR + "/story_state.json"
	TeamRoster.SAVE_PATH = DIR + "/teams.json"
	GameState.forget(self)
	CardDatabase.get_db().tuning[CardDatabase._normalise("choice_window_seconds")] = "1"
	await process_frame

	# ---- 1. a brand-new save opens the base ----
	change_scene_to_file(ScenePaths.BASE)
	var story := await _wait_for_scene("dialogue", 20.0)
	_check(story != "", "a new save opens the base and a story plays (%s)" % story)
	var state := GameState.fetch(self)
	_check(state.has_flag("tutorial_match"), "new_game set flag:tutorial_match")

	await create_timer(1.0, true, false, true).timeout
	await _shot("1_story")
	# ---- 2. the prologue ends -> the first match starts on its own ----
	await _read_story(60.0)
	_check(state.has_flag("prologue_done"), "the prologue set flag:prologue_done")
	var scene := await _wait_for_match(30.0)
	_check(scene != null, "after the prologue, the first match opens by itself")
	if scene == null:
		_finish()
		return
	_check(String(MatchMode.current(self).get("id", "")) == "intro", "it is the intro mode")

	# ---- 3. who is on the pitch ----
	var picked := TeamSelection.fetch(self)
	_check(picked != null and picked.plain, "the side is plain (no Stars)")
	if picked != null:
		var names := _names_of(picked)
		_first_names = names
		print("[intro] first match: %s" % ", ".join(names))
		_check(names.has("Koch"), "Koch plays")
		_check(picked.active_star != null and picked.active_star.player_name == "Koch"
			and picked.active_star.unit_type == "Bergmännlein"
			and picked.active_star.tier == "III" and picked.active_star.base_power_left == 3,
			"Koch is a Bergmännlein, Tier III Power 3, and kicks off")
		_check(names.size() == 12, "twelve players in the squad (%d)" % names.size())
		var women := 0
		for card in _cards_of(picked):
			if card.artwork != null and card.artwork.resource_path.contains("female"):
				women += 1
		print("[intro] %d of them wear the women's sprite." % women)
		_check(RecruitBook.names(state).size() == 11, "the eleven random players joined the base (%d)" % RecruitBook.names(state).size())
	await _play_to_full_time(scene)
	var stars_on_pitch := 0
	if is_instance_valid(scene):
		for unit in scene.call("_all_units"):
			if not unit.is_enemy and unit.is_star_player:
				stars_on_pitch += 1
	_check(stars_on_pitch == 0, "no Star badge on your side in the first match")

	# ---- 4. star-intro, then the second match ----
	var after := await _wait_for_scene("dialogue", 30.0)
	_check(after != "", "full time sends you to a story scene")
	_check(state.has_flag("tutorial_match_2") and not state.has_flag("tutorial_match"),
		"first_match_is_over swapped the flags")
	await _read_story(60.0)
	scene = await _wait_for_match(30.0)
	_check(scene != null, "after star-intro, the second match opens by itself")
	if scene == null:
		_finish()
		return
	_check(String(MatchMode.current(self).get("id", "")) == "intro2", "it is the intro2 mode")
	picked = TeamSelection.fetch(self)
	if picked != null:
		var names := _names_of(picked)
		print("[intro] second match: %s" % ", ".join(names))
		_check(not picked.plain and picked.active_star != null and picked.active_star.player_name == "Belial",
			"the Stars are back: Belial kicks off")
		for star in ["Belial", "Valefor", "Haures", "Koch"]:
			_check(names.has(star), "%s plays" % star)
		var same := 0
		for name_text in names:
			if _first_names.has(name_text):
				same += 1
		_check(same >= 9, "the first team came back (%d names the same, Koch included)" % same)

	# ---- MatchTalk: a box over the pitch, tried with a scene that exists ----
	MatchTalk._load()
	MatchTalk._rows.append({"id": "intro_check_talk", "mode": "intro2", "when": "duel_won",
		"requires": "", "scene": "star-intro", "once": true})
	await _play_to_full_time(scene)
	_check(_talks > 0, "MatchTalk.csv put the coach's box over the pitch and the match carried on (%d box)" % _talks)
	_check(not state.has_flag("tutorial_match_2"), "second_match_is_over cleared flag:tutorial_match_2")
	_check(String(MatchMode.stand_in_for("friendly", state)) == "friendly",
		"after the intro, Play a match is an ordinary friendly again")
	_finish()


# -------------------------------------------------------------

func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(DIR + "/shot_%s.png" % shot_name)
	print("[intro] screenshot %s" % shot_name)


func _check(ok: bool, what: String) -> void:
	_results.append(("PASS  " if ok else "FAIL  ") + what)
	print(("[intro] PASS  " if ok else "[intro] FAIL  ") + what)
	if not ok:
		_failed = true


func _finish() -> void:
	print("")
	for line in _results:
		print("  " + line)
	print("")
	print("[intro] NO TROUBLE." if not _failed else "[intro] SOMETHING FAILED - see above.")
	quit(1 if _failed else 0)


func _scene_name() -> String:
	if current_scene == null:
		return ""
	return String(current_scene.scene_file_path).get_file().get_basename()


func _wait_for_scene(part: String, seconds: float) -> String:
	var waited := 0.0
	while waited < seconds:
		await create_timer(0.2, true, false, true).timeout
		waited += 0.2
		if _scene_name().contains(part):
			return _scene_name()
	return ""


## Click through every line until the story screen goes away.
func _read_story(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await create_timer(0.1, true, false, true).timeout
		waited += 0.1
		if not _scene_name().contains("dialogue"):
			return
		var view := current_scene
		if view.has_method("_finish_typing"):
			view.call("_finish_typing")
		var line = view.get("_line")
		if line != null and line.has_choices():
			var choices: Array = line.available_choices(view.get("state"))
			if not choices.is_empty():
				view.call("_on_choice", choices[0])
				continue
		view.call("_advance")


func _wait_for_match(seconds: float) -> Node:
	var waited := 0.0
	while waited < seconds:
		await create_timer(0.2, true, false, true).timeout
		waited += 0.2
		if _scene_name() == "main_scene":
			return current_scene
	print("[intro] still on '%s' after %.0fs." % [_scene_name(), seconds])
	return null


func _play_to_full_time(scene: Node) -> void:
	var sheet_shot := false
	for i in 300:
		await create_timer(0.2, true, false, true).timeout
		if not is_instance_valid(scene):
			return
		var sheet = scene.get("_sheet")
		if sheet != null and is_instance_valid(sheet):
			if bool(sheet.get("_opened")):
				if not sheet_shot:
					sheet_shot = true
					await create_timer(1.5, true, false, true).timeout
					await _shot("2_sheet_%s" % String(MatchMode.current(self).get("id", "")))
				sheet.call("_go")
			continue
		var parade = _find(scene, "LineUpParade")
		if parade != null:
			parade.call("skip")
			continue
		break
	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, true)
	if scene.has_method("_on_auto_pick_changed"):
		scene.call("_on_auto_pick_changed", true)
	GameSpeed.set_speed(4.0)
	var started := Time.get_ticks_msec()
	var pitch_shot := false
	while is_instance_valid(scene):
		await create_timer(0.3, true, false, true).timeout
		if not is_instance_valid(scene):
			break
		# A coach's box pauses the game: read it like a player would.
		if not pitch_shot and float(Time.get_ticks_msec() - started) > 6000.0:
			pitch_shot = true
			await _shot("3_pitch_%s" % String(MatchMode.current(self).get("id", "")))
		var box = scene.get("_talk_box")
		if box != null and is_instance_valid(box):
			_talks += 1
			await _shot("4_talk")
			while is_instance_valid(box):
				box.call("_next")
				await create_timer(0.05, true, false, true).timeout
		if not is_instance_valid(scene):
			break
		if int(scene.get("current_state")) == 4:
			print("[intro] FULL TIME %d-%d" % [int(scene.get("player_score")), int(scene.get("enemy_score"))])
			# the match moves on by itself (a story, or the report)
			for i in 100:
				await create_timer(0.2, true, false, true).timeout
				if not is_instance_valid(scene) or _scene_name() != "main_scene":
					break
			break
		if float(Time.get_ticks_msec() - started) / 1000.0 > GIVE_UP_SECONDS:
			_check(false, "the match reached full time")
			break
	GameSpeed.reset()


func _names_of(picked: TeamSelection) -> Array[String]:
	var out: Array[String] = []
	for card in _cards_of(picked):
		out.append(card.player_name)
	return out


func _cards_of(picked: TeamSelection) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for card in picked.star_bundle:
		out.append(card)
	for tier_key in picked.regulars.keys():
		for card in picked.regulars[tier_key]:
			out.append(card)
	return out


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
