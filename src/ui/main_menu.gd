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
## ROUND AI: what the title screen LOOKS like - the wallpaper, the title and
## any pictures standing on it (the hero) - one row each. See _look().
const MAIN_MENU_PATH := "res://data/MainMenu.csv"

## Optional full-screen art. Set it here, or add a Background Art row to
## MenuConfig.csv with the path in the Art Path column.
@export var background_art_path: String = "res://assets/menu/background.png"
@export var title_text: String = "Bockball"
@export var title_font_size: int = 72

var db: CardDatabase
## Flags, counters and unlocks, shared with the match and the story screen.
var state: GameState
var steps: Progression
var _buttons: Control
var _footer: Label


func _ready() -> void:
	db = CardDatabase.get_db()

	# FIRST: is every file where it should be? A script in the wrong folder
	# shows up as a dozen "not declared in the current scope" errors that
	# never name the file, so this names it. See install_check.gd.
	InstallCheck.run(get_tree())

	# Then one consolidated report of everything the CSVs got wrong, printed
	# once. See content_report.gd — it also catches mistakes no single file
	# can see, like a condition testing a counter nothing ever fills in.
	ContentReport.print_report()

	state = GameState.fetch(get_tree())
	steps = Progression.get_rules()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuEscape.install(self)

	_read_look()
	_build_background()
	_build_pictures()
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

	var path := background_art_path
	if not _look_rows.get("background", {}).is_empty():
		path = String(_look_rows["background"].get("image", path))
	if path == "" or not ResourceLoader.exists(path):
		return
	var texture := load(path)
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
	var row: Dictionary = _look_rows.get("title", {})
	if not row.is_empty():
		if String(row["text"]) != "":
			title.text = String(row["text"])
		if float(row["height"]) > 0.0:
			title_font_size = int(row["height"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", title_font_size)
	title.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 8)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var top := 70.0
	if not row.is_empty() and float(row["y"]) > 0.0:
		top = float(row["y"]) - float(title_font_size) * 0.5
	title.offset_top = top
	title.offset_bottom = top + float(title_font_size) + 20.0
	# ROUND AL: X places the title's centre (like a picture). Width is the
	# box it is centred in; blank = 1200. With no X it stays centred on screen.
	if not row.is_empty() and float(row["x"]) != 960.0:
		var box := float(row["width"]) if float(row["width"]) > 0.0 else 1200.0
		title.set_anchors_preset(Control.PRESET_TOP_LEFT)
		title.position = Vector2(float(row["x"]) - box * 0.5, top)
		title.size = Vector2(box, float(title_font_size) + 20.0)
	var gold := MenuSupport.COLOUR_ACCENT
	if not row.is_empty():
		title.add_theme_color_override("font_color", gold)
		title.add_theme_constant_override("outline_size", 14)
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
#  THE LOOK, FROM data/MainMenu.csv  (round AI)
#
#  One row per thing on the title screen:
#
#    Part     background   the wallpaper (the first one wins)
#             title        the big word at the top (Text; Height = font size)
#             picture      anything standing on it - the hero. Any number.
#    Image    the file. A picture may be a STRIP: Frames pictures side by
#             side, all the same width, played at FPS frames a second.
#    Text     for the title
#    X, Y     the CENTRE, in a 1920 x 1080 screen
#    Width, Height   how big to draw it (a picture keeps its pixels sharp)
#    Frames, FPS     for an animated strip; blank = a still picture
#
#  No file, no row: the screen looks as it did before the file existed.
# -------------------------------------------------------------

var _look_rows: Dictionary = {}
var _pictures: Array[Dictionary] = []


func _read_look() -> void:
	_look_rows = {}
	_pictures = []
	for row in MenuSupport.read_csv(MAIN_MENU_PATH):
		var part := MenuSupport.field(row, "Part").strip_edges().to_lower()
		if part == "":
			continue
		var entry := {
			"image": MenuSupport.field(row, "Image").strip_edges(),
			"text": MenuSupport.field(row, "Text").strip_edges(),
			"x": MenuSupport.field_float(row, "X", 960.0),
			"y": MenuSupport.field_float(row, "Y", 0.0),
			"width": MenuSupport.field_float(row, "Width", 0.0),
			"height": MenuSupport.field_float(row, "Height", 0.0),
			"frames": maxi(1, int(MenuSupport.field_float(row, "Frames", 1.0))),
			"fps": MenuSupport.field_float(row, "FPS", 8.0),
		}
		match part:
			"background", "title":
				if not _look_rows.has(part):
					_look_rows[part] = entry
			"picture":
				_pictures.append(entry)
			_:
				print("[menu] MainMenu.csv: Part '%s' is not background, title or picture - skipping it." % part)


func _build_pictures() -> void:
	for entry in _pictures:
		var path := String(entry["image"])
		if path == "" or not ResourceLoader.exists(path):
			print("[menu] MainMenu.csv: no picture at '%s' yet." % path)
			continue
		var sheet := load(path) as Texture2D
		if sheet == null:
			continue
		var frames := int(entry["frames"])
		var frame_w := float(sheet.get_width()) / float(frames)
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0, 0, frame_w, sheet.get_height())
		var art := TextureRect.new()
		art.texture = atlas
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := float(entry["width"]) if float(entry["width"]) > 0.0 else frame_w
		var h := float(entry["height"]) if float(entry["height"]) > 0.0 else float(sheet.get_height())
		art.size = Vector2(w, h)
		art.position = Vector2(float(entry["x"]) - w * 0.5, float(entry["y"]) - h * 0.5)
		add_child(art)
		if frames > 1 and float(entry["fps"]) > 0.0:
			var timer := Timer.new()
			timer.wait_time = 1.0 / float(entry["fps"])
			timer.autostart = true
			var at := {"frame": 0}
			timer.timeout.connect(func() -> void:
				at["frame"] = (int(at["frame"]) + 1) % frames
				atlas.region = Rect2(frame_w * int(at["frame"]), 0, frame_w, sheet.get_height()))
			art.add_child(timer)


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
			Vector2(width, height),
			MenuSupport.field(row, "Label On Art").strip_edges().to_lower() == "yes")
		button.position = Vector2(centre_x - width * 0.5, centre_y - height * 0.5)
		# ROUND AI: each button's sounds are MenuConfig.csv columns - a row
		# ID of Audio.csv or a file name in assets/audio/. Blank = the
		# usual tick and click.
		var hover_sound := MenuSupport.field(row, "Hover Sound", "menu_hover").strip_edges()
		var press_sound := MenuSupport.field(row, "Press Sound", "menu_click").strip_edges()
		button.mouse_entered.connect(func() -> void: AudioDirector.play_cue(get_tree(), hover_sound))
		button.focus_entered.connect(func() -> void: AudioDirector.play_cue(get_tree(), hover_sound))
		button.pressed.connect(func() -> void: AudioDirector.play_cue(get_tree(), press_sound))
		button.pressed.connect(_on_action.bind(action))
		_buttons.add_child(button)


## The four buttons the title screen falls back to when MenuConfig.csv cannot
## be read. They are the same four the CSV ships with, so a missing file
## changes how the buttons LOOK and not what the game can do.
func _default_rows() -> Array[Dictionary]:
	return [
		{"label": "Start", "x": "640", "y": "380", "width": "260", "height": "68",
			"action": "goto:base", "artpath": ""},
		{"label": "Settings", "x": "640", "y": "464", "width": "260", "height": "68",
			"action": "open_settings", "artpath": ""},
		{"label": "Tutorial", "x": "640", "y": "548", "width": "260", "height": "68",
			"action": "tutorial_game", "artpath": ""},
		{"label": "Quit", "x": "640", "y": "632", "width": "260", "height": "68",
			"action": "quit_game", "artpath": ""},
	]


## A button that wears a PNG when one is given and falls back to a plain
## labelled button when it is not — so the menu works before any art exists.
func _make_button(label: String, art_path: String, box: Vector2, label_on_art: bool = false) -> Button:
	var button := Button.new()
	button.size = box
	button.custom_minimum_size = box
	button.text = label
	button.add_theme_font_size_override("font_size", 22)

	# ROUND AL: "Label On Art" yes = the picture is a blank plank and the
	# Label is written on top of it, so one plank serves every button.
	if label_on_art and art_path != "" and ResourceLoader.exists(art_path):
		var plank := load(art_path) as Texture2D
		if plank != null:
			var states := {"normal": Color(1, 1, 1), "hover": Color(1.18, 1.12, 1.0),
				"pressed": Color(0.82, 0.78, 0.72), "focus": Color(1.18, 1.12, 1.0)}
			for state in states:
				var box_style := StyleBoxTexture.new()
				box_style.texture = plank
				# The plank is made at the button's own shape (Pixelate.csv
				# Widen), so it is simply drawn over the whole button.
				box_style.modulate_color = states[state]
				button.add_theme_stylebox_override(state, box_style)
			button.add_theme_font_size_override("font_size", 26)
			button.add_theme_color_override("font_color", Color("f6ead0"))
			button.add_theme_color_override("font_hover_color", Color("ffd36a"))
			button.add_theme_color_override("font_focus_color", Color("ffd36a"))
			button.add_theme_color_override("font_pressed_color", Color("e8d7b0"))
			button.add_theme_color_override("font_outline_color", Color("2a1608"))
			button.add_theme_constant_override("outline_size", 7)
			button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			return button
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
			# START ASKS WHICH SAVE FIRST, then opens the base. With
			# slot_count set to 1 in Tuning.csv the slot screen still works
			# and simply has one tile on it, so a single-save game is a
			# spreadsheet setting rather than a different code path.
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.SLOTS)
		"quick_match":
			# A QUICK MATCH IS ITS OWN KIND OF MATCH, not a shortcut to the
			# usual one: no clock, one Star, and nothing written to the season
			# table. What it is exactly comes from MatchModes.csv, so its shape
			# can change without touching this file.
			MatchMode.choose(get_tree(), "quick")
			ScenePaths.go_to(get_tree(), ScenePaths.TEAM_SELECT)
		"match":
			# ONE ACTION FOR EVERY MODE YOU EVER ADD. A button whose Action is
			# match:cup starts the `cup` row of MatchModes.csv. No new code.
			MatchMode.choose(get_tree(), argument if argument != "" else "season")
			ScenePaths.go_to(get_tree(), ScenePaths.TEAM_SELECT)
		"tutorial_game", "tutorial":
			# THE TUTORIAL BASE. A small enclosed base of its own, with its own
			# buildings, its own visitors and its own save — nothing you do in
			# there touches the real game. See tutorial_base.gd.
			state.save_to_disk()
			TutorialBase.enter(get_tree(), argument)
		"story":
			DialogueView.play(get_tree(),
				argument if argument != "" else "main", ScenePaths.MAIN_MENU)
		"goto":
			# One action word for every screen. MenuConfig.csv can say
			# goto:base, goto:builder, goto:match — no new code per button.
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.for_name(argument))
		"open_settings", "settings":
			state.save_to_disk()
			ScenePaths.go_to(get_tree(), ScenePaths.SETTINGS)
		"quit_game":
			get_tree().quit()
		_:
			push_warning("[menu] MenuConfig.csv asks for unknown action '%s'." % action)
			_footer.text = "Unknown action '%s' — check MenuConfig.csv." % action
