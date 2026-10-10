extends SceneTree

# =============================================================
#  THE TUTORIAL, PLAYED THROUGH  (round AN)
#
#      godot --headless --path . --script res://tools/tutorial_check.gd
#
#  In saves of its own (user://tutorial_check/), so yours are never touched:
#
#    1. a brand-new save opens the base and asks "do the Tutorial?" - NO:
#       the base gets the starting team (twelve plain players) and nothing
#       is unlocked
#    2. another brand-new save - YES: Pub Dialogue 1 plays, then the
#       tutorial match starts by itself
#    3. the match, on AUTO: every Head Coach stop in MatchTalk.csv must turn
#       up (the kick-off, the Tier I / II / IV cards, the five duel moments,
#       the shot, the exhaust, the TIME OUT in the pub, Koch the Star, the
#       star swap), Koch must be a Star with Beer Courage after the pub, and
#       the score and clock must be the same after the pub as before it
#    4. full time - the base: the same starting team, nothing unlocked
#    5. the main menu's Tutorial button: its own save, and back to yours
#
#  Run it WITHOUT --headless and every stop is also saved as frames in
#  user://tutorial_check/frames/<n>_<scene>/ for the GIFs.
# =============================================================

const DIR := "user://tutorial_check"
const GIVE_UP_SECONDS := 1500.0

const STOPS: Array[String] = ["tut-kickoff", "tut-tier1", "tut-tier2", "tut-tier4",
	"tut-duel-start", "tut-duel-priority", "tut-duel-ability-1", "tut-duel-ability-2",
	"tut-duel-power", "tut-duel-result", "tut-shot", "tut-exhaust",
	"tut-timeout-call", "tut-timeout-inspiration", "tut-koch-ability",
	"tut-referee", "tut-combo", "tut-combo-2",
	"tut-timeout2-call", "tut-timeout-cursed", "tut-koch-earth", "tut-keeper-tip"]

var _results: Array[String] = []
var _failed := false
var _seen: Array[String] = []
var _stop_index := 0
var _keeper_drains := 0
var _windowed := false


func _initialize() -> void:
	seed(20261008)
	_windowed = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/frames"))
	CardDatabase.get_db().tuning[CardDatabase._normalise("choice_window_seconds")] = "0"
	# The match only: "the morning after" (the Dorms and the first Adventure)
	# has its own check, tools/morning_after_check.gd.
	CardDatabase.get_db().tuning[CardDatabase._normalise("tutorial_morning_after")] = "false"
	await process_frame

	# ---- 1. NO ----
	_fresh_save("no")
	change_scene_to_file(ScenePaths.BASE)
	var asked := await _answer_offer(1)
	_check(asked, "a new save asks: do the Tutorial?")
	await create_timer(1.0, true, false, true).timeout
	var state := GameState.fetch(self)
	_check(_scene_name().contains("base"), "NO stays at the base")
	_check(RecruitBook.names(state).size() == 12, "NO: the base has the full starting team (%d)" % RecruitBook.names(state).size())
	_check(state.unlocks.is_empty(), "NO: nothing is unlocked (%s)" % str(state.unlocks))
	await _shot_one("no_base")

	# ---- 2. YES ----
	_fresh_save("yes")
	change_scene_to_file(ScenePaths.BASE)
	asked = await _answer_offer(0)
	_check(asked, "the second new save asks too")
	var story := await _wait_for_scene("dialogue", 20.0)
	_check(story != "", "YES: Pub Dialogue 1 plays")
	_check(Tutorial.active(self), "the tutorial is running")
	_check(GameState.SAVE_PATH == Tutorial.SEALED_SAVE, "YES: the tutorial plays in a save of its own")
	var tutorial_names: Array[String] = []
	await create_timer(1.0, true, false, true).timeout
	await _shot_one("prologue")
	await _read_story(90.0)
	var scene := await _wait_for_match(40.0)
	_check(scene != null, "after the pub, the tutorial match opens by itself")
	if scene == null:
		_finish()
		return
	_check(String(MatchMode.current(self).get("id", "")) == "tutorial", "it is the tutorial match")
	var picked := TeamSelection.fetch(self)
	_check(picked != null and picked.active_star != null and picked.active_star.player_name == "Koch"
		and picked.active_star.is_star() and picked.active_star.unit_type == "Normal",
		"Koch starts as a plain Star (no transformation in the pub)")

	# ---- 3. the match ----
	tutorial_names = RecruitBook.names(GameState.fetch(self))
	await _play(scene)
	for stop in STOPS:
		_check(_seen.has(stop), "the coach stopped: %s" % stop)
	_check(int(_keeper_drains) > 0, "Koch's Earth Courage opened the keeper's window (%d times)" % int(_keeper_drains))

	# ---- 4. the base ----
	await _wait_for_scene("base", 30.0)
	_check(_scene_name().contains("base"), "full time: the tutorial ends at the base")
	_check(not Tutorial.active(self), "the tutorial is over")
	state = GameState.fetch(self)
	_check(RecruitBook.names(state).size() == 12, "the base has the full starting team (%d)" % RecruitBook.names(state).size())
	_check(state.unlocks.is_empty(), "nothing is unlocked (%s)" % str(state.unlocks))
	# NOTHING FROM THE TUTORIAL REACHES YOUR GAME (Anthony, 8 Oct).
	_check(GameState.SAVE_PATH == DIR + "/story_yes.json", "your own save is back")
	_check(not FileAccess.file_exists(Tutorial.SEALED_SAVE), "the tutorial's save is thrown away")
	var leaked: Array[String] = []
	for key in state.flags.keys():
		if String(key).contains("tutorial") or String(key).begins_with("matchtalkdone") \
				or String(key).begins_with("match_talk_done"):
			leaked.append(String(key))
	_check(leaked.is_empty(), "no tutorial flags in your save (%s)" % str(leaked))
	var same := 0
	for name_text in RecruitBook.names(state):
		if tutorial_names.has(name_text):
			same += 1
	# The starting team is made fresh in your save, so a shared name can only
	# be chance (Names.csv is long, so it is nearly always 0).
	_check(same <= 2, "the tutorial's players did not come with you (%d names shared)" % same)
	_check(int(state.count("matches_played")) == 0, "the tutorial match is not counted (%d)" % int(state.count("matches_played")))
	await _shot_one("end_base")

	# ---- 5. from the main menu ----
	var real := GameState.SAVE_PATH
	Tutorial.start(self, true)
	_check(GameState.SAVE_PATH == Tutorial.SEALED_SAVE, "the menu's Tutorial plays in a save of its own")
	await _wait_for_scene("dialogue", 20.0)
	Tutorial.finish(self)
	_check(GameState.SAVE_PATH == real, "and gives your own save back")
	_check(await _wait_for_scene("main_menu", 20.0) != "", "and comes back to the title screen")
	_finish()


func _fresh_save(tag: String) -> void:
	for file_name in ["story_%s.json" % tag, "teams_%s.json" % tag]:
		var path: String = DIR + "/" + file_name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameState.SAVE_PATH = DIR + "/story_%s.json" % tag
	TeamRoster.SAVE_PATH = DIR + "/teams_%s.json" % tag
	GameState.forget(self)
	TeamSelection.clear(self)


func _answer_offer(index: int) -> bool:
	var window := await _wait_for_node(ChoiceWindow, 15.0)
	if window == null:
		return false
	await create_timer(0.6, true, false, true).timeout
	await _shot_one("offer")
	window.emit_signal("chosen", index)
	return true


# -------------------------------------------------------------
#  PLAYING THE MATCH
# -------------------------------------------------------------

func _play(scene: Node) -> void:
	for i in 300:
		await create_timer(0.2, true, false, true).timeout
		if not is_instance_valid(scene):
			return
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
	# Picked like a player would - AUTO draws the cards faded. The other
	# questions (the throw-in, a reveal) answer themselves after a second
	# (choice_window_seconds).
	CardDatabase.get_db().tuning[CardDatabase._normalise("choice_window_seconds")] = "1"
	var state = scene.get("state")
	MatchHUD.set_auto_pick(state, false)
	scene.call("_on_auto_pick_changed", false)
	GameSpeed.set_speed(3.0)
	var dealt_at := -1
	var started := Time.get_ticks_msec()
	while is_instance_valid(scene):
		await create_timer(0.1, true, false, true).timeout
		if not is_instance_valid(scene):
			break
		var box = scene.get("_talk_box")
		if box != null and is_instance_valid(box):
			await _read_coach(scene, box)
		var timeout_layer := scene.get_node_or_null("TimeOut")
		if timeout_layer != null:
			await _read_time_out(scene, timeout_layer)
		if not is_instance_valid(scene):
			break
		# The throw-in question and the old coin answer themselves.
		var throw := _find_kind(scene, ThrowInView)
		if throw != null and not throw.has_meta("answered"):
			throw.set_meta("answered", true)
			throw.call("auto_play", 0.3, 0.5)
		var clash = scene.get("rps")
		if clash != null and clash.is_running() and not clash.has_meta("answered"):
			clash.set_meta("answered", true)
			clash.call("auto_play", 0.3, 0.5)
		elif clash != null and not clash.is_running() and clash.has_meta("answered"):
			clash.remove_meta("answered")
		var brewery := scene.get_node_or_null("BreweryTimeOut")
		if brewery != null and not brewery.has_meta("done"):
			# The Brewery thread's tour is checked by its own tools; here we
			# only see that the TIME OUT opens it and that it hands back.
			brewery.set_meta("done", true)
			_check(true, "cycle 2, Play Maker 5: the missing beer sends us to the Brewery")
			await create_timer(1.0, true, false, true).timeout
			await _shot_one("brewery_time_out")
			for child in brewery.get_children():
				if child.has_method("leave"):
					child.call("leave")
			continue
		var shot_view = scene.get("shootout")
		if shot_view != null and bool(shot_view.get("draining")):
			if int(shot_view.get("drains_shown")) > _keeper_drains:
				_keeper_drains = int(shot_view.get("drains_shown"))
				if _keeper_drains == 1:
					await create_timer(0.3, true, false, true).timeout
					await _shot_one("keeper_drain_before")
					await create_timer(0.9, true, false, true).timeout
					await _shot_one("keeper_drain_stamina")
					await create_timer(0.9, true, false, true).timeout
					await _shot_one("keeper_drain_chance")
			continue
		var lesson := scene.get_node_or_null("DrinkLessonGold")
		if lesson != null and not lesson.has_meta("done"):
			lesson.set_meta("done", true)
			await _drink_lesson(scene)
			continue
		var offered: Array = scene.get("offered_cards")
		if offered.is_empty() or paused:
			dealt_at = -1
		elif dealt_at < 0:
			dealt_at = Time.get_ticks_msec()
			if not _tried_fast_click:
				# Anthony, 8 Oct: clicking fast must not skip a pick.
				_tried_fast_click = true
				var first_card = scene.call("_best_offered_card")
				var before := offered.size()
				scene.call("_on_card_selected", first_card)
				_check((scene.get("offered_cards") as Array).size() == before,
					"a card clicked the moment it is dealt is not taken (the pick guard)")
		elif Time.get_ticks_msec() - dealt_at > 1500:
			dealt_at = -1
			var best = _pickable_card(scene)
			if best != null:
				scene.call("_on_card_selected", best)
		if int(scene.get("current_state")) == 4:
			print("[tutorial] FULL TIME %d-%d" % [int(scene.get("player_score")), int(scene.get("enemy_score"))])
			break
		if float(Time.get_ticks_msec() - started) / 1000.0 > GIVE_UP_SECONDS:
			_check(false, "the match reached full time")
			break
	GameSpeed.reset()


func _read_coach(scene: Node, box: Node) -> void:
	var line = box.get("_line")
	var scene_name := String(line.scene) if line != null else "?"
	if not _seen.has(scene_name):
		_seen.append(scene_name)
	print("[tutorial] the coach stops: %s" % scene_name)
	var folder := "%02d_%s" % [_stop_index, scene_name]
	_stop_index += 1
	var frame := 0
	while is_instance_valid(box):
		# A few frames of every line, so the gold pulses in the GIF.
		for i in 8:
			await _frame(folder, frame)
			frame += 1
			await create_timer(0.12, true, false, true).timeout
		if not is_instance_valid(box):
			break
		box.call("_next")
		await create_timer(0.05, true, false, true).timeout
	if scene_name in ["tut-timeout-call", "tut-timeout2-call"]:
		_before_pub = [int(scene.get("player_score")), int(scene.get("enemy_score")),
			String(scene.get("timer_label").text)]


var _before_pub: Array = []


var _time_outs := 0
var _tried_fast_click := false
var _lessons := 0


func _read_time_out(scene: Node, layer: Node) -> void:
	_time_outs += 1
	var pub_scene := "tut-timeout-inspiration" if _time_outs == 1 else "tut-timeout-cursed"
	_seen.append(pub_scene)
	var folder := "%02d_%s" % [_stop_index, pub_scene]
	_stop_index += 1
	var frame := 0
	var view: Node = null
	for i in 20:
		view = _find_kind(layer, DialogueView)
		if view != null:
			break
		await create_timer(0.1, true, false, true).timeout
	while is_instance_valid(layer) and view != null and is_instance_valid(view):
		for i in 8:
			await _frame(folder, frame)
			frame += 1
			await create_timer(0.12, true, false, true).timeout
		if not is_instance_valid(view):
			break
		view.call("_finish_typing")
		view.call("_advance")
		await create_timer(0.3, true, false, true).timeout
	await create_timer(0.5, true, false, true).timeout
	var after := [int(scene.get("player_score")), int(scene.get("enemy_score")),
		String(scene.get("timer_label").text)]
	_check(_before_pub.is_empty() or after == _before_pub,
		"back from the pub, the match is where it was (%s -> %s)" % [str(_before_pub), str(after)])
	var koch: PlayerUnit = null
	for unit in scene.call("_everyone_ever"):
		if not unit.is_enemy and unit.data != null and unit.data.player_name == "Koch":
			koch = unit
	if _time_outs == 1:
		_check(koch != null and koch.is_star_player and koch.data.is_star()
			and koch.data.attack_ability_id == "TUT_KOCH_BEER"
			and koch.data.unit_type == "Normal",
			"after the first TIME OUT Koch is still a plain Star, now with Beer Courage")
	else:
		_check(koch != null and koch.is_star_player
			and koch.data.attack_ability_id == "TUT_KOCH_EARTH"
			and koch.data.defend_ability_id == "TUT_KOCH_EARTH_DEF"
			and koch.data.unit_type == "Bergmännlein",
			"after the second TIME OUT Koch is a Bergmännlein with Earth Courage")
	await _shot_one("after_time_out_%d" % _time_outs)


# -------------------------------------------------------------

func _frame(folder: String, index: int) -> void:
	if not _windowed:
		return
	await process_frame
	var dir := DIR + "/frames/" + folder
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var image := root.get_texture().get_image()
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	image.save_png(dir + "/f_%03d.png" % index)


func _shot_one(shot_name: String) -> void:
	if not _windowed:
		return
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	image.save_png(DIR + "/frames/shot_%s.png" % shot_name)


func _check(ok: bool, what: String) -> void:
	_results.append(("PASS  " if ok else "FAIL  ") + what)
	print(("[tutorial] PASS  " if ok else "[tutorial] FAIL  ") + what)
	if not ok:
		_failed = true


func _finish() -> void:
	print("")
	for line in _results:
		print("  " + line)
	print("")
	print("[tutorial] NO TROUBLE." if not _failed else "[tutorial] SOMETHING FAILED - see above.")
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


func _read_story(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await create_timer(0.1, true, false, true).timeout
		waited += 0.1
		if not _scene_name().contains("dialogue"):
			return
		var view := current_scene
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
	print("[tutorial] still on '%s' after %.0fs." % [_scene_name(), seconds])
	return null


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


func _find(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var hit := _find(child, wanted)
		if hit != null:
			return hit
	return null


## The best card a player could actually click: the AI's choice when it is
## not locked, else the first unlocked one (the drinking lesson locks all
## but one).
func _pickable_card(scene: Node) -> PlayerData:
	var best = scene.call("_best_offered_card")
	var open: Array = []
	for child in (scene.get("card_container") as Node).get_children():
		var card := child as PlayerCardUI
		if card != null and not card.locked and card.current_data != null:
			open.append(card.current_data)
	if open.has(best) or open.is_empty():
		return best
	return open[0]


## THE KLEINER FASS (cycle 2, Play Maker 4): open the bag on the 0 Power,
## check it holds only the Kleiner Faß, use it, and check what it did.
func _drink_lesson(scene: Node) -> void:
	var first: PlayerCardUI = null
	var locked_others := true
	for child in (scene.get("card_container") as Node).get_children():
		var card := child as PlayerCardUI
		if card == null:
			continue
		if first == null:
			first = card
		elif not card.locked:
			locked_others = false
	if _lessons < 2:
		_check(first != null and first.current_data.get_attack_power() == _lessons,
			"drinking lesson %d is on the Tier I Power %d" % [_lessons + 1, _lessons])
	else:
		_check(first != null and first.current_data.get_tier_clean() == ("I" if _lessons == 2 else "II"),
			"combo lesson %d is on the Tier %s" % [_lessons - 1, "I" if _lessons == 2 else "II"])
	_check(locked_others, "during the lesson only his bag button can be clicked")
	_check(first != null and not first.bag_shut, "his bag button is not greyed")
	await create_timer(0.8, true, false, true).timeout
	scene.call("_on_brew_wanted", first.current_data)
	await create_timer(0.4, true, false, true).timeout
	var bag := scene.get_node_or_null("InventoryScreen") as InventoryScreen
	var shown := 0
	if bag != null:
		for tile in bag.get("_grid").get_children():
			if not tile.is_queued_for_deletion():
				shown += 1
	var wanted: String = ["keg", "small_bottle", "anstoss_helles", "doppelpass_weisse"][mini(_lessons, 3)]
	var should_show: int = [1, 1, 3, 2][mini(_lessons, 3)]
	_check(bag != null and shown == should_show and bag.tile_for(wanted) != null,
		"the bag shows %d item(s), the %s among them" % [should_show, wanted])
	await _shot_one("drink_lesson_bag_%d" % _lessons)
	var item_id := wanted
	_lessons += 1
	scene.call("_use_on_card", first.current_data, AdventureDB.get_db().item(item_id))
	if bag != null and is_instance_valid(bag):
		bag.close()
	await create_timer(1.2, true, false, true).timeout
	await _shot_one("drink_window_%d" % _lessons)
	await create_timer(1.6, true, false, true).timeout
	await _shot_one("drink_window_burp_%d" % _lessons)
	_check(first.bag_shut, "after he has drunk, his bag is greyed like the rest")
	if _lessons == 1:
		_check(first.current_data.active_attack_ability() == "TUT_FASS_COURAGE"
			and first.current_data.active_defend_ability() == "TUT_FASS_COURAGE",
			"after the Kleiner Faß the 0 Power has Fass Courage on both sides")
	elif _lessons == 3:
		_check(first.current_data.active_attack_ability() == "COMBO_HELLES_ATK"
			and first.current_data.active_defend_ability() == "COMBO_HELLES_DEF",
			"after the Anstoß Helles the Tier I has Pass It On and Heavy Legs")
	elif _lessons == 4:
		_check(first.current_data.active_attack_ability() == "COMBO_WEISSE_ATK"
			and first.current_data.active_defend_ability() == "COMBO_WEISSE_DEF",
			"after the Doppelpass Weiße the Tier II has Fumbled Pass and One-Two")
	else:
		_check(first.current_data.active_attack_ability() == "PLAIN_GOALIE_ATK"
			and first.current_data.active_defend_ability() == "PLAIN_GOALIE_DEF",
			"after the bottle the Power 1 has the plain beer's goalie pair (hit or miss)")
