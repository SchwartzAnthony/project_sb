class_name SlotScreen
extends Control

## ROUND AL: loaded by path, so it works even before Godot has registered
## the new script (a fresh copy of the project).
const Look := preload("res://src/ui/screen_look.gd")

# =============================================================
#  WHICH SAVE ARE YOU PLAYING?
#
#  Start on the title screen opens this: one tile per slot, showing what is
#  in it and when it was last played. Picking one starts the game on it.
#
#  How many tiles there are is `slot_count` in Tuning.csv. Nothing else.
#
#  SLOT 1 IS YOUR EXISTING SAVE. If you have been playing this game already,
#  everything you have done is in slot 1 and is exactly where you left it —
#  see the header of save_slots.gd for why.
# =============================================================

const TILE := Vector2(320.0, 210.0)

var state: GameState
var _list: HBoxContainer
var _detail: Label


func _ready() -> void:
	MenuEscape.install(self)
	_build()
	_fill()
	# ROUND AL: the trophy room behind it and plank buttons - data/ScreenLook.csv
	Look.install(self, "slot")
	# ROUND AN: a see-through black plate behind words that sit straight on
	# the painting (text_backdrop_alpha in Tuning.csv).
	TextBackdrop.watch(self)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = MenuSupport.COLOUR_BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 40)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)

	page.add_child(MenuSupport.heading("CHOOSE A SAVE", 34, MenuSupport.COLOUR_ACCENT))
	page.add_child(MenuSupport.heading(
		"Each one is its own game — its own progress, its own teams. Your settings are shared between them.",
		18, MenuSupport.COLOUR_TEXT_DIM))

	var centre := CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(centre)

	_list = HBoxContainer.new()
	_list.add_theme_constant_override("separation", 18)
	centre.add_child(_list)

	_detail = Label.new()
	var footer := MenuSupport.footer_bar(self, func() -> void:
		ScenePaths.go_back(get_tree(), ScenePaths.MAIN_MENU))
	footer.add_child(MenuSupport.footer_gap(_detail))
	page.add_child(footer)


func _fill() -> void:
	for child in _list.get_children():
		child.queue_free()
	for slot in range(1, SaveSlots.count() + 1):
		_list.add_child(_tile(SaveSlots.describe(slot)))


func _tile(about: Dictionary) -> Control:
	var slot := int(about["slot"])
	var used := bool(about["used"])

	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 6)

	var button := MenuSupport.icon_button("save|▤", "", TILE)
	# The two-part face is right for a toolbar and wrong for a big tile, so
	# the tile builds its own contents. Everything else about it — the
	# colours, the hover, the focus box — is still the shared style.
	for child in button.get_children():
		child.queue_free()

	# ROUND AN: the words sit inside the frame, not on it. They used to fill
	# the whole tile, so "last played" was printed over the bottom border.
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := MenuSupport.tuned("save_tile_padding", 18.0)
	column.offset_left = pad
	column.offset_top = pad
	column.offset_right = -pad
	column.offset_bottom = -pad
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)

	var title := MenuSupport.heading("Slot %d" % slot, 26,
		MenuSupport.COLOUR_TEXT if used else MenuSupport.COLOUR_TEXT_DIM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var line := Label.new()
	line.text = String(about["line"])
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# One line, stepping down a size if it would not fit the tile.
	line.add_theme_font_size_override("font_size", MenuSupport._fit_font_size(line.text,
		int(MenuSupport.tuned("save_tile_text_size", 20.0)), Vector2(TILE.x - pad * 2.0 - 8.0, 999.0)))
	line.set_meta(TextScale.FITTED_META, true)
	line.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if used else MenuSupport.COLOUR_TEXT_DIM)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	# `played_at`, not `when` — see the note in save_slots.gd. `when` is a
	# Godot keyword and naming a variable that is a parse error.
	if String(about["played_at"]) != "":
		var stamp := Label.new()
		stamp.text = "last played  " + String(about["played_at"])
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stamp.add_theme_font_size_override("font_size", int(MenuSupport.tuned("save_tile_small_size", 15.0)))
		stamp.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(stamp)

	button.pressed.connect(_play.bind(slot))
	frame.add_child(button)

	# ============ ERASING IS NOT A MAIN BUTTON ============
	#
	# It used to be the second button on every filled tile, the same size as
	# PLAY and directly under it — so the destructive action sat where your
	# hand already was, and the only thing between you and losing a save was
	# pressing the same button twice.
	#
	# It is behind a cog now. The cog opens that slot's own window, the
	# window holds Delete Profile, and Delete Profile asks Yes or No. Three
	# deliberate steps, and Close gets you out at any point.
	if used:
		var cog := MenuSupport.icon_button("settings|⚙",
			Loc.text("settings", "Settings"), Vector2(TILE.x, 56))
		cog.tooltip_text = "What to do with this save, including deleting it."
		cog.pressed.connect(_open_slot_settings.bind(slot, about))
		frame.add_child(cog)

	return frame


# =============================================================
#  ONE SAVE'S OWN WINDOW
# =============================================================

## Opened by the cog on a filled tile. Everything that is about this save
## rather than about playing it lives here, which today is one thing and
## will not stay one thing.
func _open_slot_settings(slot: int, about: Dictionary) -> void:
	var window := MenuSupport.dialog(self,
		"SLOT %d" % slot, String(about.get("line", "")))
	var column: VBoxContainer = window.get_meta("column")

	var gone := MenuSupport.icon_button("✕",
		Loc.text("delete_profile", "Delete Profile"), Vector2(0, 52))
	gone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gone.add_theme_stylebox_override("normal", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, Color(0.92, 0.45, 0.42)))
	gone.pressed.connect(func() -> void:
		_confirm_delete(slot, window))
	column.add_child(gone)

	var close := MenuSupport.icon_button("↩", Loc.text("close", "Close"),
		Vector2(0, 52))
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void:
		if is_instance_valid(window):
			window.queue_free())
	column.add_child(close)


## Yes or No, and No comes back to the slot's settings window rather than
## dumping you out to the shelf — you asked to look at this save, not to
## leave it.
func _confirm_delete(slot: int, parent_window: CanvasLayer) -> void:
	var ask := MenuSupport.dialog(self,
		Loc.text("are_you_sure", "Are you sure?"),
		"Slot %d and everything in it — the teams, the unlocks, the season — is gone for good. There is no undo." % slot)
	var column: VBoxContainer = ask.get_meta("column")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	var yes := MenuSupport.icon_button("✕", Loc.text("yes", "Yes"), Vector2(0, 52))
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.add_theme_stylebox_override("normal", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL, Color(0.92, 0.45, 0.42)))
	yes.pressed.connect(func() -> void:
		SaveSlots.erase(slot)
		print("[slots] Slot %d erased." % slot)
		if is_instance_valid(ask):
			ask.queue_free()
		if is_instance_valid(parent_window):
			parent_window.queue_free()
		_detail.text = "Slot %d is empty." % slot
		_fill())
	row.add_child(yes)

	var no := MenuSupport.icon_button("↩", Loc.text("no", "No"), Vector2(0, 52))
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func() -> void:
		if is_instance_valid(ask):
			ask.queue_free())
	row.add_child(no)


func _play(slot: int) -> void:
	SaveSlots.choose(get_tree(), slot)
	ScenePaths.go_to(get_tree(), ScenePaths.BASE)
