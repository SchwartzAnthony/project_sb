extends SceneTree

# =============================================================
#  PICTURES OF THE CLUB HOUSE AND THE TRAINING GROUND  (round AN)
#
#      godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/rooms_shot.gd
#
#  Runs inside the TEST ENVIRONMENT, so your real save is never touched.
#  Leaves some keys and upgrades unbought (one locked), signs up a few
#  recruits waiting for a role, opens the Club House and the Training
#  Ground over the base, hovers a thing in each, opens their paper lists,
#  and lets the Head Coach speak once in each. Writes clubhouse_room.png,
#  clubhouse_hover.png, clubhouse_list.png, clubhouse_coach.png and the
#  same four for training_ into the user:// folder.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	var db := CardDatabase.get_db()
	var state := GameState.fetch(self)
	state.set_count("coins", 900)

	# ---- the shelf: some keys and upgrades still to buy, one locked ----
	for key_id in ["trophy_room_key", "tavern_key", "bottling_key", "cooling_key", "lautering_key"]:
		state.set_count(key_id, 0)
	state.unlock("Traveling Tavern")
	state.set_flag(AchievementBook.EARNED_PREFIX + "third_vat", false)
	state.set_count("matches_won", 0)
	state.set_flag(AchievementBook.EARNED_PREFIX + "second_vat", true)
	BaseRooms.buy_upgrade("second_vat", state)

	# ---- recruits: three new lads waiting for a role, one brewer ----
	for who in [["Johanna", "I", 0, "f"], ["Sepp", "III", 3, "m"], ["Vroni", "II", 2, "f"], ["Hias", "I", 1, "m"]]:
		RecruitBook.enlist(String(who[0]), String(who[1]), int(who[2]), String(who[3]), state, "", "new")
	BaseRooms.train_brewer("Johanna", state)
	# One Ausbildung taken, one mini-game taken.
	state.set_flag(BaseRooms.TRAINED_PREFIX + "ausbildung_keeper", true)
	state.set_flag(BaseRooms.TRAINED_PREFIX + "mini_mill", true)

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

	for room in ["clubhouse", "training"]:
		var window := BaseWindow.open(base, base._window_title(room), ScenePaths.for_name(room))
		await create_timer(0.9, true, false, true).timeout
		_shoot(room + "_room")
		var screen := window.content as SceneRoom
		# Hover the first lit thing.
		for node in screen.find_children("*", "MapBuilding", true, false):
			if String(node.get_meta("look", "")) == "open":
				node.mouse_entered.emit()
				break
		await create_timer(0.3, true, false, true).timeout
		_shoot(room + "_hover")
		screen._tag.visible = false
		if room == "clubhouse":
			screen.call("_show_recruits")
		else:
			screen.call("_show_team_sheet")
		await create_timer(0.4, true, false, true).timeout
		_shoot(room + "_list")
		screen.close_sheet()
		window.close()
		await create_timer(0.3, true, false, true).timeout
		state.set_flag(Guide.DONE_PREFIX + room + "_explain", false)
		window = BaseWindow.open(base, base._window_title(room), ScenePaths.for_name(room))
		await create_timer(1.6, true, false, true).timeout
		_shoot(room + "_coach")
		window.close()
		await create_timer(0.4, true, false, true).timeout

	print("[shot] pictures in %s" % ProjectSettings.globalize_path("user://"))
	TestEnvironment.leave(self)
	quit(0)


func _shoot(name_text: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("user://%s.png" % name_text)
	print("[shot] user://%s.png" % name_text)
