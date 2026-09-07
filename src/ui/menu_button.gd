# =============================================================
#  MENU BUTTON — one interactive button on the main menu
#
#  Displays art (PNG or colored rectangle if missing), responds to click.
# =============================================================

extends Control

signal pressed(action: String)

@export var button_id: String = ""
@export var label_text: String = "Button"
@export var action: String = ""
@export var art_path: String = ""

var button: Button = null
var art_rect: ColorRect = null
var art_sprite: Sprite2D = null


func _ready() -> void:
	# Create the button
	button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(size.x, size.y)
	button.pressed.connect(_on_button_pressed)
	add_child(button)

	# Try to load art. If no art or art fails, show a placeholder colored rect.
	if art_path and art_path != "":
		var art = load(art_path)
		if art is Texture2D:
			art_sprite = Sprite2D.new()
			art_sprite.texture = art
			art_sprite.centered = true
			art_sprite.scale = Vector2(size.x / art.get_size().x, size.y / art.get_size().y)
			art_sprite.position = Vector2(size.x / 2.0, size.y / 2.0)
			add_child(art_sprite)
			button.modulate.a = 0.0  # Hide text if art is present
		else:
			_show_placeholder()
	else:
		_show_placeholder()


func _show_placeholder() -> void:
	# Fallback: colored rectangle with text
	art_rect = ColorRect.new()
	art_rect.color = Color(0.2, 0.6, 0.9, 0.8)
	art_rect.size = size
	add_child(art_rect)
	move_child(art_rect, 0)  # Behind the button


func _on_button_pressed() -> void:
	pressed.emit(action)


func set_size_and_pos(x: float, y: float, w: float, h: float) -> void:
	position = Vector2(x, y)
	size = Vector2(w, h)
	if button:
		button.custom_minimum_size = size
	if art_rect:
		art_rect.size = size
	if art_sprite:
		art_sprite.scale = Vector2(w / art_sprite.texture.get_size().x, h / art_sprite.texture.get_size().y)
		art_sprite.position = Vector2(w / 2.0, h / 2.0)
