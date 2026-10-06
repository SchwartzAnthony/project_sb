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

## ROUND AC: THE ZONE MAP (Z key in a match, `zones` in Keys.csv). Draws the
## quarters loud, names them for both sides, the `edge_keep` lines nobody is
## sent past, and for every unit a line to where it is heading plus its
## "don't stand still" clock (a ring that fills up; when it is full the unit
## picks a fresh spot).
var detail := false
## Who to draw lines for. main_scene hands its _all_units here.
var units_source: Callable = Callable()
var edge_keep := 0.10
var linger_seconds := 2.5

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
	if detail:
		queue_redraw()
		return
	if is_equal_approx(_current, _target):
		return
	_current = move_toward(_current, _target, fade_speed * delta)
	queue_redraw()


func _draw() -> void:
	if zones == null or zones.play.size.x <= 1.0:
		return
	if detail:
		_draw_detail()
		return
	if _current <= 0.001:
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


func _draw_detail() -> void:
	var play := zones.play
	var font := ThemeDB.fallback_font
	var away := ["IV", "III", "II", "I"]
	for i in TIERS.size():
		var tier: String = TIERS[i]
		var zone := zones.zone_for(tier, false)
		var colour := MenuSupport.colour_for_tier(tier)
		var fill := colour
		fill.a = 0.22
		draw_rect(zone, fill, true)
		var edge := colour
		edge.a = 0.9
		draw_rect(zone, edge, false, 3.0)
		var words := "YOU  Tier %s   |   THEM  Tier %s" % [tier, away[i]]
		# The last quarter is named at the BOTTOM: the Emblem tiles cover
		# its top corner.
		var at := zone.position + Vector2(12, 34)
		if i == TIERS.size() - 1:
			at = Vector2(zone.position.x + 12, zone.end.y - 44)
		# A see-through plate behind the words (TextBackdrop), or they vanish
		# into the grass stripes and the village.
		TextBackdrop.draw_behind(self, font, at, words, zone.size.x - 24.0, 24)
		TextBackdrop.draw_behind(self, font, at + Vector2(0, 28), "quarter %d" % (i + 1),
			zone.size.x - 24.0, 18)
		draw_string(font, at, words,
			HORIZONTAL_ALIGNMENT_LEFT, zone.size.x - 24.0, 24, Color(1, 1, 1, 0.95))
		draw_string(font, at + Vector2(0, 28), "quarter %d" % (i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, zone.size.x - 24.0, 18, Color(1, 1, 1, 0.7))
	# The lines a fresh spot is never past.
	if edge_keep > 0.0:
		var keep := play.size.y * edge_keep
		var line := Color(1.0, 0.85, 0.3, 0.8)
		_dashed(Vector2(play.position.x, play.position.y + keep), Vector2(play.end.x, play.position.y + keep), line)
		_dashed(Vector2(play.position.x, play.end.y - keep), Vector2(play.end.x, play.end.y - keep), line)
		TextBackdrop.draw_behind(self, font, Vector2(play.position.x + 16, play.position.y + keep - 8),
			"edge_keep - nobody is SENT past this line (they may still chase the ball over it)", -1, 18)
		draw_string(font, Vector2(play.position.x + 16, play.position.y + keep - 8),
			"edge_keep - nobody is SENT past this line (they may still chase the ball over it)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, line)
	if not units_source.is_valid():
		return
	var units: Array = units_source.call()
	for u in units:
		var unit := u as PlayerUnit
		if unit == null or not is_instance_valid(unit):
			continue
		var at := unit.global_position
		var colour := Color(0.45, 0.75, 1.0) if not unit.is_enemy else Color(1.0, 0.45, 0.45)
		if unit.has_role_target:
			var to := unit.role_target
			var c := colour
			c.a = 0.75
			draw_line(at, to, c, 2.0)
			draw_circle(to, 6.0, c)
		if unit.fresh_left > 0.0 and unit.fresh_spot != Vector2.INF:
			draw_arc(unit.fresh_spot, 14.0, 0.0, TAU, 20, Color(1, 1, 0.4, 0.9), 3.0)
		if linger_seconds > 0.0:
			var full := clampf(unit.linger_time / linger_seconds, 0.0, 1.0)
			draw_arc(at, 30.0, -PI * 0.5, -PI * 0.5 + TAU * full, 24, Color(1, 1, 1, 0.9), 4.0)


func _dashed(a: Vector2, b: Vector2, colour: Color) -> void:
	var length := a.distance_to(b)
	var step := 28.0
	var dir := (b - a).normalized()
	var t := 0.0
	while t < length:
		draw_line(a + dir * t, a + dir * minf(t + step * 0.6, length), colour, 3.0)
		t += step
