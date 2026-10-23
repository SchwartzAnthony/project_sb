class_name SettingsScreen
extends Control

## ROUND AL: loaded by path, so it works even before Godot has registered
## the new script (a fresh copy of the project).
const Look := preload("res://src/ui/screen_look.gd")

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
#  ============ ROUND AN: YOU HEAR IT AT ONCE, AND SAVE TO KEEP IT ============
#
#  Every change happens the moment you make it (drag Music and the music gets
#  quieter while you drag), but it is only written to user://settings.json
#  when you press SAVE. Leaving with changes you have not saved asks first:
#  Save, Don't save, or Stay. Tuning.csv `settings_unsaved_on_leave` can make
#  it save or throw them away without asking instead.
#
#  The key bindings and the language are the exception: they save themselves
#  the moment you change them, as they always have.
# =============================================================

const TABS: Array[String] = ["Keys", "Screen", "Sound", "Colour", "Controller", "Language"]

## What the screen shows, and what is in effect right now.
var settings: Dictionary = {}
## What is in settings.json. The difference between the two is "unsaved".
var _saved: Dictionary = {}
## setting key -> the words beside it, for the "unsaved: Music, Window" line.
var _names: Dictionary = {}
var _save_button: Button
## Set once a Save / Don't save has been decided, so the screen closing does
## not undo it.
var _settled: bool = false

var _tab: String = "Keys"
var _tab_buttons: Dictionary = {}
var _body: VBoxContainer
var _title: Label
var _note: Label

## The action waiting for a key press, or "" when nothing is.
var _listening: String = ""

## ROUND AN: OPENED ON TOP OF ANOTHER SCREEN (the Adventure's Escape menu)
## rather than as a screen of its own. Back then closes it and you are where
## you were, instead of travelling back through the screen trail.
var as_overlay: bool = false
signal closed


## Open Settings over whatever is on screen, with the game paused underneath.
## `host` is any node in the scene; the window frees itself on Back.
static func open_over(host: Node) -> SettingsScreen:
	var layer := CanvasLayer.new()
	layer.name = "SettingsOverlay"
	layer.layer = 170
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var screen := (load("res://src/ui/settings_screen.tscn") as PackedScene).instantiate() as SettingsScreen
	screen.as_overlay = true
	layer.add_child(screen)
	host.add_child(layer)
	return screen


## WHICH TAB TO OPEN ON. It rides on the SceneTree rather than living in
## this script, so that rebuilding the screen — which a palette change does,
## because every colour on it has to be redrawn — comes back to the tab you
## were on instead of dumping you back on Keys.
const TAB_KEY := "cw_settings_tab"


func _ready() -> void:
	if not as_overlay:
		MenuEscape.install(self)
	GameKeys.install(get_tree())
	_saved = GameSettings.load_all()
	settings = _saved.duplicate(true)
	# LEAVING ANY OTHER WAY (Escape > main menu, a crash out of a dialog)
	# puts the saved settings back, so what you hear always matches the file.
	tree_exiting.connect(_undo_unsaved)
	_build()
	# ROUND AL: the Beer Keller behind it and plank buttons - data/ScreenLook.csv
	Look.install(self, "settings")
	# No see-through plate behind each line any more (Anthony 20 Oct 2026:
	# the dark bars made the list hard to read); the one dark box in
	# data/ScreenLook.csv sits behind the whole page instead.
	set_meta(TextBackdrop.NO_PLATES, true)

	var opening := "Keys"
	if get_tree().has_meta(TAB_KEY):
		var remembered := String(get_tree().get_meta(TAB_KEY))
		if TABS.has(remembered):
			opening = remembered
	_show_tab(opening)
	_refresh_save()


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
	add_child(SignHeader.make(Loc.text("settings", "Settings").to_upper()))

	# ANTHONY 20 OCT 2026 (his picture of a game's settings): the tabs are a
	# list down the left with Back and Save under them, and the chosen tab's
	# settings sit in one panel on the right, one short line each.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", int(MenuSupport.tuned("settings_column_gap", 30.0)))
	margin.add_child(split)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(MenuSupport.tuned("settings_tab_width", 300.0), 0)
	split.add_child(column)

	for name_text in TABS:
		var button := MenuSupport.icon_button(
			"", name_text, Vector2(MenuSupport.tuned("settings_tab_width", 300.0), 56))
		button.pressed.connect(_show_tab.bind(name_text))
		column.add_child(button)
		_tab_buttons[name_text] = button

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(gap)

	var back := MenuSupport.icon_button("back|←", "Back", Vector2(MenuSupport.tuned("settings_tab_width", 300.0), 54))
	back.pressed.connect(_leave)
	column.add_child(back)

	_save_button = MenuSupport.icon_button("save|✓", "Save", Vector2(MenuSupport.tuned("settings_tab_width", 300.0), 54))
	_save_button.pressed.connect(_save)
	column.add_child(_save_button)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(page)

	_title = MenuSupport.heading("", _fs(24), MenuSupport.COLOUR_ACCENT)
	page.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	page.add_child(footer)

	_note = Label.new()
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_size_override("font_size", _fs(14))
	_note.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	footer.add_child(_note)



## ROUND AN: every word on this screen is `settings_text_scale` (Tuning.csv)
## times the size it was written at - "hard to read" was the note.
func _fs(written: int) -> int:
	return int(round(written * MenuSupport.tuned("settings_text_scale", 1.25)))


func _show_tab(name_text: String) -> void:
	_tab = name_text
	_listening = ""
	if get_tree() != null:
		get_tree().set_meta(TAB_KEY, name_text)
	# The chosen tab is bright, the others dimmed (the plank stays the same).
	var dim := MenuSupport.tuned("settings_tab_dim", 0.55)
	for key in _tab_buttons.keys():
		var button := _tab_buttons[key] as Button
		var lit := String(key) == name_text
		button.modulate = Color(1, 1, 1) if lit else Color(dim, dim, dim)
	if _title != null:
		_title.text = name_text.to_upper()
	_rebuild()


## Redraw the WHOLE screen — background, tabs, footer and body — keeping the
## tab you are on. Only the palette needs this; everything else changes one
## row and calls _rebuild().
##
## The children are cleared and _build() runs again, which is cheap and, more
## importantly, does not go anywhere near the window.
func _repaint() -> void:
	var was_on := _tab
	for child in get_children():
		# MenuEscape is a CanvasLayer that belongs to the screen rather than
		# to its look, and rebuilding it would install a second one.
		if child is MenuEscape:
			continue
		child.queue_free()
	_tab_buttons.clear()
	_title = null
	_body = null
	_note = null
	_save_button = null

	# The freed nodes are gone at the end of the frame, so the new ones are
	# built after that — otherwise the old chrome is still on screen
	# underneath the new chrome for one frame.
	await get_tree().process_frame
	_build()
	Look.install(self, "settings")
	_show_tab(was_on)
	_refresh_save()
	_say("Palette changed. Every screen in the game uses these colours.")


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()

	match _tab:
		"Keys":        _build_keys()
		"Screen":      _build_screen()
		"Sound":       _build_sound()
		"Colour":      _build_colour()
		"Controller":  _build_controller()
		"Language":    _build_language()


# =============================================================
#  KEYS
# =============================================================

func _build_keys() -> void:
	_body.add_child(_hint(
		"Click a key and press the one you want instead. A key that is already doing another job is refused, and it tells you which. Keys are kept the moment you change them."))

	for group in GameKeys.groups():
		_body.add_child(MenuSupport.heading(group.to_upper(), _fs(16), MenuSupport.COLOUR_ACCENT))
		for action in GameKeys.in_group(group):
			_body.add_child(_key_row(action))

	var reset := MenuSupport.icon_button("", "Put every key back", Vector2(280, 50))
	reset.pressed.connect(func() -> void:
		GameKeys.reset_all(get_tree())
		_say("Every key is back to what Keys.csv says.")
		_rebuild())
	# Its own size at the right, not pulled across the panel (Anthony 20 Oct).
	reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	_body.add_child(reset)


func _key_row(action: String) -> Control:
	var row := _row()

	var label := Label.new()
	label.text = GameKeys.describe(action)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _fs(16))
	row.add_child(label)

	# The controller button for this job is shown on the Controller tab, not
	# here (Anthony 20 Oct 2026).
	var entry: Dictionary = GameKeys.actions.get(action, {})

	var button := MenuSupport.icon_button("", GameKeys.label_for(action), Vector2(220, 46))
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
		"A change happens as you click it; press Save to keep it. If the window ends up somewhere you cannot see, press Escape twice to quit and nothing is kept."))

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
		"Every sound in the game is a row in Audio.csv and plays on one of these buses, which are the rows of SoundBuses.csv. You hear a change as you drag; press Save to keep it. Sliding one to nothing mutes that bus."))

	for row in GameSettings.bus_rows():
		_body.add_child(_slider_row(String(row["slider"]), String(row["setting"]),
			float(row["default"])))


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
	label.add_theme_font_size_override("font_size", _fs(16))
	row.add_child(label)

	for i in 4:
		var tier := TierLadder.TIERS[i] if i < TierLadder.TIERS.size() else str(i)
		var chip := Label.new()
		chip.text = "Tier %s" % tier
		chip.custom_minimum_size = Vector2(110, 44)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_theme_color_override("font_color", Color(0.06, 0.06, 0.08))
		chip.add_theme_font_size_override("font_size", _fs(15))
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
	_body.add_child(_switch_row("Vibration", "pad_vibration",
		"Goals, cards, big hits and saves shake the pad. Which ones, and how hard, is data/Rumble.csv."))

	_body.add_child(MenuSupport.heading("WHAT EACH BUTTON DOES", _fs(16),
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
		name_label.add_theme_font_size_override("font_size", _fs(16))
		name_label.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		row.add_child(name_label)

		var does := Label.new()
		does.text = GameKeys.describe(action)
		does.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		does.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		does.add_theme_font_size_override("font_size", _fs(15))
		does.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		row.add_child(does)
		_body.add_child(row)


# =============================================================
#  LANGUAGE
#
#  Every column of res://data/Language.csv that is not Key or Notes is a
#  language, so this list is that file's columns and nothing else. Add a
#  column headed Français, fill it in, and French is on this screen.
# =============================================================

func _build_language() -> void:
	_body.add_child(_hint(
		"One column per language in res://data/Language.csv. Add a column, fill it in, and it appears here — there is no list of languages anywhere in the code."))

	var row := _row()
	var label := Label.new()
	label.text = "Show the game in"
	label.custom_minimum_size = Vector2(220, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _fs(16))
	row.add_child(label)

	for language in Loc.languages():
		var lit := language == Loc.current()
		var button := MenuSupport.icon_button("", language,
			Vector2(MenuSupport.tuned("settings_value_width", 230.0), 46))
		button.add_theme_stylebox_override("normal", MenuSupport.panel_style(
			MenuSupport.COLOUR_SLOT_EMPTY if lit else MenuSupport.COLOUR_PANEL,
			MenuSupport.COLOUR_ACCENT if lit else MenuSupport.COLOUR_TEXT_DIM))
		button.pressed.connect(func() -> void:
			Loc.choose(language)
			_say("%s. Screens are written in the new language as you open them." % language)
			# THE WORDS ARE READ WHEN A SCREEN IS BUILT, so this screen is
			# rebuilt to show the change and the others pick it up when you
			# next open them. Nothing is cached anywhere else.
			_repaint())
		row.add_child(button)

	_body.add_child(row)

	_body.add_child(MenuSupport.heading("WHAT IS STILL TO TRANSLATE", _fs(16),
		MenuSupport.COLOUR_ACCENT))
	_body.add_child(_hint(
		"Play through a screen, then press the button below. Every word the game asked for that has no row yet is printed to the Output panel, already formatted to paste into the spreadsheet."))

	var listing := MenuSupport.icon_button("", "List the missing words",
		Vector2(300, 48))
	listing.pressed.connect(func() -> void:
		Loc.report()
		_say("Printed to the Output panel."))
	listing.size_flags_horizontal = Control.SIZE_SHRINK_END
	_body.add_child(listing)


# =============================================================
#  THE THREE KINDS OF ROW
#
#  Everything above is built from these, so a new setting is one line
#  wherever it belongs and no new layout code.
# =============================================================

func _row() -> HBoxContainer:
	var frame := HBoxContainer.new()
	frame.add_theme_constant_override("separation", 10)
	frame.custom_minimum_size = Vector2(0, 50)
	return frame


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", _fs(14))
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	return label


## A row of buttons where exactly one is lit. Works for words and for
## numbers, which is why `choices` is an untyped Array.
func _choice_row(label_text: String, key: String, choices: Array,
		zero_word: String = "") -> Control:
	_names[key] = label_text
	var row := _row()
	row.add_child(_name_label(label_text))

	# < value >  (Anthony 20 Oct 2026, the layout of his picture): the arrows
	# step through the same choices the row always had.
	var now: Variant = settings.get(key, choices[0])
	var at := 0
	for i in range(choices.size()):
		if str(choices[i]) == str(now):
			at = i
	var shown_of := func(choice: Variant) -> String:
		if zero_word != "" and str(choice) == "0":
			return zero_word
		return GameSettings.pretty(str(choice))

	var value := Label.new()
	value.text = shown_of.call(choices[at])
	value.custom_minimum_size = Vector2(MenuSupport.tuned("settings_value_width", 230.0), 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", _fs(16))
	value.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)

	for step in [-1, 1]:
		var button := MenuSupport.icon_button("", "<" if step < 0 else ">", Vector2(60, 44))
		var to: int = at + int(step)
		button.disabled = to < 0 or to >= choices.size()
		button.pressed.connect(func() -> void:
			var choice: Variant = choices[to]
			_change(key, choice)
			_say("%s: %s" % [label_text, shown_of.call(choice)])
			# A NEW PALETTE REPAINTS THIS SCREEN IN PLACE (it used to reload
			# the scene, which resized the window and lost your tab).
			if key == "palette":
				_repaint()
				return
			_rebuild())
		if step < 0:
			row.add_child(button)
			row.add_child(value)
		else:
			row.add_child(button)

	return row


## The setting's name on the left of its line, with room for the rest.
func _name_label(label_text: String, note: String = "") -> Control:
	var label := Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _fs(16))
	if note == "":
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return label
	# A short note under the name, in smaller words.
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	stack.add_child(label)
	var small := Label.new()
	small.text = note
	small.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	small.add_theme_font_size_override("font_size", _fs(12))
	small.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	stack.add_child(small)
	return stack


func _switch_row(label_text: String, key: String, note: String) -> Control:
	_names[key] = label_text
	var row := _row()
	row.add_child(_name_label(label_text, note))

	# On / Off side by side, the one in use bright (his picture's layout).
	var on := bool(settings.get(key, true))
	var dim := MenuSupport.tuned("settings_tab_dim", 0.55)
	for want in [true, false]:
		var button := MenuSupport.icon_button("", "On" if want else "Off", Vector2(120, 44))
		var lit: bool = want == on
		button.modulate = Color(1, 1, 1) if lit else Color(dim, dim, dim)
		button.pressed.connect(func() -> void:
			if want == on:
				return
			_change(key, want)
			_say("%s: %s" % [label_text, "on" if want else "off"])
			_rebuild())
		row.add_child(button)

	return row


func _slider_row(label_text: String, key: String, fallback: float = 0.8) -> Control:
	_names[key] = label_text
	var row := _row()

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(320, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _fs(16))
	row.add_child(label)

	var readout := Label.new()
	readout.custom_minimum_size = Vector2(90, 0)
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.add_theme_font_size_override("font_size", _fs(16))
	readout.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(settings.get(key, fallback))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 30)
	readout.text = "%d%%" % roundi(slider.value * 100.0)
	# Applied as you drag, so you hear it rather than guess at it.
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = "%d%%" % roundi(value * 100.0)
		_change(key, value))
	row.add_child(slider)
	row.add_child(readout)

	return row


func _say(text: String) -> void:
	if _note != null:
		_note.text = text


# =============================================================
#  SAVING  (round AN)
# =============================================================

## Put one change into effect without saving it.
func _change(key: String, value: Variant) -> void:
	settings[key] = value
	GameSettings.preview(get_tree(), settings, key)
	_refresh_save()


## The settings that differ from settings.json. Keys and the language are
## never in it: they save themselves.
func unsaved() -> Array[String]:
	var out: Array[String] = []
	for key in GameSettings.defaults().keys():
		if key == "keys":
			continue
		if not _same(settings.get(key), _saved.get(key)):
			out.append(String(key))
	return out


## 60 from a button and 60.0 back from the JSON file are the same setting.
static func _same(a: Variant, b: Variant) -> bool:
	var a_number := a is int or a is float
	var b_number := b is int or b is float
	if a_number and b_number:
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return false
	return a == b


func _unsaved_words() -> String:
	var words: Array[String] = []
	for key in unsaved():
		words.append(String(_names.get(key, GameSettings.pretty(key))))
	return ", ".join(words)


## The Save button is lit while there is something to save.
func _refresh_save() -> void:
	if _save_button == null:
		return
	var waiting := not unsaved().is_empty()
	_save_button.disabled = not waiting
	_save_button.tooltip_text = ("Not saved yet: " + _unsaved_words()) if waiting else "Nothing to save."


## `after` runs once the settings are written (Back's "Save" uses it).
func _save(after: Callable = Callable()) -> void:
	var keys := unsaved()
	if keys.is_empty():
		_say("Nothing to save.")
		if after.is_valid():
			after.call()
		return
	if GameSettings.editing_slot == 0 and not _used_saves().is_empty():
		_ask_which_saves(keys, after)
		return
	_write(keys, [])
	if after.is_valid():
		after.call()


## Write the General (or this save's) settings, then copy them into the
## saves picked in the "for which saves?" box.
func _write(keys: Array, saves: Array) -> void:
	_saved = GameSettings.save_some(settings, keys)
	for slot in saves:
		GameSettings.save_to_profile(int(slot), settings, keys)
	_refresh_save()
	if GameSettings.editing_slot != 0:
		_say("Saved.")
	elif saves.is_empty():
		_say(MenuSupport.tuned_text("general_settings_saved_note",
			"Saved. These General Settings are only what a new save starts with. To change a save's own settings, open it from the Save Menu."))
	else:
		_say(MenuSupport.tuned_text("general_settings_saved_to_saves",
			"Saved for new saves and for: %s.") % ", ".join(saves.map(
				func(slot: int) -> String: return "Save %d" % slot)))


## The saves that have been played (empty mugs start from General anyway).
func _used_saves() -> Array:
	var used: Array = []
	for slot in range(1, SaveSlots.count() + 1):
		if bool(SaveSlots.describe(slot).get("used", false)):
			used.append(slot)
	return used


## ANTHONY 20 OCT 2026: "Add a 'save to profile' in the general settings,
## after a player hits save or ask them if it is for all profiles."
## Saving the General Settings asks which saves they are for. They always
## become what NEW saves start with; the player can also put them into one
## save's Profile Settings, or into every save.
func _ask_which_saves(keys: Array, after: Callable) -> void:
	var used := _used_saves()
	var window := MenuSupport.dialog(self,
		MenuSupport.tuned_text("general_settings_ask_title", "SAVE FOR WHICH SAVES?"),
		MenuSupport.tuned_text("general_settings_ask_note",
			"These settings are always what a new save starts with. Put them into your saves too?"),
		520.0)
	var column: VBoxContainer = window.get_meta("column")
	var choices: Array = [[MenuSupport.tuned_text("general_settings_ask_new_only",
		"Only new saves"), []]]
	for slot in used:
		choices.append(["Save %d  (%s)" % [slot, String(SaveSlots.describe(slot).get("line", ""))], [slot]])
	if used.size() > 1:
		choices.append([MenuSupport.tuned_text("general_settings_ask_all",
			"All saves"), used])
	for choice in choices:
		var button := MenuSupport.icon_button("save|✓", String(choice[0]), Vector2(440, 50))
		var saves: Array = choice[1]
		button.pressed.connect(func() -> void:
			window.queue_free()
			_write(keys, saves)
			if after.is_valid():
				after.call())
		column.add_child(button)
	var stay := MenuSupport.icon_button("←", "Cancel", Vector2(440, 50))
	stay.pressed.connect(func() -> void:
		window.queue_free())
	column.add_child(stay)


## Put back what settings.json says, for every setting not saved.
func _undo_unsaved() -> void:
	if _settled:
		return
	_settled = true
	var keys := unsaved()
	for key in keys:
		settings[key] = _saved.get(key)
	for key in keys:
		GameSettings.preview(get_tree(), settings, key)


## Back (and the controller's B, which presses Back).
func _leave() -> void:
	var keys := unsaved()
	if keys.is_empty():
		_go()
		return

	var rule := "ask"
	var book := CardDatabase.get_db()
	if book != null:
		rule = book.tune_text("settings_unsaved_on_leave", "ask").to_lower()
	match rule:
		"save":
			_save(_go)
			return
		"discard":
			_undo_unsaved()
			_go()
			return

	var window := MenuSupport.dialog(self, "UNSAVED CHANGES",
		"You changed %s. Keep them?" % _unsaved_words())
	var column: VBoxContainer = window.get_meta("column")
	var keep := MenuSupport.icon_button("save|✓", "Save", Vector2(300, 50))
	keep.pressed.connect(func() -> void:
		window.queue_free()
		_save(_go))
	column.add_child(keep)
	var drop := MenuSupport.icon_button("✕", "Don't save", Vector2(300, 50))
	drop.pressed.connect(func() -> void:
		_undo_unsaved()
		_go())
	column.add_child(drop)
	var stay := MenuSupport.icon_button("←", "Stay here", Vector2(300, 50))
	stay.pressed.connect(func() -> void:
		window.queue_free())
	column.add_child(stay)


func _go() -> void:
	_settled = true
	# Back to the save being played, with its own settings in effect.
	if GameSettings.editing_slot >= 0:
		GameSettings.editing_slot = -1
		GameSettings.apply(get_tree(), true)
	if as_overlay:
		closed.emit()
		var layer := get_parent()
		if layer is CanvasLayer and layer.name.begins_with("SettingsOverlay"):
			layer.queue_free()
		else:
			queue_free()
		return
	ScenePaths.go_back(get_tree(), ScenePaths.MAIN_MENU)


## Escape while Settings is open over another screen is Back.
func leave() -> void:
	_leave()
