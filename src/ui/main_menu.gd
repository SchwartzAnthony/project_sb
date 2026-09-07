class_name MainMenu
extends Control

# =============================================================
#  MAIN MENU
#
#  Every button on this screen is a row in res://data/MenuConfig.csv.
#  Add a row, get a button. Point its Art Path at a PNG and the button
#  wears that art; leave it blank and you get a plain labelled button.
#  Nothing here needs a scene file editing.
#
#  If MenuConfig.csv is missing or unreadable the menu falls back to a
#  built-in Start / Quit pair, so the game always launches.
# =============================================================

const MENU_CONFIG_PATH := "res://data/MenuConfig.csv"

## Optional full-screen art. Set it here, or add a Background Art row to
## MenuConfig.csv with the path in the Art Path column.
@export var background_art_path: String = "res://assets/menu/background.png"
@export var title_text: String = "AUTOBATTLER"
@export var title_font_size: int = 72

var db: CardDatabase
## Flags, counters and unlocks, shared with the match and the story screen.
var state: GameState
var steps: Progression
var _buttons: Control
var _footer: Label


func _ready() -> void:
	db = CardDatabase.get_db()

	# One consolidated report of everything the CSVs got wrong, printed once.
	# See content_report.gd — it also catches mistakes no single file can see,
	# like a condition testing a counter nothing ever fills in.
	ContentReport.print_report()

	state = GameState.fetch(get_tree())
	steps = Progression.get_rules()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_background()
	_build_title()

	_buttons = Control.new()
	_buttons.name = "Buttons"
	_buttons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buttons)

	_build_footer()
	_build_buttons()

	# game_start fires once ever; menu_opened fires every time you land here.
	_advance_progression("game_start")
	_advance_progression("menu_opened")


## Run the Progression rows for this moment. State changes happen here;
## anything that needs a screen change is carried out below.
func _advance_progression(trigger: String) -> void:
	if steps == null or state == null:
		return
	for action in steps.fire(trigger, state):
		var kind := String(action["kind"])
		var value := String(action["value"])
		match kind:
			"announce":
				_footer.text = value
			"story":
				state.save_to_disk()
				DialogueView.play(get_tree(), value, ScenePaths.MAIN_MENU)
				return
			"goto":
				state.save_to_disk()
				ScenePaths.go_to(get_tree(), ScenePaths.for_name(value))
				return
	state.save_to_disk()


# -------------------------------------------------------------
#  BACKGROUND & CHROME
# -------------------------------------------------------------

func _build_background() -> void:
	var fill := ColorRect.new()
	fill.color = MenuSupport.COLOUR_BACKGROUND
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

	if background_art_path == "" or not ResourceLoader.exists(background_art_path):
		return
	var texture := load(background_art_path)
	if not (texture is Texture2D):
		return

	var art := TextureRect.new()
	art.texture = texture
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)


func _build_title() -> void:
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", title_font_size)
	title.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 8)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 70.0
	title.offset_bottom = 70.0 + float(title_font_size) + 20.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)


## A quiet line at the bottom telling you what the CSVs actually loaded.
## If a class is missing from the game, this is the first place to look.
func _build_footer() -> void:
	_footer = Label.new()
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.offset_top = -46.0
	_footer.offset_bottom = -14.0
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer)

	var classes := db.stars_by_class().size()
	var text := "%d cards  ·  %d class%s  ·  %d abilities" % [
		db.players.size(), classes, "" if classes == 1 else "es", db.abilities.size()]
	if not db.problems.is_empty():
		text += "   ⚠ %d CSV warning%s — see the Output panel" % [
			db.problems.size(), "" if db.problems.size() == 1 else "s"]
		_footer.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
	_footer.text = text


# -------------------------------------------------------------
#  BUTTONS FROM CSV
# -------------------------------------------------------------

func _build_buttons() -> void:
	var rows := MenuSupport.read_csv(MENU_CONFIG_PATH)
	if rows.is_empty():
		print("[menu] No usable %s — using the built-in buttons." % MENU_CONFIG_PATH)
		rows = _default_rows()

	for row in rows:
		var action := MenuSupport.field(row, "Action")
		if action == "":
			continue

		var width := MenuSupport.field_float(row, "Width", 260.0)
		var height := MenuSupport.field_float(row, "Height", 68.0)
		var centre_x := MenuSupport.field_float(row, "X", 640.0)
		var centre_y := MenuSupport.field_float(row, "Y", 420.0)

		var button := _make_button(
			MenuSupport.field(row, "Label", "Button"),
			MenuSupport.field(row, "Art Path"),
			Vector2(width, height))
		button.position = Vector2(centre_x - width * 0.5, centre_y - height * 0.5)
		button.pressed.connect(_on_action.bind(action))
		_buttons.add_child(button)


func _default_rows() -> Array[Dictionary]:
	return [
		{"label": "Start Game", "x": "640", "y": "400", "width": "260", "height": "68",
			"action": "start_game", "artpath": ""},
		{"label": "Quick Match", "x": "640", "y": "484", "width": "260", "height": "68",
			"action": "quick_match", "artpath": ""},
		{"label": "Quit", "x": "640", "y": "568", "width": "260", "height": "68",
			"action": "quit_game", "artpath": ""},
	]


## A button that wears a PNG when one is given and falls back to a plain
## labelled button when it is not — so the menu works before any art exists.
func _make_button(label: String, art_path: String, box: Vector2) -> Button:
	var button := Button.new()
	button.size = box
	button.custom_minimum_size = box
	button.text = label
	button.add_theme_font_size_override("font_size", 22)

	if art_path != "" and ResourceLoader.exists(art_path):
		var texture := load(art_path)
		if texture is Texture2D:
			button.text = ""
			button.icon = texture
			button.expand_icon = true
			button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
			button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
			button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			return button
		push_warning("[menu] '%s' is not an image — showing a text button instead." % art_path)
	elif art_path != "":
		print("[menu] No file at '%s' — showing a text button instead." % art_path)

	button.add_theme_stylebox_override("normal",
		MenuSupport.panel_style(MenuSupport.COLOUR_PANEL, MenuSupport.COLOUR_ACCENT))
	button.add_theme_stylebox_override("hover",
		MenuSupport.panel_style(MenuSupport.COLOUR_SLOT_EMPTY, MenuSupport.COLOUR_ACCENT))
	return button


# -------------------------------------------------------------
#  ACTIONS
#  Add a case here to teach the menu a new Action word.
# -------------------------------------------------------------

func _on_action(action: String) -> void:
	# An action may carry an argument after a colon, which is how one Action
	# word serves any number of buttons: story:prologue, story:chapter2 and
	# story:lorelei_intro are three buttons and no new code.
	var verb := action
	var argument := ""
	var colon := action.find(":")
	if colon > 0:
		verb = action.substr(0, colon).strip_edges()
		argument = action.substr(colon + 1).strip_edges()

	match verb.to_lower():
		"start_game":
			TeamSelection.clear(get_tree())
			ScenePaths.go_to(get_tree(), ScenePaths.CLASS_SELECT)
		"quick_match":
			# Straight to a match with a random class and roster — handy for
			# testing without walking the menus every time.
			TeamSelection.clear(get_tree())
			ScenePaths.go_to(get_tree(), ScenePaths.MATCH)
		"story":
			DialogueView.play(get_tree(),
				argument if argument != "" else "main", ScenePaths.MAIN_MENU)
		"open_settings":
			_footer.text = "Settings are not built yet."
		"quit_game":
			get_tree().quit()
		_:
			push_warning("[menu] MenuConfig.csv asks for unknown action '%s'." % action)
			_footer.text = "Unknown action '%s' — check MenuConfig.csv." % action
