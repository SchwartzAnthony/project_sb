extends SceneTree

# =============================================================
#  THE TITLE SCREEN, PHOTOGRAPHED: user://shot_title.png
#
#  For comparing button looks. A tool, not part of the game.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	change_scene_to_file(ScenePaths.MAIN_MENU)
	for i in 120:
		await process_frame
	root.get_texture().get_image().save_png("user://shot_title.png")
	print("[title] shot_title.png")
	quit()
