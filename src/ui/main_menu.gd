# =============================================================
#  MAIN MENU — CSV-driven menu system
#
#  Loads menu button configuration from MenuConfig.csv, displays them,
#  and routes actions (start game, settings, quit). Fully customizable
#  via CSV and PNG art files — no code changes needed.
#
#  RUN THIS: godot --path . res://main_menu.tscn
# =============================================================

extends CanvasLayer

const MENU_CONFIG_PATH := "res://data/MenuConfig.csv"
const MENU_BUTTON_SCENE := preload("res://src/ui/menu_button.tscn")
const MAIN_MATCH_SCENE := "res://src/formations/main_scene.tscn"

@export var background_art_path: String = ""  # res://assets/menu/background.png
@export var title_text: String = "AUTOBATTLER"
@export var title_font_size: int = 80

var db: CardDatabase = null
var background_sprite: Sprite2D = null
var title_label: Label = null
var buttons_container: Control = null


func _ready() -> void:
	db = CardDatabase.get_db()

	# Create background
	if background_art_path != "":
		_setup_background()
	else:
		_setup_default_background()

	# Create title
	_setup_title()

	# Create buttons container
	buttons_container = Control.new()
	buttons_container.name = "ButtonsContainer"
	buttons_container.anchor_right = 1.0
	buttons_container.anchor_bottom = 1.0
	add_child(buttons_container)

	# Load menu buttons from CSV
	_load_menu_buttons()


func _setup_default_background() -> void:
	# Simple gradient background
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)


func _setup_background() -> void:
	var art = load(background_art_path)
	if art is Texture2D:
		background_sprite = Sprite2D.new()
		background_sprite.texture = art
		background_sprite.centered = true
		background_sprite.global_position = get_viewport_rect().get_center()

		# Scale to fit viewport
		var vp_size = get_viewport_rect().size
		var tex_size = art.get_size()
		var scale_x = vp_size.x / tex_size.x
		var scale_y = vp_size.y / tex_size.y
		var scale_factor = maxf(scale_x, scale_y)
		background_sprite.scale = Vector2(scale_factor, scale_factor)

		add_child(background_sprite)
		move_child(background_sprite, 0)


func _setup_title() -> void:
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = title_text
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", title_font_size)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	title_label.add_theme_constant_override("outline_size", 4)

	# Position at top-center
	title_label.anchor_left = 0.5
	title_label.anchor_top = 0.0
	title_label.offset_left = -200.0
	title_label.offset_right = 200.0
	title_label.offset_top = 40.0
	title_label.offset_bottom = 120.0

	add_child(title_label)


func _load_menu_buttons() -> void:
	# Try to load MenuConfig.csv. If it doesn't exist, create default buttons.
	var config = _load_menu_config()
	if config.is_empty():
		_create_default_buttons()
		return

	# Create a button for each row
	for row in config:
		var button = MENU_BUTTON_SCENE.instantiate()
		if button == null:
			push_error("menu_button.tscn did not instantiate.")
			continue

		button.button_id = row.get("Button ID", "")
		button.label_text = row.get("Label", "Button")
		button.action = row.get("Action", "")
		button.art_path = row.get("Art Path", "")

		var x = float(row.get("X", 640))
		var y = float(row.get("Y", 400))
		var w = float(row.get("Width", 200))
		var h = float(row.get("Height", 80))
		button.set_size_and_pos(x - w/2, y - h/2, w, h)

		button.pressed.connect(_on_button_pressed.bind(row.get("Action", "")))
		buttons_container.add_child(button)


func _create_default_buttons() -> void:
	# Fallback buttons if MenuConfig.csv is missing
	var start_btn = _create_simple_button("START_GAME", "Start Game", 640, 450, 200, 80, "start_game")
	var settings_btn = _create_simple_button("SETTINGS", "Settings", 640, 570, 200, 80, "open_settings")
	var quit_btn = _create_simple_button("QUIT", "Quit", 640, 690, 200, 80, "quit_game")

	buttons_container.add_child(start_btn)
	buttons_container.add_child(settings_btn)
	buttons_container.add_child(quit_btn)


func _create_simple_button(id: String, label: String, x: float, y: float, w: float, h: float, action: String):
	var scene = MENU_BUTTON_SCENE.instantiate()
	scene.button_id = id
	scene.label_text = label
	scene.action = action
	scene.set_size_and_pos(x - w/2, y - h/2, w, h)
	scene.pressed.connect(_on_button_pressed.bind(action))
	return scene


func _load_menu_config() -> Array:
	# Parse MenuConfig.csv and return array of rows (dictionaries)
	var file = FileAccess.open(MENU_CONFIG_PATH, FileAccess.READ)
	if file == null:
		print("[menu] MenuConfig.csv not found at %s — using default buttons." % MENU_CONFIG_PATH)
		return []

	var rows: Array = []
	var headers: Array[String] = []
	var line_num = 0

	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		line_num += 1

		if line == "" or line.begins_with("#"):
			continue

		# Parse CSV (simple comma-split, no quote handling)
		var parts = line.split(",")
		for i in range(parts.size()):
			parts[i] = String(parts[i]).strip_edges()

		if headers.is_empty():
			headers = parts
			continue

		# Convert row to dictionary
		var row: Dictionary = {}
		for i in range(mini(headers.size(), parts.size())):
			row[headers[i]] = parts[i]
		rows.append(row)

	print("[menu] Loaded %d menu buttons from MenuConfig.csv." % rows.size())
	return rows


func _on_button_pressed(action: String) -> void:
	match action:
		"start_game":
			_start_game()
		"open_settings":
			_open_settings()
		"quit_game":
			_quit_game()
		_:
			print("[menu] Unknown action: %s" % action)


func _start_game() -> void:
	print("[menu] Starting new match...")
	get_tree().change_scene_to_file(MAIN_MATCH_SCENE)


func _open_settings() -> void:
	print("[menu] Settings not yet implemented.")
	# TODO: Create a settings scene


func _quit_game() -> void:
	print("[menu] Quitting...")
	get_tree().quit()
