class_name PlayerCardUI
extends Control

signal card_hovered(data: PlayerData)
signal card_unhovered(data: PlayerData)
signal card_selected(data: PlayerData)

var current_data: PlayerData

## True while AUTO is playing for you. A locked card cannot be clicked and
## is drawn faded, so it is obvious the game is choosing rather than you.
var locked: bool = false

@onready var name_label: Label = $Panel/NameLabel
@onready var artwork: TextureRect = $Panel/Artwork
@onready var stats_label: Label = $Panel/StatsLabel
@onready var interact_button: Button = $Panel/InteractButton


func _ready() -> void:
	# Connect the invisible button's built-in signals to our custom logic
	interact_button.mouse_entered.connect(_on_mouse_entered)
	interact_button.mouse_exited.connect(_on_mouse_exited)
	interact_button.pressed.connect(_on_pressed)
	_apply_lock()


## Called by main_scene whenever AUTO is switched on or off, and once when
## the card is created. Safe to call before _ready(): _apply_lock() checks.
func set_locked(is_locked: bool) -> void:
	locked = is_locked
	_apply_lock()


func _apply_lock() -> void:
	if interact_button == null:
		return
	interact_button.disabled = locked
	# MOUSE_FILTER_IGNORE as well as disabled, so a locked card does not eat
	# the hover either — the stats panel should not follow a card you cannot
	# choose.
	interact_button.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked \
		else Control.MOUSE_FILTER_STOP
	modulate = Color(1, 1, 1, 0.45) if locked else Color(1, 1, 1, 1)


func setup_card(data: PlayerData) -> void:
	current_data = data
	name_label.text = data.player_name
	stats_label.text = "T: %s | P: %d" % [data.tier, data.base_power_left]
	
	if data.artwork:
		# Automatically slice the 12x39 spritesheet to show only the first frame
		var atlas = AtlasTexture.new()
		atlas.atlas = data.artwork
		# Frame size is 128x64 based on your 1536x2496 sheet
		atlas.region = Rect2(0, 0, 128, 64) 
		artwork.texture = atlas


func _on_mouse_entered() -> void:
	if current_data:
		card_hovered.emit(current_data)


func _on_mouse_exited() -> void:
	if current_data:
		card_unhovered.emit(current_data)


func _on_pressed() -> void:
	if current_data:
		card_selected.emit(current_data)
