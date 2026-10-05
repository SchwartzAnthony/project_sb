extends SceneTree

# =============================================================
#  ART PHASE A1, IN THE GAME  (round AH)
#
#      xvfb-run godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/a1_shot.gd
#
#  Photographs the main menu and the base with the new wallpapers. Runs in
#  the TEST ENVIRONMENT, so your real save is never touched.
#  Writes a1_menu.png and a1_base.png into the user:// folder.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	# Skip the opening story: a new save's first visit to the base plays it.
	GameState.fetch(self).set_flag("game_begun")
	for pair in [["res://src/ui/main_menu.tscn", "a1_menu"], ["res://src/ui/base_screen.tscn", "a1_base"]]:
		# Twice: if a story scene took over the first time, it has been seen now.
		for attempt in 2:
			change_scene_to_file(String(pair[0]))
			for i in 40:
				await process_frame
		await create_timer(1.0, true, false, true).timeout
		# A story scene may open over the base: Escape leaves it.
		for i in 3:
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.pressed = true
			root.push_input(esc)
			await create_timer(0.4, true, false, true).timeout
		_free_panels(current_scene)
		await create_timer(0.4, true, false, true).timeout
		root.get_texture().get_image().save_png("user://%s.png" % pair[1])
		print("[a1] user://%s.png" % pair[1])
	TestEnvironment.leave(self)
	quit(0)


func _free_panels(at: Node) -> void:
	if at == null:
		return
	for child in at.get_children():
		if child is NewUnlocksPanel:
			child.queue_free()
