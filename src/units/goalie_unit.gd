class_name GoalieUnit
extends Area2D

# =============================================================
#  GOALIE
#  Stamina is a WALL. While stamina remains, shots almost never go in.
#  Once stamina hits 0 the goal is open and the next shot almost always
#  goes in. Conceding a goal fully restores THIS goalie's stamina only.
#
#  NOTE: goalie_unit.tscn's ROOT NODE must be an Area2D. If it is a
#  Node2D, instantiate() silently returns null and no goals can ever be
#  scored. Use the corrected goalie_unit.tscn shipped alongside this file.
# =============================================================

signal goal_conceded
signal stamina_depleted
signal shot_saved(remaining_stamina: int)

@export var max_stamina: int = 40

## Chance a shot sneaks past while the goalie still has stamina.
@export_range(0.0, 1.0, 0.01) var break_through_chance: float = 0.05
## Chance a shot goes in once stamina is 0 (the goalie can still get lucky).
@export_range(0.0, 1.0, 0.01) var open_goal_chance: float = 0.90

var current_stamina: int
var is_enemy: bool = false
var data: GoalieData

# Typed as Range, not ProgressBar — TextureProgressBar and ProgressBar are
# siblings, both extending Range. Typing this as ProgressBar breaks any
# scene that uses a TextureProgressBar.
@onready var artwork: Sprite2D = get_node_or_null("Artwork")
@onready var stamina_bar: Range = get_node_or_null("StaminaBar")
@onready var name_label: Label = get_node_or_null("NameLabel")


func _ready() -> void:
	_refill()


func setup(goalie_data: GoalieData) -> void:
	data = goalie_data
	if data == null:
		return
	max_stamina = data.max_stamina
	if data.artwork != null and artwork != null:
		artwork.texture = data.artwork
	if name_label != null:
		name_label.text = data.goalie_name
	if is_node_ready():
		_refill()


func _refill() -> void:
	current_stamina = max_stamina
	if stamina_bar != null:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = current_stamina
	if artwork != null:
		artwork.modulate = Color.WHITE


# =============================================================
#  SHOT RESOLUTION — returns true if the shot was a GOAL
# =============================================================

func take_shot(shot_power: int) -> bool:
	# --- Open goal: stamina was already broken before this shot ---
	if current_stamina <= 0:
		if randf() < open_goal_chance:
			_concede()
			return true
		play_save_feedback()
		return false

	# --- Wall: chip away at the stamina first ---
	current_stamina = maxi(0, current_stamina - shot_power)
	if stamina_bar != null:
		stamina_bar.value = current_stamina

	if current_stamina == 0:
		stamina_depleted.emit()
		play_exhausted_feedback()
	else:
		play_save_feedback()

	# Small chance it still finds a way in.
	if randf() < break_through_chance:
		_concede()
		return true

	shot_saved.emit(current_stamina)
	return false


func _concede() -> void:
	goal_conceded.emit()
	print("%s conceded a goal — stamina reset to %d" % [
		"Enemy goalie" if is_enemy else "Player goalie", max_stamina
	])
	# A conceded goal resets ONLY this goalie. The other keeper is untouched.
	_refill()
	play_concede_feedback()


## Backwards-compatible alias for older call sites.
func absorb_shot(shot_power: int) -> void:
	take_shot(shot_power)


# =============================================================
#  FEEDBACK
# =============================================================

func play_save_feedback() -> void:
	if artwork == null:
		return
	var tween := create_tween()
	tween.tween_property(artwork, "modulate", Color.CYAN, 0.1)
	tween.tween_property(artwork, "modulate", _resting_colour(), 0.1)


func play_exhausted_feedback() -> void:
	if artwork == null:
		return
	artwork.modulate = Color(0.6, 0.6, 0.6, 0.8)


func play_concede_feedback() -> void:
	if artwork == null:
		return
	var tween := create_tween()
	tween.tween_property(artwork, "modulate", Color.RED, 0.15)
	tween.tween_property(artwork, "modulate", Color.WHITE, 0.35)


func _resting_colour() -> Color:
	return Color(0.6, 0.6, 0.6, 0.8) if current_stamina == 0 else Color.WHITE
