extends SceneTree

# Round AC: photographs the Dev screen and the base inside the TEST
# COMPLETE ENVIRONMENT (te_inspector.png, te_base.png, te_teams.png).
#     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1920x1080 --script res://tools/test_env_shot.gd


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	for scene_path in [ScenePaths.INSPECTOR, ScenePaths.BASE, ScenePaths.TEAM_SELECT]:
		change_scene_to_file(scene_path)
		for i in 40:
			await process_frame
		var shot := "user://te_%s.png" % scene_path.get_file().get_basename()
		root.get_texture().get_image().save_png(shot)
		print("[test env shot] ", ProjectSettings.globalize_path(shot))
	TestEnvironment.leave(self)
	quit(0)
