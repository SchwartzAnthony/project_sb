class_name SlotScreen
extends Control

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

const TILE := Vector2(300.0, 200.0)

var state: GameState
var _wiping: int = -1
var _list: HBoxContainer
var _detail: Label


func _ready() -> void:
	MenuEscape.install(self)
	_build()
	_fill()


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
		14, MenuSupport.COLOUR_TEXT_DIM))

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

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 6)
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
	line.add_theme_font_size_override("font_size", 15)
	line.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if used else MenuSupport.COLOUR_TEXT_DIM)
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	# `played_at`, not `when` — see the note in save_slots.gd. `when` is a
	# Godot keyword and naming a variable that is a parse error.
	if String(about["played_at"]) != "":
		var stamp := Label.new()
		stamp.text = "last played  " + String(about["played_at"])
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stamp.add_theme_font_size_override("font_size", 11)
		stamp.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(stamp)

	button.pressed.connect(_play.bind(slot))
	frame.add_child(button)

	# ERASING ASKS TWICE. There is no undo, so the first press only arms it.
	if used:
		var wipe := MenuSupport.icon_button("✕",
			"Press again to erase" if _wiping == slot else "Erase",
			Vector2(TILE.x, 40))
		if _wiping == slot:
			wipe.add_theme_stylebox_override("normal", MenuSupport.panel_style(
				MenuSupport.COLOUR_LOCKED, Color(0.92, 0.45, 0.42)))
		wipe.pressed.connect(func() -> void:
			if _wiping != slot:
				_wiping = slot
				_detail.text = "Erasing slot %d cannot be undone. Press it again to be sure." % slot
				_fill()
				return
			SaveSlots.erase(slot)
			_wiping = -1
			_detail.text = "Slot %d is empty." % slot
			_fill())
		frame.add_child(wipe)

	return frame


func _play(slot: int) -> void:
	SaveSlots.choose(get_tree(), slot)
	ScenePaths.go_to(get_tree(), ScenePaths.BASE)
