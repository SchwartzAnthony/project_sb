class_name SaveInspector
extends Control

# =============================================================
#  THE SAVE INSPECTOR — a developer tool
#
#  Everything the game remembers about you, on one page, with buttons to
#  change it. It exists for one reason: so that testing a Progression row
#  that fires after ten matches does not mean playing ten matches.
#
#  THE ROW THAT MATTERS IS THE TOP ONE — "JUMP STRAIGHT TO".
#  One button per locked thing in the game. Press it and the save is moved
#  to exactly the state where you have it: counters set to their targets,
#  flags switched, unlocks granted. Testing "what happens when the Brewery
#  opens" becomes one click.
#
#  It satisfies each requirement DIRECTLY rather than earning it, so
#  granting the Pub does not silently play five matches for you. That is
#  what you want from a test tool, and it is worth knowing when a number
#  looks lower than you expected afterwards.
#
#  ------------------------------------------------------------
#  IS THIS SAFE TO SHIP?
#  Yes — it changes nothing on its own, and it is only reachable from a
#  button. To hide it before showing the game to anyone, set
#  `show_dev_tools` to false in Tuning.csv and the button at the base
#  disappears. The screen itself stays in the project.
#  ------------------------------------------------------------
#
#  THE NODES IT FILLS  (same template pattern — open the .tscn and move
#  them about, just do not rename them)
#    %Title  %Summary
#    %JumpHeading   %JumpList        <- buttons are ADDED here
#    %CountersHeading  %CountersList <- rows are ADDED here
#    %SwitchesHeading  %SwitchesList <- rows are ADDED here
#    %AddRow  %NameBox               <- the "add one by hand" row
#    %HomeButton  %WipeButton
# =============================================================

var db: CardDatabase
var state: GameState

var _title: Label
var _summary: Label
var _jump_heading: Label
var _jump_list: HFlowContainer
var _counters_heading: Label
var _counters_list: VBoxContainer
var _switches_heading: Label
var _switches_list: VBoxContainer
var _add_row: HBoxContainer
var _name_box: LineEdit
var _home: Button
var _wipe: Button

var _note: String = ""
var _wipe_armed: bool = false


func _ready() -> void:
	GameSpeed.reset()
	db = CardDatabase.get_db()
	state = GameState.fetch(get_tree())

	_title = _grab("Title") as Label
	_summary = _grab("Summary") as Label
	_jump_heading = _grab("JumpHeading") as Label
	_jump_list = _grab("JumpList") as HFlowContainer
	_counters_heading = _grab("CountersHeading") as Label
	_counters_list = _grab("CountersList") as VBoxContainer
	_switches_heading = _grab("SwitchesHeading") as Label
	_switches_list = _grab("SwitchesList") as VBoxContainer
	_add_row = _grab("AddRow") as HBoxContainer
	_name_box = _grab("NameBox") as LineEdit
	_home = _grab("HomeButton") as Button
	_wipe = _grab("WipeButton") as Button

	_build_add_row()

	if _home != null:
		_home.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_back(get_tree(), ScenePaths.BASE))

	if _wipe != null:
		_wipe.pressed.connect(_on_wipe)

	_rebuild()


func _grab(node_name: String) -> Node:
	var found := find_child(node_name, true, false)
	if found == null:
		push_warning("[save inspector] save_inspector.tscn has no node called '%s'." % node_name)
	return found


# =============================================================
#  DRAWING WHAT IS IN THE SAVE
# =============================================================

func _rebuild() -> void:
	_fill_jumps()
	_fill_counters()
	_fill_switches()

	if _summary != null:
		var base := "%d unlock(s), %d flag(s), %d counter(s), %d text(s)   -   %s" % [
			state.unlocks.size(), state.flags.size(),
			state.counters.size(), state.texts.size(),
			GameState.save_location()]
		_summary.text = base if _note == "" else "%s\n%s" % [_note, base]
		_summary.add_theme_color_override("font_color",
			MenuSupport.COLOUR_ACCENT if _note != "" else MenuSupport.COLOUR_TEXT_DIM)


## One button per locked thing in the game, closest first, so the useful ones
## are at the front. Built from the same engine as the unlock board.
func _fill_jumps() -> void:
	if _jump_list == null:
		return
	for child in _jump_list.get_children():
		child.queue_free()

	var progress := UnlockProgress.build(state)
	var open_ones := progress.nearest(db.tune_int("inspector_jump_buttons", 14))

	if open_ones.is_empty():
		var none := Label.new()
		none.text = "Nothing left to jump to - you have everything that has a requirement."
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		_jump_list.add_child(none)
	else:
		for entry in open_ones:
			var button := _small_button("%s  %d%%" % [
				entry["name"], int(round(float(entry["fraction"]) * 100.0))])
			button.tooltip_text = "%s\nStill needs: %s" % [entry["kind"], entry["missing"]]
			button.pressed.connect(_on_jump.bind(entry))
			_jump_list.add_child(button)

	if _jump_heading != null:
		_jump_heading.text = "JUMP STRAIGHT TO   (%d of %d earned so far)" % [
			progress.done_count(), progress.entries.size()]


func _fill_counters() -> void:
	if _counters_list == null:
		return
	for child in _counters_list.get_children():
		child.queue_free()

	var keys := _sorted(state.counters.keys())
	if keys.is_empty():
		_counters_list.add_child(_quiet("No counters yet. Play a match, or add one below."))
	for key in keys:
		_counters_list.add_child(_counter_row(key))

	if _counters_heading != null:
		_counters_heading.text = "COUNTERS  (%d)" % keys.size()


func _counter_row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	var label := Label.new()
	label.text = state.pretty(key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT_DIM if key.begins_with("tune") else MenuSupport.COLOUR_TEXT)
	row.add_child(label)

	var value := Label.new()
	value.text = str(state.count(key))
	value.custom_minimum_size = Vector2(52, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	row.add_child(value)

	for step in [-1, 1, 5]:
		var button := _small_button("%+d" % step, 38.0)
		button.pressed.connect(func() -> void:
			state.add_count(key, step)
			_after("%s is now %d" % [state.pretty(key), state.count(key)]))
		row.add_child(button)

	var zero := _small_button("0", 32.0)
	zero.pressed.connect(func() -> void:
		state.set_count(key, 0)
		_after("%s reset to 0" % state.pretty(key)))
	row.add_child(zero)

	return row


func _fill_switches() -> void:
	if _switches_list == null:
		return
	for child in _switches_list.get_children():
		child.queue_free()

	var unlock_keys := _sorted(state.unlocks.keys())
	for key in unlock_keys:
		_switches_list.add_child(_switch_row(String(state.unlocks[key]), true, key))

	var flag_keys := _sorted(state.flags.keys())
	var shown := 0
	for key in flag_keys:
		# The "this row already fired" bookkeeping is not interesting, and
		# there is one of them per Progression row. Leave them out.
		if key.begins_with(CardDatabase._normalise(Progression.DONE_PREFIX)):
			continue
		_switches_list.add_child(_switch_row(state.pretty(key), false, key))
		shown += 1

	if unlock_keys.is_empty() and shown == 0:
		_switches_list.add_child(_quiet("Nothing unlocked and no flags set yet."))

	if _switches_heading != null:
		_switches_heading.text = "UNLOCKS (%d) AND FLAGS (%d)" % [unlock_keys.size(), shown]


func _switch_row(shown_name: String, is_unlock: bool, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	var tag := Label.new()
	tag.text = "unlock" if is_unlock else "flag"
	tag.custom_minimum_size = Vector2(52, 0)
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	row.add_child(tag)

	var label := Label.new()
	label.text = shown_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	row.add_child(label)

	var off := _small_button("take away", 88.0)
	off.pressed.connect(func() -> void:
		if is_unlock:
			state.unlocks.erase(key)
		else:
			state.set_flag(key, false)
		_after("%s taken away" % shown_name))
	row.add_child(off)

	return row


# =============================================================
#  CHANGING THINGS
# =============================================================

func _on_jump(entry: Dictionary) -> void:
	var changed := UnlockProgress.satisfy(entry, state)
	if changed.is_empty():
		_after("%s needed nothing changed." % entry["name"])
		return
	_after("%s: %s" % [entry["name"], ", ".join(changed)])


func _build_add_row() -> void:
	if _add_row == null:
		return

	var unlock_it := _small_button("Unlock this", 110.0)
	unlock_it.pressed.connect(func() -> void:
		var text := _typed()
		if text == "":
			return
		state.unlock(text)
		_after("unlocked %s" % text))
	_add_row.add_child(unlock_it)

	var flag_it := _small_button("Set as a flag", 120.0)
	flag_it.pressed.connect(func() -> void:
		var text := _typed()
		if text == "":
			return
		state.set_flag(text, true)
		_after("flag %s is on" % text))
	_add_row.add_child(flag_it)

	for amount in [1, 5, 10]:
		var count_it := _small_button("Count = %d" % amount, 96.0)
		count_it.pressed.connect(func() -> void:
			var text := _typed()
			if text == "":
				return
			state.set_count(text, amount)
			_after("%s = %d" % [text, amount]))
		_add_row.add_child(count_it)


func _typed() -> String:
	if _name_box == null:
		return ""
	var text := _name_box.text.strip_edges()
	if text == "":
		_after("Type a name in the box first.")
	return text


func _on_wipe() -> void:
	# Two presses, because there is no undo. The button says so in between.
	if not _wipe_armed:
		_wipe_armed = true
		_wipe.text = "Press again to wipe"
		_wipe.add_theme_color_override("font_color", Color(0.95, 0.45, 0.42))
		return

	state.reset()
	state.save_to_disk()
	_wipe_armed = false
	_wipe.text = "Wipe the save"
	_wipe.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_after("The save is empty. You are back at the very beginning.")


## Save, then redraw. Everything on this screen goes through here, so nothing
## can change the save without it being written to disk.
func _after(message: String) -> void:
	_note = message
	print("[inspector] %s" % message)
	state.save_to_disk()
	if _wipe_armed:
		_wipe_armed = false
		if _wipe != null:
			_wipe.text = "Wipe the save"
			_wipe.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_rebuild()


# =============================================================
#  SMALL PIECES
# =============================================================

## Dictionary keys come out in whatever order they were inserted. An explicit
## copy-and-sort keeps the list steady between redraws, so a row does not jump
## about under the mouse after every press.
func _sorted(keys: Array) -> Array[String]:
	var out: Array[String] = []
	for key in keys:
		out.append(String(key))
	out.sort()
	return out


func _small_button(label: String, width: float = 0.0) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 28)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	return button


func _quiet(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label
