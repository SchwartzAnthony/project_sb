extends SceneTree

# =============================================================
#  A PICTURE OF THE DORMS AND THE CLUB HOUSE  (round AN)
#
#      godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/dorms_shot.gd
#
#  Runs inside the TEST ENVIRONMENT, so your real save is never touched.
#  Puts a few players in bed (one from a match, one from an Adventure, one
#  carried home, one sleeping off a brew), earns two achievements, and opens
#  both rooms as windows over the base. Writes dorms.png and clubhouse.png
#  into the user:// folder.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	var db := CardDatabase.get_db()
	var state := GameState.fetch(self)
	db.tuning["recovery"] = "true"
	for entry in BaseDB.get_db().buildings.duplicate():
		for term in String(entry["requires"]).split(";", false):
			var clean := String(term).strip_edges()
			if clean.to_lower().begins_with("unlocked:"):
				state.unlock(clean.substr(clean.find(":") + 1).strip_edges())
	state.set_count("coins", 420)

	var cards: Array = db.players.filter(func(c: PlayerData) -> bool: return not c.is_star())
	RecoveryBook.after_match([cards[0], cards[1]], state, db)
	state.set_text(BrewDB.TEMP_PREFIX + BrewDB.card_key(cards[2]), "fire_brew")
	RecoveryBook.after_match([cards[2]], state, db)
	BrewDB.clear_temporary(state)
	RecoveryBook.after_adventure([cards[3], cards[4], cards[5]], [cards[5]], state, db)

	# ALL THREE STATES ON THE SHELF: two still locked, one already bought.
	state.set_flag(AchievementBook.EARNED_PREFIX + "third_vat", false)
	state.set_flag(AchievementBook.EARNED_PREFIX + "goal_machine", false)
	state.set_count("matches_won", 0)
	state.set_count("goals", 0)
	state.set_flag(AchievementBook.EARNED_PREFIX + "second_vat", true)
	state.set_count("coins", 900)
	BaseRooms.buy_upgrade("second_vat", state)

	# NO STORY TONIGHT: mark every Progression row done, or the base hands
	# the screen to a dialogue before the picture is taken.
	for row in MenuSupport.read_csv("res://data/Progression.csv"):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text != "":
			state.set_flag(Progression.DONE_PREFIX + id_text.to_lower(), true)
	state.set_flag("game_begun")
	change_scene_to_file("res://src/ui/base_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	var base := current_scene
	for child in base.get_children():
		if child is NewUnlocksPanel:
			child.queue_free()

	for room in ["dorms", "clubhouse"]:
		var window := BaseWindow.open(base, base._window_title(room), ScenePaths.for_name(room))
		for i in 12:
			await process_frame
		await create_timer(0.7, true, false, true).timeout
		root.get_viewport().get_texture().get_image().save_png("user://%s.png" % room)
		print("[shot] user://%s.png" % room)
		window.close()
		await create_timer(0.3, true, false, true).timeout

	print("[shot] pictures in %s" % ProjectSettings.globalize_path("user://"))
	TestEnvironment.leave(self)
	quit(0)
