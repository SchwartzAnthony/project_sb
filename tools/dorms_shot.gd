extends SceneTree

# =============================================================
#  A PICTURE OF THE DORMS, THE CLUB HOUSE, THE TRAINING GROUND, THE BREWERY
#  AND THE DEV SCREEN'S PLAYERS ROW  (round AN)
#
#      godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/dorms_shot.gd
#
#  Runs inside the TEST ENVIRONMENT, so your real save is never touched.
#  Puts a few players in bed (back from a match, from an Adventure, carried
#  home, a brewer after his shift), trains two recruits as brewers, leaves
#  some keys unbought, and opens the rooms as windows over the base. Writes
#  dorms.png, clubhouse.png, training.png, brewery.png and dev_players.png
#  into the user:// folder.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	var db := CardDatabase.get_db()
	var state := GameState.fetch(self)
	db.tuning["recovery"] = "true"
	state.set_count("coins", 900)

	# ---- in bed ----
	var cards: Array = db.players.filter(func(c: PlayerData) -> bool: return not c.is_star())
	RecoveryBook.after_match([cards[0], cards[1]], state, db)
	RecoveryBook.after_adventure([cards[3], cards[4], cards[5]], [cards[5]], state, db)

	# ---- two brewers and a recruit who could be one ----
	for who in [["Johanna", "I", 0, "f"], ["Sepp", "III", 3, "m"], ["Vroni", "II", 2, "f"]]:
		RecruitBook.enlist(String(who[0]), String(who[1]), int(who[2]), String(who[3]), state, "", "new")
	BaseRooms.train_brewer("Johanna", state)
	BaseRooms.train_brewer("Sepp", state)
	for id_text in (BreweryBook.section("malthouse")["takes"] as Dictionary).keys():
		BreweryBook.add_stock(String(id_text), 5, state)
	BrewerBook.work("malthouse", state, db, 1)

	# ---- the shelf: some keys and upgrades still to buy, one locked ----
	for key_id in ["trophy_room_key", "tavern_key", "bottling_key", "cooling_key"]:
		state.set_count(key_id, 0)
	state.unlock("Traveling Tavern")
	state.set_flag(AchievementBook.EARNED_PREFIX + "third_vat", false)
	state.set_flag(AchievementBook.EARNED_PREFIX + "goal_machine", false)
	state.set_count("matches_won", 0)
	state.set_count("goals", 0)
	state.set_flag(AchievementBook.EARNED_PREFIX + "second_vat", true)
	BaseRooms.buy_upgrade("second_vat", state)

	# NO STORY: mark every Progression row done, or the base hands the
	# screen to a dialogue before the picture is taken.
	for row in MenuSupport.read_csv("res://data/Progression.csv"):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text != "":
			state.set_flag(Progression.DONE_PREFIX + id_text.to_lower(), true)
	for row in MenuSupport.read_csv("res://data/Guide.csv"):
		state.set_flag(Guide.DONE_PREFIX + MenuSupport.field(row, "ID").strip_edges(), true)
	state.set_flag("game_begun")
	state.save_to_disk()
	change_scene_to_file("res://src/ui/base_screen.tscn")
	for i in 40:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	var base := current_scene
	for child in base.get_children():
		if child is NewUnlocksPanel:
			child.queue_free()

	for room in ["dorms", "clubhouse", "training", "brewery"]:
		var window := BaseWindow.open(base, base._window_title(room), ScenePaths.for_name(room))
		for i in 12:
			await process_frame
		# The brewers are at the foot of the Training Ground: scroll down.
		if room == "training":
			for node in window.find_children("*", "ScrollContainer", true, false):
				(node as ScrollContainer).scroll_vertical = 100000
			for i in 6:
				await process_frame
		await create_timer(0.7, true, false, true).timeout
		root.get_viewport().get_texture().get_image().save_png("user://%s.png" % room)
		print("[shot] user://%s.png" % room)
		window.close()
		await create_timer(0.3, true, false, true).timeout

	change_scene_to_file(ScenePaths.INSPECTOR)
	for i in 30:
		await process_frame
	await create_timer(0.6, true, false, true).timeout
	root.get_viewport().get_texture().get_image().save_png("user://dev_players.png")
	print("[shot] user://dev_players.png")

	print("[shot] pictures in %s" % ProjectSettings.globalize_path("user://"))
	TestEnvironment.leave(self)
	quit(0)
