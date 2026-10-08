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
	var last := Time.get_ticks_msec()
	while is_instance_valid(game) and not game._over and guard < 4000:
		await process_frame
		var now := Time.get_ticks_msec()
		# The lost one: the hand stops halfway.
		if not (lose and game._time_left < float(game.game.get("seconds", 10.0)) * 0.6):
			game.bot_step((now - last) / 1000.0, false)
		last = now
		guard += 1
		if guard % 3 == 0:
			_hold_shot()
	while is_instance_valid(game):
		await _hold(0.1, 1)
	await _hold(0.2, 2)


func _hold_shot() -> void:
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("user://minigames/frame_%03d.png" % _frame)
		_frame += 1


func _hold(gap: float, shots: int) -> void:
	for i in shots:
		await create_timer(gap, true, false, true).timeout
		await process_frame
		if DisplayServer.get_name() != "headless":
			root.get_texture().get_image().save_png("user://minigames/frame_%03d.png" % _frame)
			_frame += 1
