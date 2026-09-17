class_name PauseMenu
extends CanvasLayer

# =============================================================
#  ESCAPE — pause at any moment
#
#  Speed, AUTO, and a way out. It stops the whole game, not just the match:
#  the clock, the players, the ball, the cut-aways and every timer.
#
#  ------------------------------------------------------------
#  QUITTING LOSES THE MATCH, AND MEANS IT
#
#  You are warned once, and the second press puts your save back exactly as
#  it was at kick-off. Goals counted, unlocks earned, achievements ticked
#  during this match are all undone.
#
#  That is not extra bookkeeping — the match already photographs your save
#  at kick-off so the "what you gained" panel can work out the difference.
#  Quitting simply pastes that photograph back. See match_report.gd.
#  ------------------------------------------------------------
#
#  It is built in code rather than from a .tscn because it is an overlay
#  that appears on top of whatever is already running, and there is only one
#  of it — the same rule the "new at the base" flash follows. Full screens
#  come from a .tscn; overlays do not.
# =============================================================

signal resumed
signal quit_requested

## AUTO was toggled from here rather than from the HUD. The match listens so
## it can lock or unlock your cards, and so the HUD's button matches.
signal auto_pick_changed(is_on: bool)

const NODE_NAME := "PauseMenu"

var db: CardDatabase
var state: GameState

var _panel: VBoxContainer
var _warning: Label
var _quit_button: Button
var _quit_armed: bool = false
var _steps: Array[float] = []
var _speed_buttons: Array[Button] = []
## The line under the speed row that says why a locked one did nothing.
var _note: Label
var _auto_button: Button


static func make(database: CardDatabase, save: GameState) -> PauseMenu:
	var menu := PauseMenu.new()
	menu.name = NODE_NAME
	menu.db = database
	menu.state = save
	return menu


func _ready() -> void:
	# The whole point: this keeps working while everything else is stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	hide()
	_build()


# =============================================================
#  OPENING AND CLOSING
# =============================================================

func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	_quit_armed = false
	_refresh()
	show()
	get_tree().paused = true


func close() -> void:
	hide()
	get_tree().paused = false
	resumed.emit()


func is_open() -> bool:
	return visible


## The pause key opens and closes it. `_input` rather than
## `_unhandled_input` because a Button under the mouse would otherwise
## swallow it.
##
## It asks GameKeys about the ACTION rather than about Escape, so rebinding
## pause in Settings > Keys moves this too — and so does plugging in a
## controller, where Start does the same job.
func _input(event: InputEvent) -> void:
	if GameKeys.pressed(event, "pause"):
		toggle()
		get_viewport().set_input_as_handled()


# =============================================================
#  BUILDING IT
# =============================================================

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(420, 0)
	frame.add_theme_stylebox_override("panel",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	centre.add_child(frame)

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 26)
	for side2 in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side2, 22)
	frame.add_child(pad)

	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 12)
	pad.add_child(_panel)

	var title := MenuSupport.heading("PAUSED", 34, MenuSupport.COLOUR_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(title)

	_panel.add_child(_quiet("Escape closes this again."))

	# --- speed ---
	_panel.add_child(_section("SPEED"))
	var speed_row := HBoxContainer.new()
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_row.add_theme_constant_override("separation", 6)
	_panel.add_child(speed_row)

	# ============ THE SAME LOCK AS THE HUD ============
	#
	# This screen used to hand out 4x and 8x freely while the strip in the
	# corner had them greyed — which does not read as a half-finished feature,
	# it reads as the lock being decoration. The rule is GameSpeed's, and both
	# sets of buttons ask it.
	_steps = GameSpeed.steps(db)
	for value in _steps:
		var button := _make_button(GameSpeed.label_for(value), Vector2(62, 34))
		var locked := GameSpeed.step_locked(value, db, state)
		button.set_meta("locked", locked)
		button.tooltip_text = GameSpeed.locked_words(db) if locked \
			else "Run the game at %s" % GameSpeed.label_for(value)
		button.pressed.connect(func() -> void:
			# NOT `disabled`: a disabled button swallows the click and so
			# cannot tell you why nothing happened.
			if GameSpeed.step_locked(value, db, state):
				_note.text = GameSpeed.locked_words(db)
				return
			_note.text = ""
			GameSpeed.set_speed(value)
			_refresh())
		speed_row.add_child(button)
		_speed_buttons.append(button)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 13)
	_note.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
	_panel.add_child(_note)

	# --- auto ---
	_panel.add_child(_section("WATCHING"))
	_auto_button = _make_button("AUTO", Vector2(0, 40))
	_auto_button.tooltip_text = "The game picks your cards, your throw and attack-or-defend.\nYour clicks lock while it is on."
	_auto_button.pressed.connect(func() -> void:
		var now := not MatchHUD.auto_pick_on(state)
		MatchHUD.set_auto_pick(state, now)
		state.save_to_disk()
		_refresh()
		# Tell the match, so the cards and clash buttons lock or unlock and
		# the HUD's own AUTO button agrees with this one. Without this, AUTO
		# switched on from the pause menu left everything still clickable.
		auto_pick_changed.emit(now))
	_panel.add_child(_auto_button)

	# --- out ---
	_panel.add_child(_section("LEAVE"))

	var resume := _make_button("Resume", Vector2(0, 44))
	resume.pressed.connect(close)
	_panel.add_child(resume)

	_quit_button = _make_button("Quit this match", Vector2(0, 44))
	_quit_button.pressed.connect(_on_quit)
	_panel.add_child(_quit_button)

	_warning = _quiet("")
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_warning)


# =============================================================
#  QUITTING
# =============================================================

func _on_quit() -> void:
	# Two presses. There is no undo, and the first press has to say so.
	if not _quit_armed:
		_quit_armed = true
		_quit_button.text = "Press again to quit"
		_quit_button.add_theme_color_override("font_color", Color(0.95, 0.45, 0.42))
		_warning.text = "You lose everything this match gave you — goals, unlocks and achievement progress all go back to how they were at kick-off."
		_warning.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
		return

	get_tree().paused = false
	hide()
	quit_requested.emit()


# =============================================================
#  SHOWING WHAT IS ON
# =============================================================

func _refresh() -> void:
	for i in _speed_buttons.size():
		var button := _speed_buttons[i]
		if bool(button.get_meta("locked", false)):
			_paint_locked(button)
			continue
		_paint(button, is_equal_approx(_steps[i], GameSpeed.current()))

	if _auto_button != null:
		var on := MatchHUD.auto_pick_on(state)
		_auto_button.text = "AUTO is ON — sit back and watch" if on else "AUTO is off"
		_paint(_auto_button, on)

	if _quit_button != null and not _quit_armed:
		_quit_button.text = "Quit this match"
		_quit_button.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
		_warning.text = ""


## A locked speed keeps its box and its label and goes grey and half-faded,
## so it reads as "later" rather than as "broken".
func _paint_locked(button: Button) -> void:
	button.modulate = Color(1, 1, 1, 0.45)
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)


func _paint(button: Button, lit: bool) -> void:
	button.modulate = Color(1, 1, 1, 1)
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
		MenuSupport.COLOUR_SLOT_EMPTY if lit else MenuSupport.COLOUR_PANEL,
		MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT)


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label


func _quiet(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label


func _make_button(text: String, box: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = box
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	return button
