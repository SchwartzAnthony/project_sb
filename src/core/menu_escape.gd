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

	# ============ THE SKIN GOES ON BEFORE THE SETTINGS ============
	#
	# Theme.csv is the shipped look. The Colour tab's palettes — deuteranopia,
	# tritanopia, high contrast — are a NEED, and a need has to be able to
	# win, so GameSettings.apply() runs second and paints over anything the
	# designer's palette said about the colours it cares about.
	#
	# This also sets the real Godot theme on the root window, which is how
	# buttons laid out by hand in a .tscn — ones that never call MenuSupport
	# at all — end up wearing the skin too.
	ThemeBook.dress(tree)
	GameSettings.apply(tree)

	# CONTROLLER AND ARROW-KEY NAVIGATION, on every screen, from this one
	# line. A screen written next year gets it without knowing it exists.
	# See controller_focus.gd.
	ControllerFocus.install(on)

	# THE LANGUAGE. Loaded once per run from Language.csv; every screen then
	# reads its words through Loc.text(). See localisation.gd.
	Loc.install()

	# ============ AND THE SCREEN SAYS WHAT IT IS ============
	#
	# THE BUG THIS FIXES: "the main menu music does not start until you go
	# into the tutorial and come back."
	#
	# `screen_opened` used to be fired by ScenePaths.go_to(), which is every
	# screen change in the game EXCEPT the first one — the main menu is the
	# project's main scene and is simply there when the window opens, so it
	# never went through go_to() and never asked for its music. Walking to
	# the tutorial and back did go through go_to(), which is why that worked.
	#
	# Announcing it here instead means the screen itself says what it is, the
	# moment it is built, whichever way it was reached. Firing twice is
	# harmless: a looping cue that is already playing is left alone.
	AudioDirector.announce_screen(tree, on)
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

	# ============ A SECOND ESCAPE CLOSES THE MENU ============
	#
	# It used to QUIT THE GAME. Escape twice in a row is the most natural
	# thing in the world to do — open a menu, change your mind, press the key
	# you opened it with — and doing that shut the game down without asking
	# anything more. Escape is now the same key both ways: it opens the menu
	# and it closes it.
	#
	# `escape_quits_instantly` in Tuning.csv is for a kiosk or a demo where
	# one key should get you out; it is FALSE everywhere else.
	if _armed:
		_stand_down()
		return
	if CardDatabase.get_db().tune_bool("escape_quits_instantly", false):
		_quit()
		return

	_armed = true
	_panel.show()


## Back to the title screen, with everything written to disk first. The
## panel is stood down before the scene changes so it is not left armed on
## the screen you arrive at.
func _to_main_menu() -> void:
	var state := GameState.fetch(get_tree())
	if state != null:
		state.save_to_disk()
	_stand_down()
	print("[menu] Back to the main menu from Escape.")
	ScenePaths.go_to(get_tree(), ScenePaths.MAIN_MENU, false)


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

	var title := MenuSupport.heading("PAUSED", 30, MenuSupport.COLOUR_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var note := Label.new()
	note.text = "Your save and your teams are written to disk before you go anywhere. Escape again closes this."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	column.add_child(note)

	# ============ THERE IS A WAY BACK NOW ============
	#
	# The panel used to offer exactly two things: carry on, or shut the game
	# down. From the base that meant there was NO WAY BACK TO THE MAIN MENU
	# at all — the only exit from the game was the exit from the program.
	#
	# Three buttons, stacked rather than in a row, because "Main Menu" and
	# "Quit to Desktop" do not fit side by side at 440 wide and a button with
	# its own words cut off is worse than a taller panel.
	var back := MenuSupport.icon_button("↩", Loc.text("carry_on", "Carry on"),
		Vector2(0, 52))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_stand_down)
	column.add_child(back)

	var home := MenuSupport.icon_button("home|⌂",
		Loc.text("main_menu", "Main Menu"), Vector2(0, 52))
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.tooltip_text = "Back to the title screen. Everything is saved first."
	home.pressed.connect(_to_main_menu)
	column.add_child(home)

	var out := MenuSupport.icon_button("✕",
		Loc.text("quit_game", "Quit to Desktop"), Vector2(0, 52))
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.pressed.connect(_quit)
	column.add_child(out)
