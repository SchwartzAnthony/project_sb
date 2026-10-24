class_name SlotScreen
extends Control

## ROUND AL: loaded by path, so it works even before Godot has registered
## the new script (a fresh copy of the project).
const Look := preload("res://src/ui/screen_look.gd")

# =============================================================
#  WHICH SAVE ARE YOU PLAYING?
#
#  Start on the title screen opens this: one beer mug per slot on a table
#  (19 Oct 2026). Clicking a mug opens its lid and shows Play, Profile
#  Settings and Delete. Layout and pictures: data/SaveMugs.csv.
#
#  How many tiles there are is `slot_count` in Tuning.csv. Nothing else.
#
#  SLOT 1 IS YOUR EXISTING SAVE. If you have been playing this game already,
#  everything you have done is in slot 1 and is exactly where you left it —
#  see the header of save_slots.gd for why.
# =============================================================

var state: GameState
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
	_read_mugs()

	var bg := ColorRect.new()
	bg.color = MenuSupport.COLOUR_BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 19 Oct 2026: the saves are beer mugs standing on the table (the table
	# itself is a ScreenLook.csv picture behind them).
	_table = Control.new()
	_table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_table)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 40)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(page)

	# 20 Oct 2026: the name hangs on the tavern sign (data/MenuHeader.csv).
	add_child(SignHeader.make(Loc.text("choose_a_save", "CHOOSE A SAVE")))

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(gap)

	_detail = Label.new()
	var footer := MenuSupport.footer_bar(self, func() -> void:
		ScenePaths.go_back(get_tree(), ScenePaths.MAIN_MENU))
	footer.add_child(MenuSupport.footer_gap(_detail))
	page.add_child(footer)


# =============================================================
#  THE MUGS - data/SaveMugs.csv
# =============================================================

const MUG_SHEET := "res://data/SaveMugs.csv"

var _table: Control
var _art: Dictionary = {}
var _spots: Array[Vector2] = []
## Per slot (20 Oct 2026, Anthony: 1 blue, 2 red, 3 green): the plank for its
## buttons and the colour of the coaster under its mug.
var _planks: Array[String] = []
var _coasters: Array[Color] = []
var _name_gap := 18.0
var _name_size := 22
var _name_width := 300.0
var _menu_width := 230.0
var _menu_up := 200.0
var _menu_size := 20
var _open_slot := 0


func _read_mugs() -> void:
	for row in MenuSupport.read_csv(MUG_SHEET):
		var part := MenuSupport.field(row, "Part").strip_edges().to_lower()
		match part:
			"closed_full", "open_full", "closed_empty", "open_empty":
				_art[part] = Look.picture(MenuSupport.field(row, "Image").strip_edges())
			"slot":
				_spots.append(Vector2(MenuSupport.field_float(row, "X", 960.0),
					MenuSupport.field_float(row, "Y", 900.0)))
				_planks.append(MenuSupport.field(row, "Image").strip_edges())
				_coasters.append(Color.from_string(MenuSupport.field(row, "Colour").strip_edges(), Color(0, 0, 0, 0.55)))
			"name_text":
				_name_gap = MenuSupport.field_float(row, "Y", _name_gap)
				_name_size = int(MenuSupport.field_float(row, "Size", _name_size))
			"menu":
				_menu_width = MenuSupport.field_float(row, "X", _menu_width)
				_menu_up = MenuSupport.field_float(row, "Y", _menu_up)
				_menu_size = int(MenuSupport.field_float(row, "Size", _menu_size))
	if _spots.is_empty():
		for i in range(SaveSlots.count()):
			_spots.append(Vector2(960.0 + (i - (SaveSlots.count() - 1) * 0.5) * 520.0, 900.0))


func _fill() -> void:
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	for slot in range(1, mini(SaveSlots.count(), _spots.size()) + 1):
		_table.add_child(_mug(SaveSlots.describe(slot)))


func _mug(about: Dictionary) -> Control:
	var slot := int(about["slot"])
	var used := bool(about["used"])
	var spot := _spots[slot - 1]
	var is_open := slot == _open_slot
	var key := "closed_empty"
	if used:
		key = "open_full" if is_open else "closed_full"
	elif is_open and _art.get("open_empty") != null:
		key = "open_empty"
	var texture: Texture2D = _art.get(key)

	var mug := TextureButton.new()
	mug.name = "Mug%d" % slot
	mug.texture_normal = texture
	mug.ignore_texture_size = true
	mug.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	mug.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var size := Vector2(texture.get_size()) if texture != null else Vector2(320, 420)
	mug.size = size
	mug.position = Vector2(spot.x - size.x * 0.5, spot.y - size.y)
	mug.mouse_entered.connect(func() -> void: mug.modulate = Color(1.12, 1.08, 1.0))
	mug.mouse_exited.connect(func() -> void: mug.modulate = Color(1, 1, 1))
	mug.pressed.connect(_toggle.bind(slot))

	# The save's name and matches on the table under the mug, on a see-through
	# dark backing.
	var name_line := Label.new()
	name_line.text = "Slot %d  ·  %s" % [slot, String(about["line"]).get_slice("   ·   ", 0) if used else "Empty"]
	name_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_line.add_theme_font_size_override("font_size", _name_size)
	name_line.add_theme_color_override("font_color", Color("f6ead0"))
	# The coaster under the mug, in this slot's colour with a cream edge.
	var backing := StyleBoxFlat.new()
	backing.bg_color = _coasters[slot - 1] if slot <= _coasters.size() else Color(0, 0, 0, 0.55)
	backing.set_corner_radius_all(14)
	backing.set_border_width_all(3)
	backing.border_color = Color("f6ead0")
	backing.content_margin_left = 14
	backing.content_margin_right = 14
	name_line.add_theme_stylebox_override("normal", backing)
	name_line.set_meta(TextScale.FITTED_META, true)
	name_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_line.size = Vector2(_name_width, _name_size * 2.0)
	name_line.position = Vector2((size.x - _name_width) * 0.5, size.y + _name_gap)
	mug.add_child(name_line)

	if is_open:
		mug.add_child(_choices(slot, used, mug))
	return mug


## Click a mug: it opens and shows its choices. Click it again (or another
## mug) and it closes.
func _toggle(slot: int) -> void:
	_open_slot = 0 if _open_slot == slot else slot
	_fill()
	# WITH A CONTROLLER (24 Oct 2026) the highlight goes to the open mug's
	# Play, or back to the mug when it closes. Before, it was lost when the
	# mugs were rebuilt, and the next push of the d-pad landed on the mug
	# again, so A just opened and closed it.
	var pad := get_node_or_null(ControllerFocus.NODE_NAME)
	if pad != null and bool(pad.get("_using_pad")):
		_focus_after.call_deferred(slot)


func _focus_after(slot: int) -> void:
	var mug := _table.get_node_or_null("Mug%d" % slot)
	if mug == null:
		return
	if _open_slot == slot:
		for button in mug.find_children("*", "Button", true, false):
			(button as Button).grab_focus()
			return
	(mug as Control).grab_focus()


## Play, Profile Settings and Delete on the open mug's glass, one above the
## other (Anthony: "when pressing on the mug, it opens like that"). An empty
## slot only has Play, which starts a new game there.
func _choices(slot: int, used: bool, mug: Control) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var words: Array = [["play", "Play"]]
	if used:
		words.append(["profile_settings", "Profile Settings"])
		words.append(["delete", "Delete"])
	for pair in words:
		var button := Button.new()
		button.text = Loc.text(String(pair[0]), String(pair[1]))
		button.custom_minimum_size = Vector2(_menu_width, _menu_size * 2.5)
		button.add_theme_font_size_override("font_size", _menu_size)
		column.add_child(button)
		_paint(button, slot)
		match String(pair[0]):
			"play":
				button.pressed.connect(_play.bind(slot))
			"profile_settings":
				button.pressed.connect(_profile_settings.bind(slot))
			"delete":
				button.pressed.connect(_confirm_delete.bind(slot, null))
	# Centred on the glass (the picture's middle is the middle of the glass),
	# its middle _menu_up above the mug's bottom.
	column.resized.connect(func() -> void:
		column.position = Vector2((mug.size.x - _menu_width) * 0.5, mug.size.y - _menu_up - column.size.y * 0.5))
	column.position = Vector2((mug.size.x - _menu_width) * 0.5, mug.size.y - _menu_up)
	return column


## This slot's own plank (SaveMugs.csv slot row Image) on a choice button,
## with everything else as the screen's plank row in ScreenLook.csv.
func _paint(button: Button, slot: int) -> void:
	if slot > _planks.size() or _planks[slot - 1] == "":
		return
	for row in MenuSupport.read_csv("res://data/ScreenLook.csv"):
		if MenuSupport.field(row, "Screen").strip_edges() == "slot" \
				and MenuSupport.field(row, "Part").strip_edges().to_lower() == "button":
			var own := row.duplicate()
			own[MenuSupport.normalise("Image")] = _planks[slot - 1]
			Look._dress(button, own)
			return


## This save's own settings: the Settings screen, reading and writing
## user://slotN/settings.json.
func _profile_settings(slot: int) -> void:
	GameSettings.start_profile(slot)
	GameSettings.editing_slot = slot
	ScenePaths.go_to(get_tree(), ScenePaths.SETTINGS)


# =============================================================
#  DELETING A SAVE
# =============================================================

## Yes or No. No leaves the mug open, so you are back where you were.
func _confirm_delete(slot: int, parent_window: Variant) -> void:
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
		if parent_window is CanvasLayer and is_instance_valid(parent_window):
			(parent_window as CanvasLayer).queue_free()
		_open_slot = 0
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
