class_name ZoneOverlay
extends Node2D

# =============================================================
#  QUARTER TINT — the four Tier zones, painted faintly on the grass
#
#  The whole point of the zones is that a player can learn them by watching.
#  That only works if they can SEE them, so each quarter gets a wash of its
#  Tier's colour and a line down the boundary.
#
#  It brightens while you are choosing cards and fades back once play
#  restarts, so it is loud exactly when it is useful and nearly invisible the
#  rest of the time.
#
#  DRAW ORDER: this must be added to the scene AFTER the field sprite and
#  BEFORE the units container. All three sit at z_index 0, so it is tree
#  order that puts the tint over the grass and under the players.
# =============================================================

const TIERS: Array[String] = ["I", "II", "III", "IV"]

## Resting opacity. 0 turns the tint off entirely.
var alpha: float = 0.07
## Opacity while a draft is open.
var alpha_focus: float = 0.20
## How quickly it moves between the two, in alpha per second.
var fade_speed: float = 1.6
## Opacity of the line down each boundary, relative to the fill.
var edge_boost: float = 3.2

var zones: PitchZones = null

var _target: float = 0.07
var _current: float = 0.07


func _ready() -> void:
	z_index = 0
	_current = alpha
	_target = alpha


func setup(pitch_zones: PitchZones, rest: float, focus: float) -> void:
	zones = pitch_zones
	alpha = rest
	alpha_focus = focus
	_current = rest
	_target = rest
	queue_redraw()


## Called when a draft opens or closes.
func set_focused(focused: bool) -> void:
	_target = alpha_focus if focused else alpha


func _process(delta: float) -> void:
	if is_equal_approx(_current, _target):
		return
	_current = move_toward(_current, _target, fade_speed * delta)
	queue_redraw()


func _draw() -> void:
	if zones == null or _current <= 0.001 or zones.play.size.x <= 1.0:
		return

	for tier in TIERS:
		# Only the home side's index is drawn: the four quarters are the same
		# four rectangles whichever way round the teams are standing.
		var zone := zones.zone_for(tier, false)
		var colour := MenuSupport.colour_for_tier(tier)

		var fill := colour
		fill.a = _current
		draw_rect(zone, fill, true)

		var edge := colour
		edge.a = minf(_current * edge_boost, 0.85)
		draw_line(zone.position, Vector2(zone.position.x, zone.end.y), edge, 2.0)

	# Close the far side, which no zone's left edge covers.
	var last := zones.zone_for(TIERS[TIERS.size() - 1], false)
	var closing := MenuSupport.colour_for_tier(TIERS[TIERS.size() - 1])
	closing.a = minf(_current * edge_boost, 0.85)
	draw_line(Vector2(last.end.x, last.position.y), last.end, closing, 2.0)
