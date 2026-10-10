extends SceneTree

# =============================================================
#  PICTURES OF THE DORMS SCREEN  (round AN, Anthony 10 Oct)
#
#      godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/dorms_screen_shot.gd
#
#  Runs inside the TEST ENVIRONMENT, so your real save is never touched.
#  Puts players to bed (one, three and five fixtures of rest, some part
#  rested), buys a second and a third room and seven single beds, opens the Dorms over the
#  base, hovers a sleeper, then clicks tab 2 and records the slide.
#  Writes dorms_room1.png, dorms_hover.png, dorms_room2.png and
#  dorms_slide_00.png ... into the user:// folder.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	var db := CardDatabase.get_db()
	var state := GameState.fetch(self)
	db.tuning["recovery"] = "true"
	state.set_count("coins", 900)
	state.unlock("Dorms")
	state.set_count("dorms_key", 1)

	# ---- in bed: a spread of powers, some part way through ----
	var cards: Array = db.players.filter(func(c: PlayerData) -> bool: return not c.is_star())
	var put := 0
	for card in cards:
		if put >= 14:
			break
		var power := maxi(card.get_attack_power(), card.get_defense_power())
		if power <= 0:
			continue
		RecoveryBook.send_to_dorms(card, "match", [], state, db)
		# Some have slept a fixture or two already.
		var left := RecoveryBook.turns_left(card, state)
		state.set_count(RecoveryBook.key_for(card), maxi(1, left - put % 3))
		put += 1

	# ---- a second and a third room, some single beds in them ----
	print("[shot] room 2: ", BaseRooms.buy_dorm("room_2", state))
	for i in 7:
		BaseRooms.buy_bed(state)
	print("[shot] room 3: ", BaseRooms.buy_dorm("room_3", state))
	state.set_count("coins", 900)
	print("[shot] beds by room: ", BaseRooms.beds_by_room(state))

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

	var window := BaseWindow.open(base, base._window_title("dorms"), ScenePaths.for_name("dorms"))
	for i in 12:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	_shoot("dorms_room1")

	# ---- hover the first sleeper ----
	var screen := window.content as DormsScreen
	for node in screen.find_children("*", "MapBuilding", true, false):
		var bed := node as MapBuilding
		if bed.tooltip_text.contains("P:"):
			bed.mouse_entered.emit()
			break
	await create_timer(0.3, true, false, true).timeout
	_shoot("dorms_hover")
	screen._hover.visible = false

	# ---- tab 2, recording the slide ----
	screen._show_room(1)
	for f in 12:
		await create_timer(0.033, true, false, true).timeout
		_shoot("dorms_slide_%02d" % f)
	await create_timer(0.4, true, false, true).timeout
	_shoot("dorms_room2")
	screen._show_room(2)
	await create_timer(0.6, true, false, true).timeout
	_shoot("dorms_room3")

	print("[shot] pictures in %s" % ProjectSettings.globalize_path("user://"))
	TestEnvironment.leave(self)
	quit(0)


func _shoot(name_text: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("user://%s.png" % name_text)
	print("[shot] user://%s.png" % name_text)
