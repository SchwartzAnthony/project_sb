extends SceneTree

# =============================================================
#  EVERY SETTINGS TAB, PHOTOGRAPHED: user://shot_settings_<tab>.png
#  A tool, not part of the game.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	change_scene_to_file(ScenePaths.SETTINGS)
	for i in 90:
		await process_frame
	var screen := current_scene
	for tab in screen.TABS:
		screen._show_tab(tab)
		for i in 20:
			await process_frame
		var name := String(tab).to_lower().replace(" ", "_")
		root.get_texture().get_image().save_png("user://shot_settings_%s.png" % name)
		print("[settings] shot_settings_%s.png" % name)
	quit()
