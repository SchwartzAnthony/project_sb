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
#    3. the first match: IntroSquad.csv - Koch (Tier IV Power 3) and random players, no Stars
#    4. full time -> star-intro in the bar -> back at the base -> the
#       SECOND MATCH starts (intro2): the same players, Koch and the Stars
#    5. full time -> the Brewery opens, the Brewer's scene
#    6. the Brewery window, the Head Coach's boxes, WORK IT lit up
#    7. back at the base: the Adventure banner lit up, the board, the first
#       team only, the run carried home
#    8. straight to the Traveling Merchant, his intro, his beer
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
	var enemy := await _enemy_of(scene)
	_check(enemy["count"] > 0 and enemy["stars"] == 0 and enemy["brewed"] == 0,
		"the opposition is all plain players, no Stars, no brew (%s)" % ", ".join(enemy["names"]))

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
			and picked.active_star.tier == "IV" and picked.active_star.base_power_left == 3,
			"Koch is a Bergmännlein, Tier IV Power 3, and kicks off")
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
	var enemy2 := await _enemy_of(scene)
	_check(enemy2["star_names"].has("Bauer") and enemy2["plain_push"],
		"the opposition has its plain Stars, each giving +1 to the next normal player (%s)" % ", ".join(enemy2["star_names"]))
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
	_check(state.is_unlocked("Brewery"), "after both intro matches the Brewery is open (learn_to_brew)")
	var brewer := await _wait_for_scene("dialogue", 30.0)
	var scene_now := ""
	if brewer != "" and current_scene != null:
		scene_now = String(current_scene.get("scene_name"))
	_check(scene_now == "brewery-intro", "the Brewer's scene plays as the Brewery opens (%s)" % scene_now)
	await _read_story(60.0)
	_check(await _wait_for_scene("base", 20.0) != "", "brewery-intro comes back to the base")

	# ---- 6. the Brewery tour (Guide.csv) ----
	var brewery := await _wait_for_node(BreweryScreen, 10.0)
	_check(brewery != null, "the Brewery window opens by itself after the Brewer's scene")
	var box := await _wait_for_node(MatchTalkBox, 10.0)
	_check(box != null, "the Head Coach's box is over the Brewery")
	await _shot("5_brewery_box")
	await _read_box(box)
	var lit := await _wait_for_highlight(5.0)
	_check(lit != null and lit is Button and (lit as Button).text == "WORK IT",
		"the first WORK IT button is lit up")
	await _shot("6_brewery_lit")
	if lit != null:
		(lit as Button).pressed.emit()
	_check(state.count("res_malt") >= 1, "pressing it brews the first malt (%d)" % state.count("res_malt"))
	box = await _wait_for_node(MatchTalkBox, 10.0)
	_check(box != null, "the Head Coach says you are short and sends you out")
	await _read_box(box)
	await create_timer(1.0, true, false, true).timeout
	_check(state.has_flag("intro_adventure") and _find(current_scene, "BreweryScreen") == null
		and _scene_name().contains("base"), "the Brewery closes and you are at the base")

	# ---- 7. the Adventure, with the first team only ----
	# The "New at the base" list from the Brewer's scene is still up: Continue.
	var news := await _wait_for_node(NewUnlocksPanel, 3.0)
	if news != null:
		news.call("_close")
	box = await _wait_for_node(MatchTalkBox, 10.0)
	_check(box != null, "at the base the Head Coach says: go on an Adventure")
	await _read_box(box)
	lit = await _wait_for_highlight(5.0)
	_check(lit != null, "the Adventure banner is lit up")
	await _shot("7_base_adventure_lit")
	if lit != null:
		(lit as BaseButton).pressed.emit()
	_check(await _wait_for_scene("bounty", 10.0) != "", "it opens the Adventure board")
	var board := current_scene
	var jobs: Array = AdventureDB.get_db().bounties_in(String(board.get("_chosen_biome").get("id", "")), state)
	if not jobs.is_empty():
		board.call("_choose_bounty", jobs[0])
	board.call("_on_start")
	_check(String(MatchMode.current(self).get("id", "")) == "intro_adventure", "it is the first-Adventure mode")
	var run_scene := ""
	for i in 50:
		await create_timer(0.2, true, false, true).timeout
		if _scene_name().contains("adventure"):
			run_scene = _scene_name()
			break
	_check(run_scene != "", "no team to pick: the Adventure starts at once (%s)" % _scene_name())
	var picked_adv := TeamSelection.fetch(self)
	_check(picked_adv != null and _names_of(picked_adv).has("Koch") and _names_of(picked_adv).has("Belial"),
		"the party is your first team")
	if run_scene != "":
		await create_timer(2.0, true, false, true).timeout
		current_scene.call("_go_home", false)   # carry the run home
	_check(state.count("adventures_home") >= 1, "the run is carried home (count:adventures_home)")

	# ---- 8. straight to the Traveling Merchant ----
	var shop := await _wait_for_node(ShopScreen, 20.0)
	_check(shop != null and state.is_unlocked("Traveling Tavern"), "home from the Adventure: the Traveling Merchant's shop opens")
	box = await _wait_for_node(MatchTalkBox, 10.0)
	_check(box != null, "the Traveling Merchant introduces himself")
	await _shot("8_shop_intro")
	await _read_box(box)
	var offers := ShopBook.on_offer(state)
	var beer := 0
	for entry in offers:
		if String(entry.get("sells", "")).contains("brew_"):
			beer += 1
	_check(beer >= 2, "he trades beer for what you carried home (%d beer rows)" % beer)
	await create_timer(1.0, true, false, true).timeout
	_check(_scene_name().contains("base"), "nothing more to do: you are at the base")
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


## Who the opposition put on the pitch.
func _enemy_of(scene: Node) -> Dictionary:
	var out := {"count": 0, "stars": 0, "brewed": 0, "names": [], "star_names": [], "plain_push": true}
	for i in 50:
		await create_timer(0.2, true, false, true).timeout
		if is_instance_valid(scene) and not (scene.call("_all_units") as Array).is_empty():
			break
	if not is_instance_valid(scene):
		return out
	var stars: Array = []
	if scene.get("enemy_star_bundle") != null:
		stars = scene.get("enemy_star_bundle")
	for unit in scene.call("_all_units"):
		if not unit.is_enemy or unit.data == null:
			continue
		out["count"] += 1
		(out["names"] as Array).append(unit.data.player_name)
		if unit.is_star_player:
			out["stars"] += 1
		if unit.data.is_brewed():
			out["brewed"] += 1
	for card in stars:
		(out["star_names"] as Array).append(card.player_name)
		if card.attack_ability_id != "PLAIN_STAR_PUSH":
			out["plain_push"] = false
	return out


func _wait_for_node(kind: Variant, seconds: float) -> Node:
	var waited := 0.0
	while waited < seconds:
		var hit := _find_kind(root, kind)
		if hit != null:
			return hit
		await create_timer(0.2, true, false, true).timeout
		waited += 0.2
	return null


func _find_kind(node: Node, kind: Variant) -> Node:
	if is_instance_of(node, kind):
		return node
	for child in node.get_children():
		var hit := _find_kind(child, kind)
		if hit != null:
			return hit
	return null


func _read_box(box: Node) -> void:
	for i in 40:
		if box == null or not is_instance_valid(box):
			return
		box.call("_next")
		await create_timer(0.1, true, false, true).timeout


func _wait_for_highlight(seconds: float) -> Node:
	var waited := 0.0
	while waited < seconds:
		var ring: Node = _find(root, "GuideHighlight")
		if ring != null:
			return ring.get_parent()
		await create_timer(0.2, true, false, true).timeout
		waited += 0.2
	return null


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
