# =============================================================
#  FIELD BOUNDS — scalable, constrained play area
#
#  Manages the play area dimensions and provides methods for:
#  - Automatic field background scaling to fit standard play area
#  - Constraining player positions within field bounds
#  - Defining safe zones for player positioning
# =============================================================

class_name FieldBounds

## Standard play area dimensions (width × height in pixels)
## This defines the "reference" field size that all art scales to.
var play_width: float = 1280.0
var play_height: float = 720.0

## Position (top-left corner) of the play area in world space
var play_position: Vector2 = Vector2.ZERO

## The field background sprite to scale
var field_sprite: Sprite2D = null


# =============================================================
#  INITIALIZATION
# =============================================================

func _init(sprite: Sprite2D, width: float = 1280.0, height: float = 720.0) -> void:
	field_sprite = sprite
	play_width = width
	play_height = height
	play_position = Vector2.ZERO
	if field_sprite != null:
		_update_field_scale()


# =============================================================
#  FIELD GEOMETRY
# =============================================================

## Get the rectangle defining the playable area
func get_play_rect() -> Rect2:
	return Rect2(play_position, Vector2(play_width, play_height))


## Get the center of the play area
func get_center() -> Vector2:
	var rect = get_play_rect()
	return rect.get_center()


## Get the x-coordinate of the horizontal centerline
func get_pitch_center_x() -> float:
	var rect = get_play_rect()
	return rect.position.x + rect.size.x / 2.0


## Get the y-coordinate of the horizontal centerline
func get_pitch_center_y() -> float:
	var rect = get_play_rect()
	return rect.position.y + rect.size.y / 2.0


# =============================================================
#  FIELD BACKGROUND SCALING
# =============================================================

## Automatically scale the field sprite to fit the play area.
## The sprite's texture will be scaled (keeping aspect ratio or distorting as needed)
## to fill the play_width × play_height rectangle.
func _update_field_scale() -> void:
	if field_sprite == null or field_sprite.texture == null:
		return

	var tex_size = field_sprite.texture.get_size()
	if tex_size.x < 1.0 or tex_size.y < 1.0:
		return

	# Scale to fit the play area (may distort if aspect ratios don't match)
	var scale_x = play_width / tex_size.x
	var scale_y = play_height / tex_size.y

	field_sprite.scale = Vector2(scale_x, scale_y)
	field_sprite.global_position = play_position + Vector2(play_width, play_height) / 2.0
	field_sprite.centered = true


## Set the play area dimensions and update field scaling
func set_play_area(width: float, height: float) -> void:
	play_width = width
	play_height = height
	_update_field_scale()


## Set the play area position in world space
func set_play_position(pos: Vector2) -> void:
	play_position = pos
	_update_field_scale()


# =============================================================
#  PLAYER POSITIONING & CONSTRAINTS
# =============================================================

## Constrain a position to stay within the play area bounds.
## Leaves a small margin so players don't stand exactly on the edge.
func constrain_to_bounds(pos: Vector2, margin: float = 16.0) -> Vector2:
	var rect = get_play_rect()
	var constrained = pos

	# Apply margin from edges
	var min_x = rect.position.x + margin
	var max_x = rect.position.x + rect.size.x - margin
	var min_y = rect.position.y + margin
	var max_y = rect.position.y + rect.size.y - margin

	constrained.x = clamp(constrained.x, min_x, max_x)
	constrained.y = clamp(constrained.y, min_y, max_y)

	return constrained


## Get a "safe zone" rectangle where players can move freely.
## Slightly smaller than the full play area to prevent edge-clipping.
func get_safe_zone(margin: float = 16.0) -> Rect2:
	var rect = get_play_rect()
	return Rect2(
		rect.position + Vector2(margin, margin),
		rect.size - Vector2(margin * 2, margin * 2)
	)


## Check if a position is within the play area bounds
func is_in_bounds(pos: Vector2, margin: float = 0.0) -> bool:
	var rect = get_play_rect()
	var expanded = rect.grow(margin)
	return expanded.has_point(pos)


## Get the closest point on the field edge for a position outside bounds
func get_closest_edge_point(pos: Vector2) -> Vector2:
	var rect = get_play_rect()
	return rect.get_closest_point(pos)


# =============================================================
#  HELPER FUNCTIONS FOR POSITIONING
# =============================================================

## Get the player's goal line (x-coordinate where their goal is)
func get_home_goal_x() -> float:
	var rect = get_play_rect()
	return rect.position.x


## Get the enemy's goal line (x-coordinate where enemy goal is)
func get_away_goal_x() -> float:
	var rect = get_play_rect()
	return rect.position.x + rect.size.x


## Get a position as a fraction of the field width/height
## Returns Vector2 with values 0.0–1.0 representing position across field
func get_normalized_position(pos: Vector2) -> Vector2:
	var rect = get_play_rect()
	return Vector2(
		(pos.x - rect.position.x) / rect.size.x,
		(pos.y - rect.position.y) / rect.size.y
	)


## Convert a normalized position (0.0–1.0) back to world space
func denormalize_position(norm_pos: Vector2) -> Vector2:
	var rect = get_play_rect()
	return Vector2(
		rect.position.x + norm_pos.x * rect.size.x,
		rect.position.y + norm_pos.y * rect.size.y
	)
