extends SceneTree

# =============================================================
#  THE TUTORIAL BREWERY, PRESSED FOR REAL (round AN)
#
#  Opens the Brewery the way the tutorial's TIME OUT does (the tree paused,
#  flag:tut_brewery set, in_match), clicks through Hanna's lines, tries a
#  machine that is not lit (refused), plays the Steeping Tank and Bottling
#  mini-games with the good hand (failing once on purpose), and checks
#  the bag holds plain beer and the screen leaves on its own.
#
#      godot --path . --resolution 1600x900 --script res://tools/brewery_tour_shot.gd
#
#  Pictures: user://brewery_tour/frame_NNN.png
# =============================================================

var _frame := 0
var _trouble := 0
var _left := false


func _initialize() -> void:
	await process_frame
	GameState.SAVE_PATH = "user://brewery_tour_throwaway.json"
	var state := GameState.fetch(self)
	state.reset()
	state.set_flag("in_tutorial", true)
	state.set_flag("tut_brewery", true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://brewery_tour"))

	var layer := CanvasLayer.new()
	layer.layer = 140
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(layer)
	paused = true
	var screen := (load("res://src/ui/brewery_screen.tscn") as PackedScene).instantiate() as BreweryScreen
	screen.in_match = true
	screen.left.connect(func() -> void: _left = true)
	layer.add_child(screen)
	await _hold(0.3, 3)

	await _talk()                                   # Hanna, step 1
	_check(state.count("malthouse_key") == 1, "step 1 hands over the Steeping Tank key")
	_press(_machine(screen, "Grain Mill"))          # not lit: refused
	await _hold(0.3, 2)
	_check(screen._status.text.begins_with("Not yet"), "an unlit machine is refused: " + screen._status.text)

	_press(_machine(screen, "Steeping Tank"))
	await _play_game(true)
	_check(BreweryBook.stock("malt", state) == 1, "one malt")

	await _talk()                                   # Hanna skips the middle
	_check(BreweryBook.stock("barrel", state) == 1, "Hanna's barrel")
	_press(_machine(screen, "Bottling Machine"))
	await _play_game(false)
	_check(state.count("small_bottle") == 6, "six small bottles in the bag (%d)" % state.count("small_bottle"))

	await _talk()                                   # back to the pitch
	await _hold(0.2, 2)
	_check(_left, "the Brewery left on its own (goto:back)")
	print("[tour] %s" % ("THE TUTORIAL BREWERY WORKS WHEN PRESSED." if _trouble == 0 else "%d PROBLEM(S)." % _trouble))
	quit(0 if _trouble == 0 else 1)


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
	print("[tour] %d line(s) clicked through." % shots)
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
	print("[tour] %s: %s." % [game.title, game.kind()])
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
	print("[tour] %s %s" % ["ok " if ok else "! ", what])
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
	root.get_texture().get_image().save_png("user://brewery_tour/frame_%03d.png" % _frame)
	_frame += 1
