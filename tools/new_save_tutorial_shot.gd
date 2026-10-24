extends SceneTree

# =============================================================
#  A NEW SAVE AND ITS TUTORIAL, PHOTOGRAPHED  (Anthony, 24 Oct)
#
#      xvfb-run -a godot --rendering-driver opengl3 --resolution 1920x1080 \
#          --script res://tools/new_save_tutorial_shot.gd
#
#  nst_01_menu       the title screen: Start, Settings, Quit
#  nst_02_question   a new save asks "Would you like to do the Tutorial?"
#  nst_03_tutorial   Yes: the Tutorial in its own save
#  nst_04_menu_after the Tutorial is done: back on the title screen
#  nst_05_base       Play on that mug: a fresh game at the base
#
#  Uses save slot 3 and wipes it before and after. A tool; nothing loads it.
# =============================================================

const SLOT := 3


func _initialize() -> void:
	await process_frame
	SaveSlots.erase(SLOT)
	await _go(ScenePaths.MAIN_MENU, 40)
	_shot("nst_01_menu")

	SaveSlots.choose(self, SLOT)
	await _go(ScenePaths.BASE, 60)
	_shot("nst_02_question")

	Tutorial.start(self, false)
	await _wait(120)
	_shot("nst_03_tutorial")

	Tutorial.finish(self)
	await _wait(60)
	_shot("nst_04_menu_after")
	print("[shot] slot %d begun after the Tutorial: %s" % [SLOT, SaveSlots.begun(SLOT)])

	SaveSlots.choose(self, SLOT)
	await _go(ScenePaths.BASE, 90)
	_shot("nst_05_base")
	print("[shot] players in slot %d: %d" % [SLOT, RecruitBook.names(GameState.fetch(self)).size()])

	print("[shot] slot %d begun at the end: %s" % [SLOT, SaveSlots.begun(SLOT)])
	SaveSlots.erase(SLOT)
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
