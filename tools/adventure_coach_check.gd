extends SceneTree

# =============================================================
#  THE ADVENTURE'S ESCAPE MENU AND THE HEAD COACH'S STOPS  (round AN)
#
#      godot --headless --path . --script res://tools/adventure_coach_check.gd
#
#  An ordinary Adventure (Mode adventure) in a save of its own
#  (user://coach_check/), through the real scene:
#
#    1. Escape stops the run: the menu has Continue, Exit to Base, Main Menu,
#       Settings and Quit, the game is paused under it, Continue carries on
#    2. Settings opens over the run, Escape closes it, the menu comes back
#    3. the run is played: every Head Coach box (MatchTalk.csv coach_adv_*)
#       that comes up is read and listed
#    4. Escape > Exit to Base leaves the run and lands at the base, unpaused
#
#  Run it WITHOUT --headless and every box is saved as a picture in
#  user://coach_check/frames/.
# =============================================================

const DIR := "user://coach_check"

## The boxes any run should show. The rest depend on how the fight goes.
const MUST_SEE: Array[String] = ["coach-adv-start", "coach-adv-wave",
	"coach-adv-focus", "coach-adv-draft", "coach-adv-hit",
	"coach-adv-enemy-turn"]

var _results: Array[String] = []
var _failed := false
var _seen: Array[String] = []
var _windowed := false
var _shots := 0


func _initialize() -> void:
	seed(20261010)
	_windowed = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/frames"))
	var db := CardDatabase.get_db()
	db.tuning[CardDatabase._normalise("match_talk_line_seconds")] = "0"
	await process_frame

	_fresh_save()
	_pick_a_real_team()
	MatchMode.choose(self, "adventure")
	change_scene_to_file("res://src/adventure/adventure_scene.tscn")
	var scene := await _wait_for_adventure(10.0)
	_check(scene != null, "the Adventure opens")
	if scene == null:
		_finish()
		return

	# ---- 1. the Escape menu over the Head Coach's first box ----
	await create_timer(0.6, true, false, true).timeout
	var first := _find_kind(root, MatchTalkBox)
	_check(first != null, "the Head Coach stops the run as it sets off")
	_escape()
	await process_frame
	var menu := _find_kind(scene, MenuEscape) as MenuEscape
	_check(menu != null and menu._panel.visible, "Escape opens the menu")
	_check(paused, "the run is paused under the menu")
	for words in ["Continue", "Exit to Base", "Main Menu", "Settings", "Quit to Desktop"]:
		var button := _button_saying(menu, words)
		_check(button != null and button.is_visible_in_tree(), "the menu has %s" % words)
	await _shot("esc_menu")

	# ---- 2. Settings over the run ----
	_button_saying(menu, "Settings").pressed.emit()
	await process_frame
	await process_frame
	var settings := _find_kind(root, SettingsScreen)
	_check(settings != null and is_instance_valid(settings), "Settings opens over the run")
	_check(current_scene == scene, "the run is still there underneath")
	await _shot("esc_settings")
	_escape()
	await process_frame
	await process_frame
	_check(_find_kind(root, SettingsScreen) == null, "Escape closes Settings")
	_check(menu._panel.visible, "and the menu comes back")
	_button_saying(menu, "Continue").pressed.emit()
	await process_frame
	_check(not menu._panel.visible, "Continue closes the menu")
	_check(paused, "the Head Coach's box still holds the run")

	# ---- 3. the run, every box read ----
	await _play_run(scene, 3)
	print("[coach] boxes seen: %s" % ", ".join(_seen))
	for scene_name in MUST_SEE:
		_check(_seen.has(scene_name), "the Head Coach explains %s" % scene_name)
	_check(not _seen.has("tut-adv-start"), "Koch's tutorial stops stay in the tutorial")

	# ---- 4. Exit to Base ----
	if current_scene is AdventureScene:
		var state := GameState.fetch(self)
		var played := int(state.count("adventures_played"))
		_escape()
		await process_frame
		menu = _find_kind(current_scene, MenuEscape) as MenuEscape
		_button_saying(menu, "Exit to Base").pressed.emit()
		var landed := await _wait_for_scene("base", 10.0)
		_check(landed != "", "Exit to Base lands at the base")
		_check(not paused, "nothing is left paused")
		_check(int(state.count("adventures_played")) == played + 1,
			"leaving counts as a run played (the party goes to bed)")
	else:
		_check(false, "the run was still going for Exit to Base")

	# ---- 5. a second run: the boxes are first-time only ----
	_seen.clear()
	MatchMode.choose(self, "adventure")
	change_scene_to_file("res://src/adventure/adventure_scene.tscn")
	scene = await _wait_for_adventure(10.0)
	if scene != null:
		await _play_run(scene, 1)
		_check(not _seen.has("coach-adv-start") and not _seen.has("coach-adv-focus"),
			"a second run is not explained again")
		_escape()
		await process_frame
		menu = _find_kind(current_scene, MenuEscape) as MenuEscape
		_button_saying(menu, "Main Menu").pressed.emit()
		var at_title := await _wait_for_scene("main_menu", 10.0)
		_check(at_title != "", "Main Menu leaves the run for the title screen")
		_check(not paused, "nothing is left paused there either")
	_finish()


# -------------------------------------------------------------

## Play until `waves` waves have been cleared (or the run ends), reading
## every box that comes up. Stops on a loot popup without pressing it.
func _play_run(scene: Node, waves: int) -> void:
	GameSpeed.set_speed(3.0)
	var started := Time.get_ticks_msec()
	var cleared := 0
	while is_instance_valid(scene) and current_scene == scene:
		await create_timer(0.15, true, false, true).timeout
		await _read_boxes()
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
		if not paused:
			var onward := _button_saying(scene, "Continue forward")
			if onward != null and onward.is_visible_in_tree():
				cleared += 1
				await _read_boxes()
				if cleared >= waves:
					break
				onward.pressed.emit()
			var fell := _button_saying(scene, "Back to the base")
			if fell != null and fell.is_visible_in_tree():
				await _read_boxes()
				break
			var claim := _button_saying(scene, "CLAIM THE BOUNTY")
			if claim != null and claim.is_visible_in_tree():
				await _read_boxes()
				break
		if float(Time.get_ticks_msec() - started) / 1000.0 > 300.0:
			_check(false, "the run moved on")
			break
	GameSpeed.reset()


func _read_boxes() -> void:
	while true:
		var box := _find_kind(root, MatchTalkBox)
		if box == null:
			return
		var line = box.get("_line")
		var scene_name := String(line.scene) if line != null else "?"
		if not _seen.has(scene_name):
			_seen.append(scene_name)
			print("[coach] box: %s" % scene_name)
			await _shot(scene_name)
		box.call("_next")
		await create_timer(0.1, true, false, true).timeout


func _escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	var up := key.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


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


## A real team, the way the team builder hands one over (as adventure_shot.gd).
func _pick_a_real_team() -> void:
	var db := CardDatabase.get_db()
	var wanted := ""
	for card in db.players:
		if card.unit_type.strip_edges().to_lower() == "lorelei":
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
		var made := TierLadder.build(roster, tier, db, false)
		picked.regulars[tier] = made["cards"]
	TeamSelection.store(self, picked)


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
	print(("[coach] PASS  " if ok else "[coach] FAIL  ") + what)
	if not ok:
		_failed = true


func _finish() -> void:
	print("")
	for line in _results:
		print("  " + line)
	print("")
	print("[coach] NO TROUBLE." if not _failed else "[coach] SOMETHING FAILED - see above.")
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
	print("[coach] still on '%s' after %.0fs." % [_scene_name(), seconds])
	return ""


func _wait_for_adventure(seconds: float) -> Node:
	var waited := 0.0
	while waited < seconds:
		await create_timer(0.2, true, false, true).timeout
		waited += 0.2
		if current_scene is AdventureScene:
			return current_scene
	return null


func _button_saying(node: Node, words: String) -> Button:
	if node == null:
		return null
	if node is Button and (String((node as Button).text).to_lower().contains(words.to_lower())
			or _label_says(node, words)):
		return node as Button
	for child in node.get_children():
		var hit := _button_saying(child, words)
		if hit != null:
			return hit
	return null


## An icon button keeps its words in a Label inside it.
func _label_says(node: Node, words: String) -> bool:
	for child in node.get_children():
		if child is Label and String((child as Label).text).to_lower().contains(words.to_lower()):
			return true
		if _label_says(child, words):
			return true
	return false


func _find_kind(node: Node, kind: Variant) -> Node:
	if is_instance_of(node, kind):
		return node
	for child in node.get_children():
		var hit := _find_kind(child, kind)
		if hit != null:
			return hit
	return null
