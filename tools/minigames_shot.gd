extends SceneTree

# =============================================================
#  ALL SIX BREWING MINI-GAMES, PLAYED (round AN)
#
#  Opens the Brewery on a throwaway save and plays every machine's game in
#  turn with its own press/release, the way a hand would: one game lost on
#  purpose (the Grain Mill, too slow) so the spoil shows too.
#
#      godot --path . --resolution 1600x900 --script res://tools/minigames_shot.gd
#
#  Pictures: user://minigames/frame_NNN.png  (tools turn them into a GIF).
# =============================================================

var _frame := 0


func _initialize() -> void:
	await process_frame
	GameState.SAVE_PATH = "user://minigames_throwaway.json"
	var state := GameState.fetch(self)
	state.reset()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://minigames"))
	change_scene_to_file("res://src/ui/brewery_screen.tscn")
	for i in 20:
		await process_frame
	var screen := current_scene
	for section in BreweryBook.sections():
		var id_text := String(section["id"])
		var game := BreweryMinigame.game_for(id_text)
		if game.is_empty():
			continue
		var lose := id_text == "mill"
		var view := BreweryMinigame.open(screen, game, 85, String(section["name"]))
		print("[games] %s: %s" % [section["name"], game["kind"]])
		await _play(view, lose)
	print("[games] %d frame(s)." % _frame)
	quit(0)


func _play(game: BreweryMinigame, lose: bool) -> void:
	await _hold(0.5, 3)
	var guard := 0
	match game.kind():
		"hold":
			game.press()
			while is_instance_valid(game) and not game.in_zone() and guard < 2000:
				await _hold(0.05, 1)
				guard += 1
			await _hold(0.04, 1)
			if is_instance_valid(game):
				game.release()
		"mash":
			var clicks := 0
			while is_instance_valid(game) and not game._over and guard < 2000:
				await _hold(0.05 if not lose else 0.25, 1)
				game.press()
				clicks += 1
				guard += 1
		_:
			while is_instance_valid(game) and not game._over and guard < 4000:
				await _hold(0.04, 1)
				guard += 1
				if game.in_zone() and game._pos > game._zone_start + game._zone_size * 0.3:
					game.press()
					await _hold(0.1, 2)
	while is_instance_valid(game):
		await _hold(0.1, 1)
	await _hold(0.2, 2)


func _hold(gap: float, shots: int) -> void:
	for i in shots:
		await create_timer(gap, true, false, true).timeout
		await process_frame
		if DisplayServer.get_name() != "headless":
			root.get_texture().get_image().save_png("user://minigames/frame_%03d.png" % _frame)
			_frame += 1
