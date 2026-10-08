extends SceneTree

# =============================================================
#  PICTURES OF MATCH PLAYERS, ADVENTURE PLAYERS AND BREWERS  (round AN)
#
#      godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/roles_shot.gd
#
#  Runs inside the TEST ENVIRONMENT, so your real save is never touched.
#  Signs two untrained players, an Adventure Player and a Brewer, then:
#      roles_training_1..3.png   the Training Ground before and after two
#                                players are trained (the frames of the GIF)
#      roles_builder.png         the team builder on an Adventure Team
#      roles_pick_adventure.png  the team shelf before an Adventure run
#  into the user:// folder.
# =============================================================

var _n := 0


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	var db := CardDatabase.get_db()
	var state := GameState.fetch(self)
	state.set_count("coins", 500)

	for who in [["Loisl", "I", 1, "m", "new"], ["Resi", "II", 2, "f", "new"],
			["Wastl", "III", 3, "m", "adventure"], ["Kathi", "I", 0, "f", "adventure"],
			["Girgl", "II", 1, "m", "adventure"], ["Vevi", "IV", 2, "f", "adventure"],
			["Hias", "II", 3, "m", "match"]]:
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

	# ---- the Training Ground: before, Loisl to Adventure, Resi to Match ----
	var window := BaseWindow.open(base, base._window_title("training"), ScenePaths.for_name("training"))
	await _settle(window)
	await _shot("roles_training_1")
	for step in [["Loisl", "Adventure"], ["Resi", "Match"]]:
		var button := _button_in_row(window, String(step[0]), String(step[1]))
		if button != null:
			button.pressed.emit()
		await _settle(window)
		_n += 1
		await _shot("roles_training_%d" % (_n + 1))
	window.close()
	await create_timer(0.3, true, false, true).timeout

	# ---- an Adventure Team in the builder ----
	var book := TeamRoster.load_all()
	var klass := db.tune_text("recruit_plain_class", "Normal")
	var stars := db.stars_for_class(klass)
	var entry := TeamRoster.blank(klass, stars[0].get_tier_clean() if not stars.is_empty() else "IV", "adventure")
	entry["name"] = "Die Wanderer"
	book.put(entry)
	book.save()
	TeamBuilderHandoff.edit(self, String(entry["id"]))
	change_scene_to_file(ScenePaths.TEAM_BUILDER)
	for i in 30:
		await process_frame
	await create_timer(0.8, true, false, true).timeout
	# Save it, so the shelf has it.
	current_scene._save_team()
	await _shot("roles_builder")

	# ---- the shelf before an Adventure run ----
	for mode in [["adventure", "roles_pick_adventure"]]:
		MatchMode.choose(self, String(mode[0]))
		change_scene_to_file(ScenePaths.TEAM_SELECT)
		for i in 30:
			await process_frame
		await create_timer(0.6, true, false, true).timeout
		await _shot(String(mode[1]))

	print("[shot] pictures in %s" % ProjectSettings.globalize_path("user://"))
	MatchMode.clear(self)
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
