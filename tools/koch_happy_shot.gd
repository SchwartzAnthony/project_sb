extends SceneTree

# =============================================================
#  KOCH CHEERS UP, PHOTOGRAPHED  (24 Oct 2026)
#
#      godot --path . --resolution 1920x1080 --script res://tools/koch_happy_shot.gd
#
#  Plays prologue put_down, still_cold and finish_up in order and saves
#  koch_happy_<n>.png in user://. On finish_up Koch, who is not speaking,
#  turns happy again (Dialogue.csv Joins koch:right:happy). A tool.
# =============================================================

const SHOTS := ["put_down", "still_cold", "finish_up"]


func _initialize() -> void:
	await process_frame
	ThemeBook.dress(self)
	var view: DialogueView = load(ScenePaths.STORY).instantiate()
	view.type_speed = 0.0
	view.transition_time = 0.0
	view.return_to_menu = false
	view.scene_name = "prologue"
	root.add_child(view)
	for i in 6:
		await process_frame
	var open := view.story.line_for("prologue", "open", view.state)
	view._show(open)
	for n in SHOTS.size():
		var line := view.story.line_for("prologue", SHOTS[n], view.state)
		view._show(line)
		for i in 8:
			await process_frame
		var file := "user://koch_happy_%d_%s.png" % [n + 1, SHOTS[n]]
		root.get_texture().get_image().save_png(file)
		print("[koch_happy_shot] ", ProjectSettings.globalize_path(file))
	quit(0)
