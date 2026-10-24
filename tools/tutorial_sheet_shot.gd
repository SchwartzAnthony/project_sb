extends SceneTree

# =============================================================
#  THE TUTORIAL MATCH'S TEAM SHEET, PHOTOGRAPHED  (Anthony 24 Oct 2026)
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/tutorial_sheet_shot.gd -- [before]
#
#  Plays a fresh Tutorial up to its match (in user://tutorial_sheet_shot/, so
#  your saves are never touched) and photographs the sheet with START on it.
#  "before" turns tutorial_vs_plain off for the old look.
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const DIR := "user://tutorial_sheet_shot"


func _initialize() -> void:
	seed(20261024)
	var before := OS.get_cmdline_user_args().has("before")
	var db := CardDatabase.get_db()
	db.tuning[CardDatabase._normalise("choice_window_seconds")] = "0"
	db.tuning[CardDatabase._normalise("tutorial_vs_plain")] = "false" if before else "true"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	await process_frame
	for file_name in ["story.json", "teams.json"]:
		if FileAccess.file_exists(DIR + "/" + file_name):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + file_name))
	GameState.SAVE_PATH = DIR + "/story.json"
	TeamRoster.SAVE_PATH = DIR + "/teams.json"
	GameState.forget(self)
	TeamSelection.clear(self)
	Tutorial.start(self, true)

	# Click through the story and the Pub until the match is up.
	var sheet = null
	for i in 900:
		await create_timer(0.2, true, false, true).timeout
		var scene := current_scene
		if scene == null:
			continue
		if scene.has_method("show_enemy_team"):
			sheet = scene.get("_sheet")
			if sheet != null and is_instance_valid(sheet) and bool(sheet.get("_opened")):
				break
			sheet = null
			continue
		_nudge(scene)

	if sheet == null:
		print("[tutorial sheet] the sheet never opened")
		quit(1)
		return
	await create_timer(10.0, true, false, true).timeout
	var image := root.get_texture().get_image()
	var path := DIR + "/sheet_%s.png" % ("before" if before else "after")
	image.save_png(path)
	print("[tutorial sheet] saved ", ProjectSettings.globalize_path(path))
	quit(0)


## Move the story on: read a dialogue line, or press the Pub on the base.
func _nudge(scene: Node) -> void:
	var where := scene.scene_file_path.get_file()
	if where.contains("dialogue"):
		scene.call("_finish_typing")
		var line = scene.get("_line")
		if line != null and line.has_choices():
			var choices: Array = line.available_choices(scene.get("state"))
			if not choices.is_empty():
				scene.call("_on_choice", choices[0])
				return
		scene.call("_advance")
	elif where.contains("base"):
		for button in _buttons(scene):
			if not button.disabled and button.is_visible_in_tree() and Guide.says(button, "pub"):
				button.emit_signal("pressed")
				return


func _buttons(node: Node) -> Array[BaseButton]:
	var found: Array[BaseButton] = []
	if node is BaseButton:
		found.append(node)
	for child in node.get_children():
		found.append_array(_buttons(child))
	return found
