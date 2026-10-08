extends SceneTree

# =============================================================
#  TUTORIAL JUMPS, PRESSED FOR REAL (round AN)
#
#  Opens the Dev screen, presses "Mini-game: Brew Kettle" (plays it) and
#  "The Brewery TIME OUT" (plays Hanna's whole tour), and checks the real
#  save is the one in use afterwards and was never touched.
#
#      godot --path . --resolution 1600x900 --script res://tools/tutorial_jumps_shot.gd
# =============================================================

var _frame := 0
var _trouble := 0
var _done_line := ""


func _initialize() -> void:
	await process_frame
	GameState.SAVE_PATH = "user://tutorial_jumps_real.json"
	var real := GameState.fetch(self)
	real.reset()
	real.set_count("coins", 123)
	real.save_to_disk()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tutorial_jumps"))
	change_scene_to_file("res://src/ui/save_inspector.tscn")
	for i in 20:
		await process_frame
	var screen := current_scene

	_press(_button(screen, "Mini-game: Brew Kettle"))
	await _play_game(false)
	await _hold(0.3, 2)
	_check(screen._summary.text.contains("Brew Kettle"), "the Dev screen says how the game went: " + screen._summary.text.get_slice("\n", 0))

	_press(_button(screen, "The Brewery TIME OUT"))
	await _talk()
	_press(_machine(screen, "Steeping Tank"))
	await _play_game(true)
	await _talk()
	_press(_machine(screen, "Bottling Machine"))
	await _play_game(false)
	await _talk()
	await _hold(0.3, 3)
	_check(GameState.SAVE_PATH == "user://tutorial_jumps_real.json", "back on the real save")
	var after := GameState.fetch(self)
	_check(after.count("coins") == 123 and not after.has_flag("in_tutorial") and after.count("small_bottle") == 0,
		"the real save was not touched")
	print("[jumps] %s" % ("TUTORIAL JUMPS WORK WHEN PRESSED." if _trouble == 0 else "%d PROBLEM(S)." % _trouble))
	quit(0 if _trouble == 0 else 1)


func _button(screen: Node, words: String) -> Button:
	for node in screen.find_children("*", "Button", true, false):
		if (node as Button).text == words:
			return node as Button
	return null


## Click through the box on screen until it is gone.
func _talk() -> void:
	var guard := 0
	while _box() == null and guard < 100:
		await _hold(0.05, 0)
		guard += 1
	var shots := 0
	while _box() != null and guard < 400:
		await create_timer(1.3, true, false, true).timeout
		await process_frame
		_shoot()
		var box := _box()
		if box != null:
			box._next()
		guard += 1
		shots += 1
	print("[jumps] %d line(s) clicked through." % shots)
	await _hold(0.3, 2)


func _box() -> MatchTalkBox:
	for node in root.find_children("*", "MatchTalkBox", true, false):
		if not node.is_queued_for_deletion():
			return node as MatchTalkBox
	return null


## Play the open mini-game with the good hand (BreweryMinigame.bot_step),
## which uses the game's own inputs. `miss_first` lets it fail once on purpose
## (does nothing until it is lost) to prove the tutorial forgives.
func _play_game(miss_first: bool) -> void:
	await process_frame
	var games := root.find_children("*", "BreweryMinigame", true, false)
	if games.is_empty():
		_check(false, "a mini-game opened")
		return
	var game := games[0] as BreweryMinigame
	print("[jumps] %s: %s." % [game.title, game.kind()])
	await _hold(0.4, 2)
	if miss_first:
		if game.kind() in ["conveyor", "hold", "colour"]:
			game.press()                 # hold on until it goes wrong
		var started := game._time_left
		var guard := 0
		while game._time_left <= started and guard < 2000:
			started = game._time_left
			await process_frame
			guard += 1
			if guard % 8 == 0:
				_shoot()
		_check(not game._over, "a miss in the tutorial starts the game again: " + game._status.text)
		await _hold(0.3, 2)
	var guard := 0
	var last := Time.get_ticks_msec()
	while is_instance_valid(game) and not game._over and guard < 4000:
		await process_frame
		var now := Time.get_ticks_msec()
		game.bot_step((now - last) / 1000.0, false)
		last = now
		guard += 1
		if guard % 8 == 0:
			_shoot()
	_check(is_instance_valid(game) and game._won, "the game is won")
	while is_instance_valid(game):
		await process_frame
	await _hold(0.3, 3)


func _machine(screen: Node, words: String) -> Button:
	for node in screen.find_children("*", "Button", true, false):
		if (node as Button).tooltip_text.begins_with(words):
			return node as Button
	return null


func _press(button: Button) -> void:
	if button == null:
		_check(false, "the button is on screen")
		return
	button.emit_signal("pressed")


func _check(ok: bool, what: String) -> void:
	print("[jumps] %s %s" % ["ok " if ok else "! ", what])
	if not ok:
		_trouble += 1


func _hold(gap: float, shots: int) -> void:
	if shots <= 0:
		await create_timer(gap, true, false, true).timeout
		return
	for i in shots:
		await create_timer(gap, true, false, true).timeout
		await process_frame
		_shoot()


func _shoot() -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png("user://tutorial_jumps/frame_%03d.png" % _frame)
	_frame += 1
