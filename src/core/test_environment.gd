class_name TestEnvironment
extends RefCounted

# =============================================================
#  THE TEST COMPLETE ENVIRONMENT  (round AC)
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "A 'Test Complete Environment' button for me on the base in the Dev
#   button ... a complete unlock feature, and all teams listed and ready to
#   play, and everything unlocked so that I can create the teams on the fly
#   ... please do make a distinction between the two."
#
#  ============ THE DISTINCTION: IT IS A DIFFERENT SAVE ============
#
#  The test environment never touches your real save. It lives in its OWN
#  folder:
#
#      user://test_environment/story_state.json
#      user://test_environment/teams.json
#
#  and while you are in it an ORANGE STRIP across the top of every screen
#  says TEST ENVIRONMENT. Leave it (the Dev screen, "Back to my real save")
#  and you are exactly where you were; your real save was never opened.
#
#  ============ WHAT "COMPLETE" MEANS ============
#
#  Every time you press the button the test save is rebuilt from nothing:
#
#    - every unlock, talent, building, brew and achievement satisfied
#      (the same "jump straight to" the Dev screen does, for all of them);
#    - every card in every CSV signed to your squad;
#    - `test_env_coins` coins (Tuning.csv) and as many talent points;
#    - every Star Hall node filled with its own Star;
#    - every class offered on the new-team screen, even ones whose Requires
#      is not met or that are Hidden in ClassInfo.csv;
#    - ONE READY TEAM PER CLASS, built the way AUTO builds one (the Star and
#      the strongest card per Tier), named "TEST · <class>", so you can pick
#      any class and play straight away - or build your own next to them.
#
#  Fixtures (the season's matches) are left alone: playing them is the test.
# =============================================================

const FOLDER := "user://test_environment"
const STATE_PATH := FOLDER + "/story_state.json"
const TEAMS_PATH := FOLDER + "/teams.json"
const META := "cw_test_environment"


## Are we in it right now?
static func active(tree: SceneTree) -> bool:
	return tree != null and tree.has_meta(META) and bool(tree.get_meta(META))


## Press the button: build a fresh complete save and switch to it.
## Returns a few lines saying what it did.
static func enter(tree: SceneTree) -> Array[String]:
	var said: Array[String] = []
	if tree == null:
		return said
	var db := CardDatabase.get_db()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	# Start from nothing every time, so the test save never drifts.
	for path in [STATE_PATH, TEAMS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	tree.set_meta(META, true)
	GameState.SAVE_PATH = STATE_PATH
	TeamRoster.SAVE_PATH = TEAMS_PATH
	GameState.forget(tree)
	TeamSelection.clear(tree)
	ScenePaths.clear_trail(tree)

	var state := GameState.fetch(tree)
	state.reset()

	# 1. Everything with a requirement, satisfied. A few passes, because
	#    satisfying one thing (the Brewery) is what another (the Pub) needs.
	var granted := 0
	for _pass in 6:
		var progress := UnlockProgress.build(state)
		var changed_any := false
		for entry in progress.entries:
			if bool(entry.get("done", false)) or String(entry.get("kind", "")) == "Fixture":
				continue
			var changed := UnlockProgress.satisfy(entry, state)
			if not changed.is_empty():
				changed_any = true
			# And the thing itself (an achievement's "earned" flag, an
			# unlock), in case its own condition was odd.
			var truth := String(entry.get("done_test", ""))
			if truth != "":
				var own := {"parts": UnlockProgress.progress_of(truth, state)["parts"],
					"kind": "", "name": entry.get("name", ""), "key": entry.get("key", "")}
				if not UnlockProgress.satisfy(own, state).is_empty():
					changed_any = true
			granted += 1
		if not changed_any:
			break
	said.append("%d unlock(s), talent(s), building(s) and achievement(s) granted" % granted)
	# Satisfying "count:season_match>=11" moved the SEASON on. The season is
	# the one thing left for you to play, so it goes back to match 1.
	state.set_count(SeasonDB.MATCH, 1)

	# 2. Every card.
	said.append(DevMode.own_everything(state, db))

	# 2b. ROUND AN: EVERY KEY. A building or a Brewery machine opens only with
	#     its key (bought at the Club House), and "everything unlocked" means
	#     every door too.
	var keys := 0
	for entry in BaseRooms.upgrades():
		if String(entry["kind"]) == "key" and state.count(String(entry["id"])) <= 0:
			state.set_count(String(entry["id"]), 1)
			keys += 1
	said.append("%d key(s) in the bag" % keys)

	# 3. Money.
	var coins := db.tune_int("test_env_coins", 99999)
	state.set_count("coins", coins)
	said.append("%d coins" % coins)

	# 4. Every Star Hall node filled with its own Star (a match needs them).
	state.set_count(ClassTree.POINTS, maxi(state.count(ClassTree.POINTS), 99999))
	var placed := 0
	var hall := db.stars_by_class()
	for key in hall:
		var unit_type := String(key)
		for node in ClassTree.nodes_for(unit_type, state):
			if bool(node["filled"]):
				continue
			for star in hall[key]:
				var result := ClassTree.place_star(unit_type, String(node["set_id"]), star as PlayerData, state, db)
				if bool(result["ok"]):
					placed += 1
					break
	said.append("%d Star(s) placed in the Star Hall" % placed)

	# 5. One ready team per class.
	var roster := TeamRoster.load_all()
	var made := 0
	var by_class := db.stars_by_class()
	var names: Array = by_class.keys()
	names.sort()
	for key in names:
		var unit_type := String(key)
		var stars: Array = by_class[key]
		if stars.is_empty():
			continue
		var star_tier := db.star_tier_for_class(unit_type)
		var entry := TeamRoster.blank(unit_type, star_tier)
		entry["id"] = "test_%s" % CardDatabase._normalise(unit_type)
		entry["name"] = "TEST · %s" % unit_type
		var pool := db.roster_for_class(unit_type)
		var chosen: Dictionary = {}
		for tier in TierLadder.TIERS:
			if tier == star_tier:
				continue
			chosen[tier] = TierLadder.build(pool, tier, db, false)["cards"]
		TeamRoster.set_cards(entry, chosen)
		roster.put(entry)
		made += 1
	roster.save()
	said.append("%d ready team(s), one per class" % made)

	state.save_to_disk()
	for line in said:
		print("[test environment] %s" % line)
	print("[test environment] Saved in %s - your real save was not touched."
		% ProjectSettings.globalize_path(FOLDER))
	return said


## Leave it. Back to the slot you were playing; nothing of the test save
## follows you.
static func leave(tree: SceneTree) -> void:
	if tree == null:
		return
	tree.set_meta(META, false)
	SaveSlots.choose(tree, SaveSlots.current(tree))
	print("[test environment] Left. Back on your real save.")


## The orange strip. MenuEscape.install() calls this on every screen, so a
## screen added later gets it for free.
static func put_banner(on: Node) -> void:
	if on == null or not active(on.get_tree()):
		return
	if on.get_node_or_null("TestEnvironmentBanner") != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "TestEnvironmentBanner"
	layer.layer = 190
	var strip := Label.new()
	strip.text = "TEST ENVIRONMENT  ·  everything unlocked  ·  not your real save  (Dev > Back to my real save)"
	strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = 22.0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_font_size_override("font_size", 14)
	strip.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02))
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.98, 0.58, 0.16, 0.92)
	strip.add_theme_stylebox_override("normal", back)
	layer.add_child(strip)
	on.add_child(layer)
