class_name PlayerCardUI
extends Control

signal card_hovered(data: PlayerData)
signal card_unhovered(data: PlayerData)
signal card_selected(data: PlayerData)

var current_data: PlayerData

@onready var name_label: Label = $Panel/NameLabel
@onready var artwork: TextureRect = $Panel/Artwork
@onready var stats_label: Label = $Panel/StatsLabel
@onready var interact_button: Button = $Panel/InteractButton


func _ready() -> void:
	# Connect the invisible button's built-in signals to our custom logic
	interact_button.mouse_entered.connect(_on_mouse_entered)
	interact_button.mouse_exited.connect(_on_mouse_exited)
	interact_button.pressed.connect(_on_pressed)


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
