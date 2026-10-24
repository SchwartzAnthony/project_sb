extends SceneTree

# Checks one d-pad press moves the highlight ONE button, even when the
# Steam Deck sends it twice (two controllers, or d-pad + arrow key).
func _initialize() -> void:
	var screen := Control.new()
	screen.size = Vector2(1920, 1080)
	root.add_child(screen)
	var buttons: Array[Button] = []
	for i in 4:
		var b := Button.new()
		b.text = "B%d" % i
		b.position = Vector2(800, 400 + i * 80)
		b.size = Vector2(250, 64)
		screen.add_child(b)
		buttons.append(b)
	ControllerFocus.install(screen)
	await process_frame
	buttons[0].grab_focus()
	var ok := true
	# One press, arriving from two pads and as an arrow key.
	_down_pad(0); _down_pad(1); _down_key()
	await process_frame
	ok = _report("one press seen three times", buttons, 1) and ok
	# A real second press of the same button still counts.
	_down_pad(0)
	await process_frame
	ok = _report("second real press", buttons, 2) and ok
	print("PAD ECHO CHECK: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

func _report(what: String, buttons: Array[Button], want: int) -> bool:
	var at := buttons.find(root.gui_get_focus_owner())
	print("%s: highlight on B%d (want B%d)" % [what, at, want])
	return at == want

func _down_pad(device: int) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = JOY_BUTTON_DPAD_DOWN
	e.pressed = true
	root.push_input(e)
	var up := e.duplicate()
	up.pressed = false
	root.push_input(up)

func _down_key() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_DOWN
	e.pressed = true
	root.push_input(e)
