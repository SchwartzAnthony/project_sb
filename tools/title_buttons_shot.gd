extends SceneTree

# =============================================================
#  THE TITLE SCREEN, PHOTOGRAPHED: user://shot_title.png
#
#  For comparing button looks. Another screen: add -- settings (or any
#  scene path) after the command; the picture is then user://shot_<name>.png.
#  A tool, not part of the game.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	var scene := ScenePaths.MAIN_MENU
	var shot := "title"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		shot = String(args[0])
		scene = ScenePaths.SETTINGS if shot == "settings" else shot
		shot = shot.get_file().get_basename()
	change_scene_to_file(scene)
	for i in 120:
		await process_frame
	root.get_texture().get_image().save_png("user://shot_%s.png" % shot)
	print("[title] shot_%s.png" % shot)
	quit()
