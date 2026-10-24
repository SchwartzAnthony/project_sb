extends SceneTree

# =============================================================
#  THE DIALOGUE BOXES, PHOTOGRAPHED  (24 Oct 2026)
#
#      godot --path . --resolution 1920x1080 --script res://tools/dialogue_box_shot.gd
#
#  The Head Coach's box over the pitch (tut-kickoff) and the story screen's
#  text box, to check Tuning.csv dialogue_box_alpha. Saves
#  dialogue_box_*.png in user://. A tool; nothing loads it.
# =============================================================


func _initialize() -> void:
	await process_frame
	ThemeBook.dress(self)
	var pitch := TextureRect.new()
	pitch.texture = load("res://assets/field/match_ground_village.png")
	pitch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pitch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(pitch)
	var box := MatchTalkBox.play(root, "tut-kickoff", GameState.fetch(self), false)
	for i in 30:
		await process_frame
	_save("coach")
	if box != null:
		box.queue_free()
	pitch.queue_free()
	var view: DialogueView = load(ScenePaths.STORY).instantiate()
	view.type_speed = 0.0
	view.transition_time = 0.0
	view.return_to_menu = false
	view.scene_name = "prologue"
	root.add_child(view)
	for i in 6:
		await process_frame
	var line := view.story.line_for("tut-base-welcome", "welcome", view.state)
	if line != null:
		view._show(line)
	for i in 10:
		await process_frame
	_save("story")
	quit(0)


func _save(what: String) -> void:
	var file := "user://dialogue_box_%s.png" % what
	root.get_texture().get_image().save_png(file)
	print("[dialogue_box_shot] ", ProjectSettings.globalize_path(file))
