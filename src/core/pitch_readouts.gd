class_name PitchReadouts
extends Node2D

# =============================================================
#  WHAT EVERY PLAYER IS READING  (round AN, 8 Oct)
#
#  Anthony: "Maybe show me all indicators that read the ball/players on the
#  field." Part of the zone map (Z in a match, `zones` in Keys.csv), drawn
#  over the players:
#
#    THE BALL'S RANGE   the gold circle round the ball. Inside it a player
#                       may sprint; outside it nobody goes faster than
#                       far_from_ball_pace x his walk (Tuning.csv).
#    WHERE IT LANDS     the gold cross: the point defenders close on
#                       (the ball's arrival point, not where it is now).
#    THE JOB            a word under every player: BALL, PRESS, RECEIVE,
#                       DRIBBLE, SURGE (going for it - sprint, face the run)
#                       or HOLD, MARK, OPEN, RECOVER (watching it - face the
#                       ball, jog). Gold = the ball is in his range.
#    WHERE HE LOOKS     the short arrow at his feet: the way the figure faces.
#    HIS MAN            a thin line from a marker to the man he marks.
#
#  The quarters, the edge_keep lines, the line to where each player is
#  heading and the "don't stand still" ring are drawn by zone_overlay.gd.
#
#  A child of ZoneOverlay; only visible while the zone map is on.
# =============================================================

const ROLE_WORDS := ["HOLD", "MARK", "OPEN", "PRESS", "BALL", "RECEIVE", "DRIBBLE", "SURGE", "RECOVER"]
const GOLD := Color(1.0, 0.82, 0.25, 0.95)
const CALM := Color(0.85, 0.95, 1.0, 0.9)

var overlay: ZoneOverlay = null


func _draw() -> void:
	if overlay == null or not overlay.units_source.is_valid():
		return
	var font := ThemeDB.fallback_font
	var ball := overlay.ball
	var has_ball := ball != null and is_instance_valid(ball)
	if has_ball and overlay.ball_reach > 0.0:
		var at := ball.global_position
		draw_arc(to_local(at), overlay.ball_reach, 0.0, TAU, 64, Color(GOLD, 0.55), 3.0)
		var land := to_local(ball.arrival_point())
		draw_line(land + Vector2(-9, -9), land + Vector2(9, 9), GOLD, 3.0)
		draw_line(land + Vector2(-9, 9), land + Vector2(9, -9), GOLD, 3.0)
		_upright(font, to_local(at) + Vector2(0, -overlay.ball_reach), Vector2(-130, -6),
			"BALL RANGE - sprint inside, jog outside", 16, GOLD)

	var to_here := get_global_transform_with_canvas().affine_inverse()
	for u in overlay.units_source.call():
		var unit := u as PlayerUnit
		if unit == null or not is_instance_valid(unit):
			continue
		var feet := to_local(unit.global_position)
		var colour := GOLD if unit.ball_in_range else CALM
		# His man.
		if unit.role == PlayerUnit.Role.MARK and unit.mark_target != null \
				and is_instance_valid(unit.mark_target):
			draw_line(feet, to_local(unit.mark_target.global_position),
				Color(1, 1, 1, 0.35), 1.5)
		# Where he looks: the figure's own facing, turned back into the pitch.
		if unit.pitch_sheet:
			var angle := float(unit.get("_dir")) * PI / 4.0
			var squash := maxf(0.1, float(unit.call("_squash")))
			var screen := Vector2(cos(angle), sin(angle) / squash).normalized() * 30.0
			var tip := feet + to_here.basis_xform(screen)
			draw_line(feet, tip, colour, 3.0)
			draw_circle(tip, 4.0, colour)
		# The job, and whether he is going for the ball or watching it.
		var word: String = ROLE_WORDS[clampi(unit.role, 0, ROLE_WORDS.size() - 1)]
		word += "  sprint" if unit.role_speed > unit.walk_speed * 1.35 else ""
		_upright(font, feet, Vector2(-22, 14), word, 13, colour)


## Words at a point on the (tilted) pitch, drawn flat to the SCREEN at screen
## size - drawn in the pitch's own plane they come out sheared and unreadable.
## `nudge` is in screen pixels from that point.
func _upright(font: Font, at: Vector2, nudge: Vector2, words: String, size: int,
		colour: Color) -> void:
	var to_screen := get_global_transform_with_canvas()
	draw_set_transform_matrix(to_screen.affine_inverse() * Transform2D(0.0, to_screen * at))
	TextBackdrop.draw_behind(self, font, nudge, words, -1, size)
	draw_string(font, nudge, words, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)
	draw_set_transform_matrix(Transform2D.IDENTITY)
