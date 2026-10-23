extends SceneTree

# =============================================================
#  THE GENERAL SETTINGS "SAVE FOR WHICH SAVES?" BOX, PHOTOGRAPHED:
#  user://shot_general_save.png
#
#  Opens the title screen's Settings (General), changes one setting and
#  presses Save, so the box shows. A tool, not part of the game.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	GameSettings.editing_slot = 0
	change_scene_to_file(ScenePaths.SETTINGS)
	for i in 60:
		await process_frame
	var screen := current_scene
	screen.settings["palette"] = "deuteranopia" if screen.settings.get("palette") != "deuteranopia" else "default"
	screen._save()
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png("user://shot_general_save.png")
	print("[settings] shot_general_save.png")
	quit()
