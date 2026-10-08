extends SceneTree

# =============================================================
#  PHOTOGRAPH THE MENU SCREENS  (round AL)
#
#      xvfb-run godot --path . --script res://tools/screens_shot.gd
#
#  Opens the title screen, Settings and the save screen one after another
#  (the menu music keeps going, so this also tests that) and saves
#  shot_menu.png, shot_settings.png and shot_slot.png into user://.
#  Runs in the TEST ENVIRONMENT, so your real save is never touched.
# =============================================================


func _initialize() -> void:
	await process_frame
	TestEnvironment.enter(self)
	GameState.fetch(self).set_flag("game_begun")
	var player_before: Object = null
	for pair in [["res://src/ui/main_menu.tscn", "menu"], ["res://src/ui/settings_screen.tscn", "settings"],
			["res://src/ui/slot_screen.tscn", "slot"], ["res://src/ui/main_menu.tscn", "menu_again"]]:
		ScenePaths.go_to(self, String(pair[0]))
		for i in 40:
			await process_frame
		await create_timer(1.2, true, false, true).timeout
		root.get_texture().get_image().save_png("user://shot_%s.png" % pair[1])
		var music := _music()
		print("[shots] %s  music: %s (%.1f s) at %s dB%s" % [pair[1],
			(music.stream.resource_path.get_file() if music.stream.resource_path != "" else "the file, read fresh") if music != null and music.stream != null else "none",
			music.stream.get_length() if music != null and music.stream != null else 0.0,
			"%.1f" % music.volume_db if music != null else "-",
			"  (same player as before - no restart)" if music != null and music == player_before else ""])
		player_before = music
	TestEnvironment.leave(self)
	quit(0)


func _music() -> AudioStreamPlayer:
	var director := AudioDirector.fetch(self)
	if director == null:
		return null
	for child in director.get_children():
		if child is AudioStreamPlayer and String(child.name).contains("Loop_Music") and (child as AudioStreamPlayer).playing:
			return child
	return null
