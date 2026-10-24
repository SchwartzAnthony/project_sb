extends SceneTree

# The Tutorial's Pub talk, clicked through with a controller whose every A
# press arrives twice (the Steam Deck: its own controller AND Steam's copy).
# It must end on the screen it was told to (here Team Select), never the
# main menu, and it must not skip lines. Each press is sent as the
# controller's A AND as the Enter key, the way the Deck sends it.
#
#      godot --headless --path . --script res://tools/story_double_press_check.gd

const SCENE := "tut-pub-arrive"


func _initialize() -> void:
	GameKeys.install(self)
	await process_frame
	DialogueView.play(self, SCENE, ScenePaths.TEAM_SELECT)
	var shown: Array[String] = []
	var ended_on := ""
	for press in 400:
		# A person reads the whole line before pressing A.
		for wait in 90:
			await process_frame
		var view := current_scene as DialogueView
		if view == null:
			ended_on = current_scene.scene_file_path if current_scene != null else ""
			if ended_on != "":
				break
			continue
		if view._line != null and not shown.has(view._line.id):
			shown.append(view._line.id)
		_press_a(0)
		_press_enter()
	# Every line is seen (none skipped by the copy) and it ends on Team Select.
	var ok := ended_on == ScenePaths.resolve(ScenePaths.TEAM_SELECT) and shown.size() == 20
	print("lines shown: %d  %s" % [shown.size(), shown])
	print("ended on: %s" % ended_on)
	print("STORY DOUBLE PRESS CHECK: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _press_a(device: int) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = JOY_BUTTON_A
	e.pressed = true
	root.push_input(e)
	var up := e.duplicate()
	up.pressed = false
	root.push_input(up)


## Steam's copy of the A button as the keyboard's Enter.
func _press_enter() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ENTER
	e.physical_keycode = KEY_ENTER
	e.pressed = true
	root.push_input(e)
	var up := e.duplicate()
	up.pressed = false
	root.push_input(up)
