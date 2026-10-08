extends SceneTree

# =============================================================
#  PICTURES OF A LOCKED ROLE AND QUEREINSTEIGER  (round AN)
#
#      godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/quereinsteiger_shot.gd
#
#  Runs inside the TEST ENVIRONMENT, so your real save is never touched.
#  Signs an untrained player, a Match Player, an Adventure Player and a
#  Brewer, then:
#      quereinsteiger_1.png   the Training Ground, roles locked
#      quereinsteiger_2.png   Quereinsteiger unlocked: Retrain buttons
#      quereinsteiger_3.png   Wastl retrained from Adventure to Match
#  into the user:// folder.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	var state := GameState.fetch(self)
	state.set_count("coins", 500)
	# The test environment grants everything; take Quereinsteiger back for the first picture.
	state.unlocks.erase(state._key("Quereinsteiger"))

	for who in [["Loisl", "I", 1, "m", "new"], ["Wastl", "III", 3, "m", "adventure"],
			["Kathi", "II", 2, "f", "match"], ["Hias", "II", 3, "m", "new"]]:
		RecruitBook.enlist(String(who[0]), String(who[1]), int(who[2]), String(who[3]), state,
			"", String(who[4]))
	BaseRooms.train_brewer("Hias", state)

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

	var window := BaseWindow.open(base, base._window_title("training"), ScenePaths.for_name("training"))
	await _settle(window)
	await _shot("quereinsteiger_1")
	window.close()
	await create_timer(0.3, true, false, true).timeout

	state.unlock("Quereinsteiger")
	window = BaseWindow.open(base, base._window_title("training"), ScenePaths.for_name("training"))
	await _settle(window)
	await _shot("quereinsteiger_2")
	var button := _button_in_row(window, "Wastl", "Retrain: Match")
	if button != null:
		button.pressed.emit()
	await _settle(window)
	await _shot("quereinsteiger_3")
	window.close()

	print("[shot] pictures in %s" % ProjectSettings.globalize_path("user://"))
	TestEnvironment.leave(self)
	quit(0)


## Let the window draw, and scroll YOUR PLAYERS into view.
func _settle(window: Node) -> void:
	for i in 10:
		await process_frame
	var heading: Control = null
	for node in window.find_children("*", "Label", true, false):
		if (node as Label).text == "YOUR PLAYERS":
			heading = node
	for node in window.find_children("*", "ScrollContainer", true, false):
		if heading != null and (node as ScrollContainer).is_ancestor_of(heading):
			(node as ScrollContainer).scroll_vertical = int(heading.position.y) - 8
	for i in 6:
		await process_frame
	await create_timer(0.5, true, false, true).timeout


## The button starting with `words` in the row that names `who`.
func _button_in_row(window: Node, who: String, words: String) -> Button:
	for node in window.find_children("*", "Label", true, false):
		if not (node as Label).text.begins_with(who + "  ·"):
			continue
		var row: Node = node.get_parent()
		while row != null and row.find_children("*", "Button", true, false).is_empty():
			row = row.get_parent()
		if row == null:
			return null
		for b in row.find_children("*", "Button", true, false):
			if (b as Button).text.begins_with(words):
				return b
	return null


func _shot(name_text: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("user://%s.png" % name_text)
	print("[shot] user://%s.png" % name_text)
