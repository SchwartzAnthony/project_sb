class_name BaseScreen
extends Control

# =============================================================
#  THE BASE — your hub between matches
#
#  Everything on this screen comes from two spreadsheets:
#    res://data/Buildings.csv    what stands here
#    res://data/Visitors.csv     who is here and what they want
#
#  Nothing in this file needs editing to add either. Put a row in the CSV,
#  press F5, it is on the screen.
#
#  ART (all optional — it works with none of it)
#    res://assets/base/background.png    behind everything
#    res://assets/base/<Art>.png         a building, named in Buildings.csv
#    res://assets/portraits/<Portrait>.png   a visitor
#
#  Without art you get a labelled plaque for a building and a lettered
#  circle for a visitor, so you can lay the whole base out and play it
#  before drawing anything.
# =============================================================

const BACKGROUND_DIRS: Array[String] = ["res://assets/base/", "res://assets/backgrounds/"]
const BUILDING_DIRS: Array[String] = ["res://assets/base/", "res://assets/buildings/", "res://assets/"]
const PORTRAIT_DIRS: Array[String] = ["res://assets/portraits/", "res://assets/players/", "res://assets/"]

const BUILDING_SIZE := Vector2(190.0, 132.0)
const VISITOR_SIZE := Vector2(120.0, 150.0)

var db: CardDatabase
var base: BaseDB
var state: GameState
var steps: Progression

var _world: Control
var _detail: Label
var _footer: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	db = CardDatabase.get_db()
	base = BaseDB.get_db()
	state = GameState.fetch(get_tree())
	steps = Progression.get_rules()

	_build_chrome()
	_rebuild()

	# Anything Progression.csv wants to happen when the base is opened. This
	# is where the prologue now lives, rather than firing at launch.
	_advance_progression("base_opened")

	# Anything you unlocked since you were last here flashes up on top, with a
	# Continue button, and is then marked as seen. One frame's wait lets the
	# base finish drawing so the panel lands over a finished screen.
	await get_tree().process_frame
	_flash_new_unlocks()


# =============================================================
#  LAYOUT
# =============================================================

func _build_chrome() -> void:
	var fill := ColorRect.new()
	fill.color = MenuSupport.COLOUR_BACKGROUND
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

	var art := _find_texture("background", BACKGROUND_DIRS)
	if art != null:
		var backdrop := TextureRect.new()
		backdrop.texture = art
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.30)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# Buildings and visitors live in here, positioned by their X,Y fractions.
	_world = Control.new()
	_world.name = "World"
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)
	_world.resized.connect(_rebuild)

	var title := MenuSupport.heading("THE BASE", 34, MenuSupport.COLOUR_ACCENT)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = 40.0
	title.offset_top = 26.0
	title.offset_bottom = 74.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# The line that explains whatever you last clicked.
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 17)
	_detail.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	_detail.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_detail.offset_left = 60.0
	_detail.offset_right = -60.0
	_detail.offset_top = -118.0
	_detail.offset_bottom = -74.0
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail)

	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.offset_top = -34.0
	_footer.offset_bottom = -12.0
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer)

	_build_exits()


func _build_exits() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.offset_left = -840.0
	row.offset_top = 26.0
	row.offset_right = -30.0
	row.offset_bottom = 74.0
	row.alignment = BoxContainer.ALIGNMENT_END
	add_child(row)

	# The developer tools. `show_dev_tools` in Tuning.csv hides this button
	# before you show the game to anyone; the screen itself stays put.
	if db.tune_bool("show_dev_tools", true):
		var to_dev := _make_button("Dev", Vector2(80, 46))
		to_dev.tooltip_text = "The save inspector. Jump straight to any unlock."
		to_dev.pressed.connect(func() -> void:
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.INSPECTOR))
		row.add_child(to_dev)

	var to_board := _make_button("Unlocks", Vector2(120, 46))
	to_board.tooltip_text = "Everything you can earn, and exactly what is missing."
	to_board.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_to(get_tree(), ScenePaths.UNLOCKS))
	row.add_child(to_board)

	var to_season := _make_button("The season", Vector2(150, 46))
	to_season.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_to(get_tree(), ScenePaths.SEASON))
	row.add_child(to_season)

	var to_match := _make_button("Play a match", Vector2(190, 46))
	to_match.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_to(get_tree(), ScenePaths.CLASS_SELECT))
	row.add_child(to_match)

	var to_menu := _make_button("Main menu", Vector2(150, 46))
	to_menu.pressed.connect(func() -> void:
		state.save_to_disk()
		ScenePaths.go_to(get_tree(), ScenePaths.MAIN_MENU))
	row.add_child(to_menu)


# =============================================================
#  BUILDING THE BASE FROM THE CSVs
# =============================================================

func _rebuild() -> void:
	if _world == null:
		return
	for child in _world.get_children():
		child.queue_free()

	for entry in base.buildings_for(state):
		_world.add_child(_make_building(entry))
	for entry in base.visitors_for(state):
		_world.add_child(_make_visitor(entry))

	_refresh_footer()


## Where a 0..1 fraction lands on the actual screen, with the plaque centred
## on that point so a row of 0.5 really is the middle.
func _place(node: Control, entry: Dictionary, box: Vector2) -> void:
	var area := _world.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport_rect().size

	node.custom_minimum_size = box
	node.size = box
	node.position = Vector2(
		clampf(area.x * float(entry["x"]) - box.x * 0.5, 8.0, maxf(area.x - box.x - 8.0, 8.0)),
		clampf(area.y * float(entry["y"]) - box.y * 0.5, 78.0, maxf(area.y - box.y - 130.0, 78.0)))


func _make_building(entry: Dictionary) -> Control:
	var unlocked := bool(entry["unlocked"])
	var name_text := String(entry["name"])

	var button := Button.new()
	button.tooltip_text = String(entry["description"])
	_place(button, entry, BUILDING_SIZE)

	var edge := MenuSupport.COLOUR_ACCENT if unlocked else MenuSupport.COLOUR_SLOT_EMPTY
	var fill := MenuSupport.COLOUR_PANEL if unlocked else MenuSupport.COLOUR_BACKGROUND
	button.add_theme_stylebox_override("normal", MenuSupport.panel_style(fill, edge))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, edge))
	button.add_theme_stylebox_override("pressed",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	button.add_child(box)

	var art := _find_texture(String(entry["art"]), BUILDING_DIRS)
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.custom_minimum_size = Vector2(0, 78)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			picture.modulate = Color(0.35, 0.35, 0.40, 1.0)
		box.add_child(picture)

	var label := Label.new()
	label.text = name_text if unlocked else name_text + "  (locked)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_TEXT if unlocked else MenuSupport.COLOUR_TEXT_DIM)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)

	button.pressed.connect(_on_building.bind(entry))
	return button


func _make_visitor(entry: Dictionary) -> Control:
	var button := Button.new()
	button.tooltip_text = "Talk to %s" % entry["name"]
	_place(button, entry, VISITOR_SIZE)
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(Color(0.12, 0.13, 0.18, 0.85), MenuSupport.COLOUR_TEXT_DIM))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)

	var art := _find_texture(String(entry["portrait"]), PORTRAIT_DIRS)
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(picture)
	else:
		# No portrait drawn yet: a big initial, so the base is still playable.
		var initial := Label.new()
		initial.text = String(entry["name"]).substr(0, 1).to_upper()
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_size_override("font_size", 54)
		initial.add_theme_color_override("font_color", MenuSupport.COLOUR_ACCENT)
		initial.size_flags_vertical = Control.SIZE_EXPAND_FILL
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(initial)

	var label := Label.new()
	label.text = String(entry["name"])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)

	button.pressed.connect(_on_visitor.bind(entry))
	return button


# =============================================================
#  CLICKING
# =============================================================

func _on_building(entry: Dictionary) -> void:
	var name_text := String(entry["name"])

	if not bool(entry["unlocked"]):
		# Say WHY it is locked, in the designer's own words from the CSV.
		_detail.text = "%s is locked. %s" % [name_text,
			DialogueGrammar.describe(String(entry["requires"]))]
		return

	var description := String(entry["description"])
	_detail.text = description if description != "" else name_text

	var action := String(entry["action"])
	if action.strip_edges() == "":
		return
	_carry_out(Progression.run_actions(action, state))


func _on_visitor(entry: Dictionary) -> void:
	var scene := String(entry["story"]).strip_edges()
	if bool(entry["once"]):
		BaseDB.mark_talked(String(entry["id"]), state)

	if scene == "":
		_detail.text = "%s has nothing to say yet." % entry["name"]
		_rebuild()
		return

	state.save_to_disk()
	DialogueView.play(get_tree(), scene, ScenePaths.BASE)


## Show what is new, if anything is. Rebuilding afterwards means a building
## you just unlocked is drawn unlocked the moment you press Continue.
func _flash_new_unlocks() -> void:
	var panel := NewUnlocksPanel.show_over(self, state)
	if panel != null:
		panel.dismissed.connect(_rebuild)


func _advance_progression(trigger: String) -> void:
	if steps == null or state == null:
		return
	_carry_out(steps.fire(trigger, state))


## Do the things that needed the scene tree. Only one screen change can
## happen, so the first one wins and the rest is dropped.
func _carry_out(actions: Array[Dictionary]) -> void:
	for action in actions:
		var kind := String(action["kind"])
		var value := String(action["value"])
		match kind:
			"announce":
				_detail.text = value
			"story":
				state.save_to_disk()
				DialogueView.play(get_tree(), value, ScenePaths.BASE)
				return
			"goto":
				state.save_to_disk()
				ScenePaths.go_to(get_tree(), ScenePaths.for_name(value))
				return

	state.save_to_disk()
	_rebuild()


# =============================================================
#  CHROME HELPERS
# =============================================================

## A quiet line showing what you have earned. Handy while writing content:
## if an unlock is not appearing, this says whether the game thinks you have it.
func _refresh_footer() -> void:
	if _footer == null or state == null:
		return
	var unlocked := state.unlocked_names()
	var text := "%d building%s here" % [base.buildings.size(),
		"" if base.buildings.size() == 1 else "s"]
	if not unlocked.is_empty():
		text += "   ·   unlocked: " + ", ".join(unlocked)
	if not base.problems.is_empty():
		text += "   ⚠ %d problem%s in Buildings.csv / Visitors.csv — see the Output panel" % [
			base.problems.size(), "" if base.problems.size() == 1 else "s"]
		_footer.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
	_footer.text = text


func _make_button(label: String, box: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = box
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	return button


func _find_texture(file_name: String, dirs: Array[String]) -> Texture2D:
	var clean := file_name.strip_edges()
	if clean == "":
		return null
	for folder in dirs:
		for candidate in [folder + clean, folder + clean + ".png"]:
			if ResourceLoader.exists(candidate):
				var res := load(candidate)
				if res is Texture2D:
					return res as Texture2D
	return null
