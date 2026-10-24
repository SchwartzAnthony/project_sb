extends SceneTree

# =============================================================
#  THE BOTTLING MINI-GAME, PLAYED (Anthony, 24 Oct: redrawn in our style)
#
#      godot --path . --resolution 1600x900 --script res://tools/bottling_shot.gd
#
#  Pictures: user://bottling/frame_NNN.png  (tools turn them into a GIF).
# =============================================================

var _frame := 0


func _initialize() -> void:
	await process_frame
	GameState.SAVE_PATH = "user://bottling_throwaway.json"
	GameState.fetch(self).reset()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bottling"))
	change_scene_to_file("res://src/ui/brewery_screen.tscn")
	for i in 20:
		await process_frame
	var game := BreweryMinigame.game_for("bottling")
	var view := BreweryMinigame.open(current_scene, game, 85, "Bottling Machine")
	await _shots(0.4, 3)
	var last := Time.get_ticks_msec()
	var guard := 0
	while is_instance_valid(view) and not view._over and guard < 4000:
		await process_frame
		var now := Time.get_ticks_msec()
		view.bot_step((now - last) / 1000.0, false)
		last = now
		guard += 1
		if guard % 3 == 0:
			_shot()
	await _shots(0.1, 6)
	print("[bottling] %d frame(s)." % _frame)
	quit(0)


func _shots(wait: float, many: int) -> void:
	for i in many:
		await create_timer(wait).timeout
		_shot()


func _shot() -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://bottling/frame_%03d.png" % _frame)
	_frame += 1
