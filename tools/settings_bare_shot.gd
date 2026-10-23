extends SceneTree

# =============================================================
#  THE SETTINGS BACKGROUND ALONE: user://shot_settings_bare.png
#
#  Only the painted layers from ScreenLook.csv, with the settings page,
#  the dark box and the sign hidden. A tool, not part of the game.
# =============================================================


func _initialize() -> void:
	await process_frame
	change_scene_to_file(ScenePaths.SETTINGS)
	for i in 60:
		await process_frame
	for child in current_scene.get_children():
		if child is CanvasItem and not child is TextureRect:
			(child as CanvasItem).visible = false
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("user://shot_settings_bare.png")
	print("[settings] shot_settings_bare.png")
	quit()
