class_name SettingsScreen
extends Control

# =============================================================
#  SETTINGS
#
#  Five tabs, which is what a Godot game is expected to have:
#
#      KEYS        every action in Keys.csv, and the key it is on. Click one
#                  and press a new key.
#      SCREEN      window mode, resolution, vsync, frame cap
#      SOUND       master, music, effects, voice
#      COLOUR      colour-blind palettes, high contrast, text size
#      CONTROLLER  on or off, stick deadzone, vibration, and what each
#                  button does
#
#  ============ NOTHING ON THIS SCREEN IS TYPED INTO THIS FILE ============
#
#  The keys come from res://data/Keys.csv. Add a row and it appears here,
#  under whatever heading its Group column names — no code. The rest is
#  game_settings.gd, which is also where a new setting would go.
#
#  Everything is saved the moment you change it, into user://settings.json.
#  There is no Apply button because there is nothing to apply: if it looks
#  wrong, change it back and it changes back.
# =============================================================

const TABS: Array[String] = ["Keys", "Screen", "Sound", "Colour", "Controller"]

var settings: Dictionary = {}

var _tab: String = "Keys"
var _tab_buttons: Dictionary = {}
var _body: VBoxContainer
var _note: Label

## The action waiting for a key press, or "" when nothing is.
var _listening: String = ""


func _ready() -> void:
	MenuEscape.install(self)
	GameKeys.install(get_tree())
	settings = GameSettings.load_all()
	_build()
	_show_tab("Keys")


# =============================================================
#  LAYOUT
# =============================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = MenuSupport.COLOUR_BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

	page.add_child(MenuSupport.heading("SETTINGS", 34, MenuSupport.COLOUR_ACCENT))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	page.add_child(tabs)

	for name_text in TABS:
		var button := MenuSupport.icon_button(
			_tab_icon(name_text), name_text, Vector2(210, 52))
		button.pressed.connect(_show_tab.bind(name_text))
		tabs.add_child(button)
		_tab_buttons[name_text] = button

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	page.add_child(footer)

	var back := MenuSupport.icon_button("back|←", "Back", Vector2(170, 54))
	back.pressed.connect(func() -> void:
		ScenePaths.go_back(get_tree(), ScenePaths.MAIN_MENU))
	footer.add_child(back)

	_note = Label.new()
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_size_override("font_size", 14)
	_note.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	footer.add_child(_note)

	var where := Label.new()
	where.text = "Saved in %s" % ProjectSettings.globalize_path(GameSettings.SAVE_PATH)
	where.add_theme_font_size_override("font_size", 11)
	where.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	footer.add_child(where)


func _tab_icon(name_text: String) -> String:
	match name_text:
		"Keys":        return "keys|⌨"
		"Screen":      return "screen|▭"
		"Sound":       return "sound|♪"
		"Colour":      return "colour|◐"
		"Controller":  return "controller|✛"
	return "◇"


func _show_tab(name_text: String) -> void:
	_tab = name_text
	_listening = ""
	for key in _tab_buttons.keys():
		var button := _tab_buttons[key] as Button
		var lit := String(key) == name_text
		button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
			MenuSupport.COLOUR_SLOT_EMPTY if lit else MenuSupport.COLOUR_PANEL,
			MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM))
	_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()

	match _tab:
		"Keys":        _build_keys()
		"Screen":      _build_screen()
		"Sound":       _build_sound()
		"Colour":      _build_colour()
		"Controller":  _build_controller()


# =============================================================
#  KEYS
# =============================================================

func _build_keys() -> void:
	_body.add_child(_hint(
		"Click a key and press the one you want instead. A key that is already doing another job is refused, and it tells you which."))

	for group in GameKeys.groups():
		_body.add_child(MenuSupport.heading(group.to_upper(), 16, MenuSupport.COLOUR_ACCENT))
		for action in GameKeys.in_group(group):
			_body.add_child(_key_row(action))

	var reset := MenuSupport.icon_button("↺", "Put every key back", Vector2(280, 50))
	reset.pressed.connect(func() -> void:
		GameKeys.reset_all(get_tree())
		_say("Every key is back to what Keys.csv says.")
		_rebuild())
	_body.add_child(reset)


func _key_row(action: String) -> Control:
	var row := _row()

	var label := Label.new()
	label.text = GameKeys.describe(action)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	var entry: Dictionary = GameKeys.actions.get(action, {})
	var pad_text := String(entry.get("button", ""))
	if pad_text != "":
		var pad := Label.new()
		pad.text = "controller: %s" % pad_text
		pad.custom_minimum_size = Vector2(200, 0)
		pad.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pad.add_theme_font_size_override("font_size", 13)
		pad.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		row.add_child(pad)

	var button := MenuSupport.icon_button("⌨", GameKeys.label_for(action), Vector2(220, 46))
	button.tooltip_text = String(entry.get("notes", ""))
	button.pressed.connect(func() -> void:
		_listening = action
		_say("Press the key you want for '%s'." % GameKeys.describe(action))
		_rebuild())
	if _listening == action:
		button.add_theme_stylebox_override("normal",
			MenuSupport.panel_style(MenuSupport.COLOUR_LOCKED, MenuSupport.COLOUR_ACCENT))
	row.add_child(button)

	return row


## While a key row is listening, the next key press is the new binding.
## `_input` rather than `_unhandled_input` so the button under the mouse does
## not eat it first.
func _input(event: InputEvent) -> void:
	if _listening == "":
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	get_viewport().set_input_as_handled()
	var action := _listening
	_listening = ""

	var trouble := GameKeys.rebind(get_tree(), action, key)
	if trouble != "":
		_say(trouble)
	else:
		_say("'%s' is now %s." % [GameKeys.describe(action), GameKeys.label_for(action)])
	_rebuild()


# =============================================================
#  SCREEN
# =============================================================

func _build_screen() -> void:
	_body.add_child(_hint(
		"A change happens as you click it. If the window ends up somewhere you cannot see, press Escape twice to quit and delete settings.json."))

	_body.add_child(_choice_row("Window", "screen_mode",
		GameSettings.SCREEN_MODES))
	_body.add_child(_choice_row("Size", "resolution",
		GameSettings.RESOLUTIONS))
	_body.add_child(_switch_row("Vsync", "vsync",
		"On stops the picture tearing. Off lets the frame rate run free."))
	_body.add_child(_choice_row("Frame cap", "max_fps",
		[0, 30, 60, 120, 144, 240], "Uncapped"))


# =============================================================
#  SOUND
# =============================================================

func _build_sound() -> void:
	_body.add_child(_hint(
		"Every sound in the game is a row in Audio.csv and plays on one of these four buses. Sliding one to nothing mutes that bus."))

	_body.add_child(_slider_row("Everything", "volume_master"))
	_body.add_child(_slider_row("Music", "volume_music"))
	_body.add_child(_slider_row("Effects", "volume_sfx"))
	_body.add_child(_slider_row("Voices", "volume_voice"))


# =============================================================
#  COLOUR
# =============================================================

func _build_colour() -> void:
	_body.add_child(_hint(
		"The tier colours are the ones that matter: Tier II and Tier III are a green and an amber by default, which is the pair red-green colour blindness merges. Pick a palette and every screen in the game changes with it."))

	_body.add_child(_choice_row("Palette", "palette", GameSettings.PALETTES))
	_body.add_child(_swatches())
	_body.add_child(_choice_row("Text size", "text_scale",
		[0.9, 1.0, 1.15, 1.3, 1.5]))


## The four tier colours as they currently stand, so a palette can be judged
## by looking rather than by reading its name.
func _swatches() -> Control:
	var row := _row()

	var label := Label.new()
	label.text = "The four tiers"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	for i in 4:
		var tier := TierLadder.TIERS[i] if i < TierLadder.TIERS.size() else str(i)
		var chip := Label.new()
		chip.text = "Tier %s" % tier
		chip.custom_minimum_size = Vector2(110, 44)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_theme_color_override("font_color", Color(0.06, 0.06, 0.08))
		chip.add_theme_font_size_override("font_size", 15)
		var style := MenuSupport.panel_style(MenuSupport.TIER_COLOURS[i])
		chip.add_theme_stylebox_override("normal", style)
		var holder := PanelContainer.new()
		holder.add_theme_stylebox_override("panel", style)
		holder.add_child(chip)
		row.add_child(holder)

	return row


# =============================================================
#  CONTROLLER
# =============================================================

func _build_controller() -> void:
	var pads := Input.get_connected_joypads()
	var found := "No controller is plugged in right now."
	if not pads.is_empty():
		found = "Found: %s" % Input.get_joy_name(pads[0])
	_body.add_child(_hint(found + "  The buttons below come from the Default Button column of Keys.csv, so changing what a button does is a spreadsheet edit."))

	_body.add_child(_switch_row("Use a controller", "pad_enabled",
		"Off ignores every pad, which is what you want if a stick is drifting."))
	_body.add_child(_choice_row("Stick deadzone", "pad_deadzone",
		[0.1, 0.15, 0.2, 0.3, 0.4]))
	_body.add_child(_switch_row("Vibration", "pad_vibration", ""))

	_body.add_child(MenuSupport.heading("WHAT EACH BUTTON DOES", 16,
		MenuSupport.COLOUR_ACCENT))
	for action in GameKeys.order:
		var entry: Dictionary = GameKeys.actions[action]
		var pad_text := String(entry.get("button", ""))
		if pad_text == "":
			continue
		var row := _row()
		var name_label := Label.new()
		name_label.text = pad_text
		name_label.custom_minimum_size = Vector2(200, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		row.add_child(name_label)

		var does := Label.new()
		does.text = GameKeys.describe(action)
		does.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		does.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		does.add_theme_font_size_override("font_size", 15)
		does.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		row.add_child(does)
		_body.add_child(row)


# =============================================================
#  THE THREE KINDS OF ROW
#
#  Everything above is built from these, so a new setting is one line
#  wherever it belongs and no new layout code.
# =============================================================

func _row() -> HBoxContainer:
	var frame := HBoxContainer.new()
	frame.add_theme_constant_override("separation", 10)
	frame.custom_minimum_size = Vector2(0, 52)
	return frame


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label


## A row of buttons where exactly one is lit. Works for words and for
## numbers, which is why `choices` is an untyped Array.
func _choice_row(label_text: String, key: String, choices: Array,
		zero_word: String = "") -> Control:
	var row := _row()

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	var now: Variant = settings.get(key, choices[0])
	for choice in choices:
		var shown := GameSettings.pretty(str(choice))
		if zero_word != "" and str(choice) == "0":
			shown = zero_word
		var button := Button.new()
		button.text = shown
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		var lit := str(now) == str(choice)
		button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
			MenuSupport.COLOUR_SLOT_EMPTY if lit else MenuSupport.COLOUR_PANEL,
			MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM))
		button.add_theme_stylebox_override("hover",
			MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
		button.pressed.connect(func() -> void:
			settings = GameSettings.put(get_tree(), key, choice)
			_say("%s: %s" % [label_text, shown])
			# A NEW PALETTE REPAINTS EVERYTHING, including the bits of this
			# screen that were drawn before you changed it — so the screen is
			# rebuilt from scratch rather than half-repainted.
			if key == "palette":
				ScenePaths.go_to(get_tree(), ScenePaths.SETTINGS, false)
				return
			_rebuild())
		row.add_child(button)

	return row


func _switch_row(label_text: String, key: String, note: String) -> Control:
	var row := _row()

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	var on := bool(settings.get(key, true))
	var button := MenuSupport.icon_button("✓" if on else "✕",
		"On" if on else "Off", Vector2(180, 44))
	button.pressed.connect(func() -> void:
		settings = GameSettings.put(get_tree(), key, not on)
		_say("%s: %s" % [label_text, "on" if not on else "off"])
		_rebuild())
	row.add_child(button)

	var hint := Label.new()
	hint.text = note
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	row.add_child(hint)

	return row


func _slider_row(label_text: String, key: String) -> Control:
	var row := _row()

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	var readout := Label.new()
	readout.custom_minimum_size = Vector2(90, 0)
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.add_theme_font_size_override("font_size", 16)
	readout.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(settings.get(key, 0.8))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 30)
	readout.text = "%d%%" % roundi(slider.value * 100.0)
	# Applied as you drag, so you hear it rather than guess at it.
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = "%d%%" % roundi(value * 100.0)
		settings = GameSettings.put(get_tree(), key, value))
	row.add_child(slider)
	row.add_child(readout)

	return row


func _say(text: String) -> void:
	if _note != null:
		_note.text = text
