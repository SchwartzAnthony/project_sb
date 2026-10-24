extends SceneTree

# =============================================================
#  KOCH'S TRANSFORMATION FACES, PHOTOGRAPHED  (24 Oct 2026)
#
#      godot --path . --resolution 1920x1080 --script res://tools/bergmaennlein_portrait_shot.gd
#
#  The pub time out (tut-timeout-cursed): the Head Coach, then Koch's
#  silhouette, then the Bergmännlein, to check they sit like the coach.
#  Also the coach box over the pitch with the Bergmännlein (tut-koch-new-card).
#  Saves berg_*.png in user://. A tool; nothing loads it.
# =============================================================


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
	for node in ["extraction", "dark", "changed"]:
		var line := view.story.line_for("tut-timeout-cursed", node, view.state)
		if line != null:
			view._show(line)
		for i in 10:
			await process_frame
		_save(node)
	view.queue_free()
	var pitch := TextureRect.new()
	pitch.texture = load("res://assets/field/match_ground_village.png")
	pitch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pitch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(pitch)
	var box := MatchTalkBox.play(root, "tut-koch-new-card", GameState.fetch(self), false)
	for i in 30:
		await process_frame
	_save("box_coach")
	if box != null and box.has_method("_next"):
		box._next()
		for i in 30:
			await process_frame
		_save("box_koch")
	quit(0)


func _save(what: String) -> void:
	var file := "user://berg_%s.png" % what
	root.get_texture().get_image().save_png(file)
	print("[berg_shot] ", ProjectSettings.globalize_path(file))
