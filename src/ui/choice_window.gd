class_name ChoiceWindow
extends CanvasLayer

# =============================================================
#  THE GAME ASKS YOU SOMETHING  (round AA)
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "They get to choose" (which unit the Rose token replaces), "ask the player
#  if they want to consume the ore", "the player still has a choice to accept
#  a transformation", and "they choose one side" of a card in the exhaust,
#  once per cycle. And from R17: "only interrupt if a player has some action
#  they could use".
#
#  So this is ONE window for all of them: a question, and a button per
#  answer. It only ever opens when there is a real choice - the ability
#  engine decides that - and never in AUTO, never for the other side.
#
#      var picked := await ChoiceWindow.ask(self, "SPEND ORE?",
#          "Erich: pay 2 Ore, then -1 to the enemy", ["Spend 2 Ore", "Keep it"])
#
#  returns the index of the button pressed (0 = the first).
#
#  `choice_window_seconds` in Tuning.csv: after this long with no answer it
#  picks the FIRST button for you, so a match left alone never hangs. 0 =
#  wait for ever.
# =============================================================

signal chosen(index: int)

var _picked := -1


static func ask(on_node: Node, title: String, body: String, options: Array[String],
		details: Array[String] = []) -> int:
	if options.is_empty():
		return -1
	var made := ChoiceWindow.new()
	made.name = "ChoiceWindow"
	made.layer = 175
	on_node.add_child(made)
	made._build(title, body, options, details)
	var db := CardDatabase.get_db()
	var wait := 0.0
	if db != null:
		wait = db.tune_float("choice_window_seconds", 0.0)
	if wait > 0.0:
		made._time_out(wait)
	var index: int = await made.chosen
	made.queue_free()
	return index


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _build(title: String, body: String, options: Array[String], details: Array[String]) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(560.0, 0.0)
	frame.add_theme_stylebox_override("panel", MenuSupport.styled(
		"window", "", MenuSupport.COLOUR_BACKGROUND, MenuSupport.COLOUR_ACCENT))
	centre.add_child(frame)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 22)
	frame.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	pad.add_child(box)

	box.add_child(MenuSupport.heading(title, 24, MenuSupport.COLOUR_ACCENT))
	var words := Label.new()
	words.text = body
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size = Vector2(516.0, 0.0)
	words.add_theme_font_size_override("font_size", 17)
	words.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	box.add_child(words)

	for i in options.size():
		var button := Button.new()
		button.text = options[i]
		button.custom_minimum_size = Vector2(516.0, 44.0)
		button.add_theme_font_size_override("font_size", 17)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_pick.bind(i))
		box.add_child(button)
		if i < details.size() and details[i].strip_edges() != "":
			var note := Label.new()
			note.text = details[i]
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(516.0, 0.0)
			note.add_theme_font_size_override("font_size", 13)
			note.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
			box.add_child(note)
		if i == 0:
			button.call_deferred("grab_focus")


func _pick(index: int) -> void:
	if _picked >= 0:
		return
	_picked = index
	chosen.emit(index)


func _time_out(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	if is_instance_valid(self):
		_pick(0)
