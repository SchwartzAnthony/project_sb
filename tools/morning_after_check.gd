extends SceneTree

# =============================================================
#  "THE MORNING AFTER", PLAYED THROUGH  (round AN)
#
#      godot --headless --path . --script res://tools/morning_after_check.gd
#
#  The Tutorial after the final whistle (tutorial_morning.gd), through the
#  real screens, in a save of its own (user://morning_check/):
#
#    1. a new save says YES to the Tutorial; the tutorial match is skipped
#       and its side (TutorialSquad.csv) is handed straight to full time
#    2. the full-time scene, then the base: the Head Coach takes you to the
#       Dorms (somebody is in bed), explains the beds, comes back, says
#       goodbye, and the Adventure banner lights up
#    3. the Bounty Board, the Brewer's Errand, and the run with Koch's stops
#       (MatchTalk.csv Mode tutorial_adventure), played to the end
#    4. home: the Dorms again (the party in bed), then the Tutorial ends at
#       your own base with the starting team and nothing kept
#
#  Run it WITHOUT --headless and every box is saved as a picture in
#  user://morning_check/frames/.
# =============================================================

const DIR := "user://morning_check"

const BOXES: Array[String] = ["tut-morning-base", "tut-morning-beds",
	"tut-morning-handover", "tut-adv-board", "tut-adv-start", "tut-adv-wave",
	"tut-adv-focus", "tut-adv-draft", "tut-adv-pile", "tut-adv-hit",
	"tut-adv-loot", "tut-adv-boss", "tut-adv-claim", "tut-morning-home",
	"tut-morning-beds-2"]

var _results: Array[String] = []
var _failed := false
var _seen: Array[String] = []
var _windowed := false
var _shots := 0
## Which screen each box came up over.
var _where: Dictionary = {}
var _sleepers_before: Array[String] = []
var _sleepers_after: Array[String] = []
var _played_at_home := -1


func _initialize() -> void:
	seed(20261008)
	_windowed = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/frames"))
	var db := CardDatabase.get_db()
	db.tuning[CardDatabase._normalise("choice_window_seconds")] = "0"
	db.tuning[CardDatabase._normalise("match_talk_line_seconds")] = "0"
	await process_frame

	# ---- 1. YES, and straight to full time ----
	_fresh_save()
	var own := GameState.SAVE_PATH
	Tutorial.start(self, false)
	_check(Tutorial.active(self) and GameState.SAVE_PATH == Tutorial.SEALED_SAVE,
		"the Tutorial plays in a save of its own")
	await _wait_for_scene("dialogue", 20.0)
	var state := GameState.fetch(self)
	var side := SquadSheet.selection_from("TutorialSquad.csv", db, state, true)
	var played: Array = []
	if side != null:
		played.append_array(side.all_regulars())
		for star in side.star_bundle:
			if star != null and not played.has(star):
				played.append(star)
		if side.active_star != null and not played.has(side.active_star):
			played.append(side.active_star)
	_check(played.size() == 12, "the tutorial side is twelve players (%d)" % played.size())
	Tutorial.full_time(self, played)

	# ---- 2. the full-time scene, the base, the Dorms ----
	await create_timer(0.5, true, false, true).timeout
	_check(_scene_name().contains("dialogue"), "full time plays a scene, not the base")
	await _shot("fulltime")
	await _read_story(60.0)
	_check(await _wait_for_scene("base", 20.0) != "", "then the base of the tutorial save")
	_check(Tutorial.active(self), "the Tutorial is still on")
	await _read_boxes(10.0)
	_check(String(_where.get("tut-morning-beds", "")).contains("dorms"),
		"the Head Coach explains the beds in the Dorms")
	_check(not _sleepers_before.is_empty(), "after the match somebody is in bed (%s)" % str(_sleepers_before))
	_check(String(_where.get("tut-morning-handover", "")).contains("base"),
		"and says goodbye back at the base")

	# ---- 3. the Adventure ----
	change_scene_to_file(ScenePaths.BOUNTY_BOARD)
	await _wait_for_scene("bounty", 10.0)
	await _read_boxes(10.0)
	var board := current_scene
	var errand := AdventureDB.get_db().bounty("tut_brewers_errand")
	var marsh := AdventureDB.get_db().biome("marshlands")
	_check(not errand.is_empty() and not marsh.is_empty(), "the Brewer's Errand is on the board")
	board.call("_choose_biome", marsh)
	board.set("_chosen_bounty", errand)
	board.call("_on_start")
	_check(String(MatchMode.current(self).get("id", "")) == "tutorial_adventure",
		"the run is the tutorial's Adventure (%s)" % String(MatchMode.current(self).get("id", "")))
	var scene := await _wait_for_adventure(40.0)
	_check(scene != null, "the run starts with the Adventure Team, no team to pick")
	if scene == null:
		_finish()
		return
	await _play_run(scene)

	# ---- 4. home ----
	await _read_boxes(10.0)
	_check(String(_where.get("tut-morning-home", "")).contains("base"), "home at the base")
	_check(_played_at_home == 1, "the run was counted (%d)" % _played_at_home)
	_check(String(_where.get("tut-morning-beds-2", "")).contains("dorms"), "Koch takes you back to the Dorms")
	var woke := 0
	for name_text in _sleepers_before:
		if not _sleepers_after.has(name_text):
			woke += 1
	_check(woke == _sleepers_before.size(),
		"the match side woke up: before %s, after %s" % [str(_sleepers_before), str(_sleepers_after)])
	_check(_sleepers_after.size() > 0, "the party is in bed (%s)" % str(_sleepers_after))
	_check(await _wait_for_scene("base", 20.0) != "", "the Tutorial ends at the base")
	_check(not Tutorial.active(self), "the Tutorial is over")
	_check(GameState.SAVE_PATH == own, "your own save is back")
	_check(not FileAccess.file_exists(Tutorial.SEALED_SAVE), "the tutorial's save is thrown away")
	state = GameState.fetch(self)
	_check(RecruitBook.names(state).size() == 12, "the base has the starting team (%d)" % RecruitBook.names(state).size())
	_check(not state.has_flag(TutorialMorning.FLAG), "no morning flag in your save")
	for box in BOXES:
		_check(_seen.has(box), "box shown: %s" % box)
	_finish()


# -------------------------------------------------------------
#  THE RUN
# -------------------------------------------------------------

func _play_run(scene: Node) -> void:
	GameSpeed.set_speed(3.0)
	var started := Time.get_ticks_msec()
	while is_instance_valid(scene) and _scene_name().contains("adventure"):
		await create_timer(0.15, true, false, true).timeout
		await _read_boxes(0.0)
		if not is_instance_valid(scene):
			break
		var fight := _find_kind(scene, AdventureEncounter) as AdventureEncounter
		if fight != null and not paused:
			if fight.step == AdventureEncounter.Step.FOCUS:
				for f in fight.foes.size():
					if fight._is_alive(f):
						fight._choose_focus(f)
						break
			elif fight.step == AdventureEncounter.Step.DRAFT:
				var tier: String = fight._current_tier()
				if tier != "":
					var ready_now := fight.run.available_in(tier, fight.db)
					if not ready_now.is_empty():
						fight._pick_card(ready_now[0])
		# The loot popup: the button Koch lit, else onward, else home.
		if not paused:
			for words in ["CLAIM THE BOUNTY", "Continue forward", "Back to the base"]:
				var button := _button_saying(scene, words)
				if button != null and button.is_visible_in_tree():
					await _shot("loot_" + words.left(8))
					button.pressed.emit()
					break
		if float(Time.get_ticks_msec() - started) / 1000.0 > 600.0:
			_check(false, "the run ended")
			break
	GameSpeed.reset()


# -------------------------------------------------------------
#  READING THE BOXES
# -------------------------------------------------------------

## Read every Head Coach / Koch box that comes up, until `until` is the
## scene's name (or no box for `seconds`).
func _read_boxes(seconds: float, until: String = "") -> void:
	var waited := 0.0
	while true:
		var box := _find_kind(root, MatchTalkBox)
		if box != null:
			var line = box.get("_line")
			var scene_name := String(line.scene) if line != null else "?"
			if not _seen.has(scene_name):
				_seen.append(scene_name)
				_where[scene_name] = _scene_name()
				print("[morning] box: %s over %s" % [scene_name, _scene_name()])
				_note_beds(scene_name)
				await _shot(scene_name)
			box.call("_next")
			await create_timer(0.1, true, false, true).timeout
			waited = 0.0
			continue
		if until != "" and _scene_name().contains(until):
			await create_timer(0.6, true, false, true).timeout
			if _find_kind(root, MatchTalkBox) == null:
				return
			continue
		if waited >= seconds:
			return
		await create_timer(0.2, true, false, true).timeout
		waited += 0.2


## Who is in bed when each Dorms box opens.
func _note_beds(scene_name: String) -> void:
	var state := GameState.fetch(self)
	var names: Array[String] = []
	for entry in RecoveryBook.in_the_dorms(CardDatabase.get_db(), state):
		names.append(String(entry["name"]))
	if scene_name == "tut-morning-beds":
		_sleepers_before = names
	elif scene_name == "tut-morning-beds-2":
		_sleepers_after = names
	elif scene_name == "tut-morning-home":
		_played_at_home = int(state.count("adventures_played"))


func _read_story(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await create_timer(0.1, true, false, true).timeout
		waited += 0.1
		if not _scene_name().contains("dialogue"):
			return
		current_scene.call("_finish_typing")
		current_scene.call("_advance")


# -------------------------------------------------------------

func _fresh_save() -> void:
	for file_name in ["story.json", "teams.json"]:
		var path: String = DIR + "/" + file_name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameState.SAVE_PATH = DIR + "/story.json"
	TeamRoster.SAVE_PATH = DIR + "/teams.json"
	GameState.forget(self)
	TeamSelection.clear(self)
	var state := GameState.fetch(self)
	state.set_flag("game_begun")
	state.save_to_disk()


func _shot(shot_name: String) -> void:
	if not _windowed:
		return
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	image.save_png(DIR + "/frames/%02d_%s.png" % [_shots, shot_name])
	_shots += 1


func _check(ok: bool, what: String) -> void:
	_results.append(("PASS  " if ok else "FAIL  ") + what)
	print(("[morning] PASS  " if ok else "[morning] FAIL  ") + what)
	if not ok:
		_failed = true


func _finish() -> void:
	print("")
	for line in _results:
		print("  " + line)
	print("")
	print("[morning] NO TROUBLE." if not _failed else "[morning] SOMETHING FAILED - see above.")
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
	print("[morning] still on '%s' after %.0fs." % [_scene_name(), seconds])
	return ""


func _wait_for_adventure(seconds: float) -> Node:
	var waited := 0.0
	while waited < seconds:
		await create_timer(0.2, true, false, true).timeout
		waited += 0.2
		if current_scene is AdventureScene:
			return current_scene
		# The team screen walks itself through for a squad mode; if it is
		# waiting, press its LOCK IN.
		var lock := _button_saying(root, "LOCK IN")
		if lock != null and lock.is_visible_in_tree() and not lock.disabled:
			lock.pressed.emit()
	print("[morning] still on '%s' after %.0fs." % [_scene_name(), seconds])
	return null


func _button_saying(node: Node, words: String) -> Button:
	if node is Button and String((node as Button).text).to_lower().contains(words.to_lower()):
		return node as Button
	for child in node.get_children():
		var hit := _button_saying(child, words)
		if hit != null:
			return hit
	return null


func _find_kind(node: Node, kind: Variant) -> Node:
	if is_instance_of(node, kind):
		return node
	for child in node.get_children():
		var hit := _find_kind(child, kind)
		if hit != null:
			return hit
	return null
