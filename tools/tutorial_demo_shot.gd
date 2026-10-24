extends SceneTree

# =============================================================
#  THE TUTORIAL DEMO, PHOTOGRAPHED  (Anthony, 24 Oct)
#
#      xvfb-run -a godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/tutorial_demo_shot.gd
#
#  With Tuning.csv tutorial_only true: Play on an empty mug plays the
#  Tutorial, and at its end you are on the main menu with that mug empty.
#  demo_01_menu, demo_02_mugs, demo_03_tutorial, demo_04_menu_after,
#  demo_05_mugs_after. Uses save slot 3. A tool; nothing loads it.
# =============================================================

const SLOT := 3


func _initialize() -> void:
	await process_frame
	SaveSlots.erase(SLOT)
	await _go(ScenePaths.MAIN_MENU, 40)
	_shot("demo_01_menu")
	await _go(ScenePaths.SLOTS, 40)
	_shot("demo_02_mugs")
	current_scene.call("_play", SLOT)
	await _wait(120)
	_shot("demo_03_tutorial")
	print("[shot] tutorial running: %s" % Tutorial.active(self))
	Tutorial.finish(self)
	await _wait(60)
	_shot("demo_04_menu_after")
	print("[shot] slot %d begun: %s, file there: %s" % [SLOT, SaveSlots.begun(SLOT),
		FileAccess.file_exists(SaveSlots.state_path(SLOT))])
	await _go(ScenePaths.SLOTS, 40)
	_shot("demo_05_mugs_after")
	quit(0)


func _go(path: String, frames: int) -> void:
	ScenePaths.go_to(self, path, false)
	await _wait(frames)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("user://%s.png" % name)
	print("[shot] %s.png" % name)
