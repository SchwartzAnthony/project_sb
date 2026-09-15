class_name MenuEscape
extends CanvasLayer

# =============================================================
#  ESCAPE — one key, one meaning, everywhere
#
#  You asked for two things that sound like one:
#
#      IN A MATCH        Escape opens the sub menu (pause, speed, AUTO, quit
#                        the match). That is pause_menu.gd and it already
#                        works — this file does not touch it.
#
#      EVERYWHERE ELSE   Escape ends the game.
#
#  "Everywhere else" is the main menu, the base, the team shelf, the builder,
#  the bounty board, the season table — every screen that is not a live match.
#  Rather than each of those screens growing its own copy of the key handler,
#  each one says ONE LINE in _ready():
#
#      MenuEscape.install(self)
#
#  and this file does the rest.
#
#  ------------------------------------------------------------
#  IT ASKS FIRST
#
#  Escape is a key people hit by accident, and closing the game without
#  warning loses whatever is on screen. So the first press puts up a small
#  panel; the second press (or the button) actually quits. Escape again while
#  the panel is up is what confirms, so a double-tap of Escape is a quit and
#  a single tap is never a surprise.
#
#  Set  escape_quits_instantly  to  true  in Tuning.csv if you would rather it
#  close on the first press with no panel at all.
#
#  ------------------------------------------------------------
#  IT SAVES ON THE WAY OUT
#
#  Quitting from here writes your save first, so nothing earned since the
#  last screen change is lost. The teams you have built are already on disk
#  the moment you press LOCK IN, so those are never at risk either.
# =============================================================

const NODE_NAME := "MenuEscape"

var _panel: Control
var _armed: bool = false


## Put the Escape handler on a screen. Safe to call twice — the second call
## does nothing, so a screen that is reloaded does not end up with two.
static func install(on: Node) -> MenuEscape:
	if on == null:
		return null
	for child in on.get_children():
		if child is MenuEscape:
			return child as MenuEscape
	var made := MenuEscape.new()
	made.name = NODE_NAME
	on.add_child(made)

	# ONE LINE ON EVERY SCREEN DOES THREE JOBS. As well as the Escape key,
	# installing this is what puts the player's settings into effect and
	# builds the key bindings from Keys.csv — both of which only do their
	# work once per run. A screen you add later gets all three for free.
	# Keys first: the settings apply step sets the controller deadzone on
	# every action there is, and there are no actions until the keys are
	# registered.
	var tree := on.get_tree()
	GameKeys.install(tree)
	GameSettings.apply(tree)
	return made


func _ready() -> void:
	# Above ordinary screen content, below the pause menu (layer 200) so that
	# if both ever exist at once the match's own menu wins.
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## True while a match's pause menu is in the tree. When it is, Escape belongs
## to that menu and this file keeps its hands off — which is the whole rule:
## in a match Escape is the sub menu, outside a match Escape is the way out.
func _match_is_running() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("pause_menu"):
		if is_instance_valid(node):
			return true
	# Not every build puts the pause menu in a group, so look by type too.
	return _find_pause(tree.root) != null


func _find_pause(node: Node) -> Node:
	if node is PauseMenu:
		return node
	for child in node.get_children():
		var hit := _find_pause(child)
		if hit != null:
			return hit
	return null


## _input rather than _unhandled_input: a Button sitting under the mouse
## swallows keys before they ever reach the unhandled pass.
func _input(event: InputEvent) -> void:
	# THE PAUSE ACTION, not the Escape key. It is Escape out of the box, and
	# it is whatever the player rebound it to in Settings > Keys after that.
	if not GameKeys.pressed(event, "pause"):
		return
	if _match_is_running():
		return

	get_viewport().set_input_as_handled()

	if _armed or CardDatabase.get_db().tune_bool("escape_quits_instantly", false):
		_quit()
		return

	_armed = true
	_panel.show()


func _quit() -> void:
	var state := GameState.fetch(get_tree())
	if state != null:
		state.save_to_disk()
	print("[quit] Closing the game from Escape.")
	get_tree().quit()


func _stand_down() -> void:
	_armed = false
	_panel.hide()


# =============================================================
#  THE LITTLE PANEL
# =============================================================

func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.hide()
	add_child(_panel)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.70)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(centre)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(440, 0)
	frame.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	centre.add_child(frame)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 22)
	frame.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)

	var title := MenuSupport.heading("QUIT THE GAME?", 30, MenuSupport.COLOUR_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var note := Label.new()
	note.text = "Your save and your teams are written to disk first. Press Escape again to quit, or carry on."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	column.add_child(note)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	var stay := MenuSupport.icon_button("↩", "Carry on", Vector2(200, 50))
	stay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stay.pressed.connect(_stand_down)
	row.add_child(stay)

	var out := MenuSupport.icon_button("✕", "Quit", Vector2(200, 50))
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.pressed.connect(_quit)
	row.add_child(out)
