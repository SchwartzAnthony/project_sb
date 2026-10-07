extends SceneTree

# =============================================================
#  PHOTOGRAPH THE MOVING TITLE SCREEN  (round AN)
#
#      godot --path . --script res://tools/menu_motion_shot.gd
#
#  Opens the title screen and saves a picture every second for 13
#  seconds into user://menu_motion/ (shot_00.png ...), so the sign, the
#  clouds, the ribbons and the bird (MainMenu.csv Motion) can be checked
#  without watching. Runs in the TEST ENVIRONMENT - your save is safe.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	GameState.fetch(self).set_flag("game_begun")
	DirAccess.make_dir_recursive_absolute("user://menu_motion")
	ScenePaths.go_to(self, "res://src/ui/main_menu.tscn")
	await process_frame
	await process_frame
	for i in 14:
		root.get_texture().get_image().save_png("user://menu_motion/shot_%02d.png" % i)
		await create_timer(1.0, true, false, true).timeout
	print("[motion] 14 pictures in user://menu_motion/")
	TestEnvironment.leave(self)
	quit(0)
