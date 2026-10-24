extends SceneTree

# Checks the controller stays on ATTACK / DEFEND while the wheel asks,
# and never walks onto the match buttons behind it (1x, EXHAUST ZONE).
func _initialize() -> void:
	var match_screen := Control.new()
	match_screen.size = Vector2(1920, 1080)
	root.add_child(match_screen)
	var speed := _button(match_screen, "1x", Vector2(20, 20))
	var exhaust := _button(match_screen, "EXHAUST ZONE", Vector2(860, 600))
	ControllerFocus.install(match_screen).start_in_middle = true
	var clash := CoinClash.make(null)
	match_screen.add_child(clash)
	await process_frame
	var ok := true
	# Hidden wheel: the match's highlight still works.
	_push(JOY_BUTTON_DPAD_DOWN)
	await process_frame
	var at := root.gui_get_focus_owner()
	print("wheel hidden: highlight on %s" % (at.text if at else "nothing"))
	ok = at == exhaust and ok
	# The wheel asks ATTACK or DEFEND (your number ticket left disabled).
	clash._running = true
	clash._my_row.visible = true
	for b in clash._my_buttons:
		b.disabled = true
	clash._random_button.visible = false
	clash._choice_row.visible = true
	clash.show()
	await process_frame
	var names: Array[String] = []
	for way in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP,
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT]:
		_push(way)
		await process_frame
		at = root.gui_get_focus_owner()
		names.append(at.text if at else "nothing")
		if at == speed or at == exhaust or not clash._choice_row.is_ancestor_of(at):
			ok = false
	print("wheel up, pushes land on: %s" % ", ".join(names))
	print("CLASH FOCUS CHECK: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

func _button(parent: Control, words: String, at: Vector2) -> Button:
	var b := Button.new()
	b.text = words
	b.position = at
	b.size = Vector2(200, 60)
	parent.add_child(b)
	return b

func _push(button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	root.push_input(e)
	var up := e.duplicate()
	up.pressed = false
	root.push_input(up)
