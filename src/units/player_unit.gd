@tool
class_name PlayerUnit
extends Area2D

# =============================================================
#  A single card living on the pitch
# =============================================================

@onready var artwork: Sprite2D = $Artwork
@onready var name_label: Label = $NameLabel
@onready var stats_label: Label = $StatsLabel

# --- Spritesheet layout (your sheet is 12 columns x 39 rows) ---
const SHEET_HFRAMES := 12
const SHEET_VFRAMES := 39
const IDLE_FRAME := 0

# --- Movement ------------------------------------------------
var home_position: Vector2
var roam_radius: float = 40.0
var is_roaming: bool = false

@export var data: PlayerData:
	set(new_data):
		data = new_data
		if is_node_ready():
			update_display()

# --- Match state ---------------------------------------------
var is_enemy: bool = false
var is_star_player: bool = false   # set explicitly at spawn; no more resource_path guessing
var is_playmaker: bool = false     # picked during the current round
var is_exhausted: bool = false     # already used this cycle


func _ready() -> void:
	update_display()


# =============================================================
#  DISPLAY
# =============================================================

func update_display() -> void:
	if data == null:
		return

	if name_label:
		name_label.text = data.player_name
	if stats_label:
		stats_label.text = "T%s  %d/%d" % [
			data.get_tier_clean(),
			data.get_attack_power(),
			data.get_defense_power(),
		]

	_apply_artwork()


func _apply_artwork() -> void:
	if artwork == null or data == null or data.artwork == null:
		return
	# Always drive the sheet the same way, everywhere. The old
	# update_unit_data() built an AtlasTexture instead, which fought with
	# these hframes/vframes and shredded the sprite after a HOLD UP! swap.
	artwork.texture = data.artwork
	artwork.hframes = SHEET_HFRAMES
	artwork.vframes = SHEET_VFRAMES
	artwork.frame = IDLE_FRAME
	artwork.flip_h = is_enemy


## Swap this unit to a different card (used by the HOLD UP! star rotation).
func update_unit_data(new_data: PlayerData) -> void:
	data = new_data          # setter calls update_display() once ready
	if is_node_ready():
		update_display()


func set_highlight(is_highlighted: bool) -> void:
	if artwork == null:
		return
	# Stay bright while locked in as this round's playmaker.
	if is_highlighted or is_playmaker:
		artwork.modulate = Color(1.2, 1.2, 1.2, 1.0)
	elif is_exhausted:
		artwork.modulate = Color(0.25, 0.25, 0.3, 1.0)  # spent this cycle
	else:
		artwork.modulate = Color(0.4, 0.4, 0.4, 1.0)


func reset_for_new_cycle() -> void:
	is_exhausted = false
	is_playmaker = false
	set_highlight(false)


func clear_round_flags() -> void:
	is_playmaker = false
	set_highlight(false)


# =============================================================
#  ROAMING
# =============================================================

func set_home(pos: Vector2) -> void:
	position = pos
	home_position = pos
	start_roaming()


func start_roaming() -> void:
	if Engine.is_editor_hint():
		return
	is_roaming = true
	_roam_to_next_spot()


func stop_roaming() -> void:
	is_roaming = false


func return_home(duration: float = 0.35) -> void:
	# Used before a combat zoom-in so the camera frames a predictable spot.
	stop_roaming()
	var tween := create_tween()
	tween.tween_property(self, "position", home_position, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _roam_to_next_spot() -> void:
	if not is_roaming or not is_inside_tree():
		return

	var random_offset := Vector2(
		randf_range(-roam_radius, roam_radius),
		randf_range(-roam_radius, roam_radius)
	)
	var target_pos := home_position + random_offset

	var tween := create_tween()
	var duration := randf_range(2.0, 4.0)
	tween.tween_property(self, "position", target_pos, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(randf_range(1.0, 3.0))
	tween.tween_callback(_roam_to_next_spot)
