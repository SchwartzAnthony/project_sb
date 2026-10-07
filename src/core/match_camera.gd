class_name MatchCamera
extends Camera2D

# =============================================================
#  THE MATCH CAMERA — the view follows the ball
#
#  Until now the whole pitch was on screen at one size and the view never
#  moved, so every player read as a small coloured dot. This camera pushes in
#  on the ball while the game is live and pulls back out for the whistle,
#  the draft and full time.
#
#  TWO THINGS IT DELIBERATELY DOES NOT DO
#
#    1. It never changes where the players are allowed to stand. The pitch
#       geometry is captured ONCE, before this camera exists, and everything
#       else in the match keeps using that. If the camera changed the play
#       area, zooming in would squash the formations toward the ball, which
#       is exactly the bug you would spend an evening on.
#
#    2. It never zooms OUT past the ground picture, so you can never see
#       past the edge of the village (frame_rect, camera_wide_ground).
#
#  EVERY NUMBER COMES FROM Tuning.csv. Set camera_enabled to false and the
#  match plays exactly as it did before, with no camera at all.
# =============================================================

enum Mode { WIDE, PLAY, CLOSE }

## The whole pitch as it was framed at kickoff. The view is never allowed
## outside this. Set once by main_scene before the camera goes live.
var home_rect: Rect2 = Rect2()
## ROUND AN (the village ground): what the camera may SHOW, which can be
## bigger than home_rect so the wide shot takes in the village round the
## pitch. home_rect still decides where the players stand; this only decides
## the framing. Tuning.csv camera_wide_ground: 0 = the old framing, 1 = the
## whole ground picture.
var frame_rect: Rect2 = Rect2()

var wide_zoom: float = 1.0
var play_zoom: float = 1.55
var close_zoom: float = 2.10
var follow_speed: float = 3.2
var zoom_speed: float = 2.2
## How far ahead of the ball to look, as a fraction of the way to where the
## ball is going. 0 = stare at the ball, 1 = stare at where it will land.
var lead: float = 0.30
## The ball can wander this far from the middle of the screen before the
## camera bothers to move. Stops a permanent tiny jitter.
var deadzone: float = 36.0

## ROUND AN (the tilted pitch, PitchView.csv): the map from the flat match
## rectangle to the picture. Every point the match hands in is flat; the
## camera itself moves over the picture. Identity = the flat pitch.
var view_xform := Transform2D.IDENTITY
## The whole ground picture, in picture coordinates, when the pitch is tilted.
var ground_view := Rect2()
## The tilted pitch's white lines (plus the boards), as a box in the picture.
## When set, the wide shot is framed on this: corner to corner across the
## screen (Anthony: the left and right corner almost touching the edges).
var pitch_box_view := Rect2()
## home_rect and frame_rect as boxes in the picture - what zoom and clamping
## actually use.
var _home_v := Rect2()
var _frame_v := Rect2()

var _mode: int = Mode.WIDE
var _want_point: Vector2 = Vector2.ZERO
var _want_zoom: float = 1.0
var _held_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Godot's own smoothing fights ours and makes the deadzone useless.
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false
	process_callback = Camera2D.CAMERA2D_PROCESS_IDLE


## Called once, with the pitch rectangle as it looked before any camera
## existed. Everything else is read straight out of Tuning.csv.
func setup(pitch: Rect2, db: CardDatabase, ground: Rect2 = Rect2()) -> void:
	home_rect = pitch
	frame_rect = pitch
	if db != null and ground.size.x > 1.0 and ground.size.y > 1.0:
		var reach := clampf(db.tune_float("camera_wide_ground", 1.0), 0.0, 1.0)
		var wide := ground.merge(pitch)
		frame_rect = Rect2(pitch.position.lerp(wide.position, reach),
			pitch.size.lerp(wide.size, reach))
	if db != null:
		play_zoom = maxf(1.0, db.tune_float("camera_zoom", 1.55))
		close_zoom = maxf(play_zoom, db.tune_float("camera_zoom_close", 2.10))
		follow_speed = maxf(0.2, db.tune_float("camera_follow_speed", 3.2))
		zoom_speed = maxf(0.2, db.tune_float("camera_zoom_speed", 2.2))
		lead = clampf(db.tune_float("camera_lead", 0.30), 0.0, 1.0)
		deadzone = maxf(0.0, db.tune_float("camera_deadzone", 36.0))

	# ============ THE ZOOM NUMBERS ARE MULTIPLES OF THE WIDE SHOT ============
	#
	# Tuning.csv says "1 = the whole pitch", and that is the only meaning that
	# survives a change of window size. They used to be handed to the camera as
	# raw zoom, which happens to be the same thing at today's window — the
	# pitch is exactly 1920x1080, so the wide shot is exactly 1 — and stops
	# being the same thing the moment either number changes.
	#
	# On a window where the wide shot works out at, say, 1.4, a raw
	# camera_zoom of 1.55 would be a push of four per cent instead of the
	# fifty-five per cent the sheet promises, and a raw 1.2 would be a zoom
	# OUT, which is refused and so does nothing at all.
	#
	# As multiples they mean what the sheet says at every window size, and
	# anything below 1 is still refused, so you can never see past the grass.
	#
	# The pushes are multiples of the PITCH shot, not of the village shot, so
	# showing more of the ground in the wide shot does not make the players
	# any smaller during play.
	_home_v = PitchView.box_of(view_xform, home_rect)
	if pitch_box_view.size.x > 1.0:
		_home_v = pitch_box_view
	_frame_v = PitchView.box_of(view_xform, frame_rect)
	if ground_view.size.x > 1.0:
		# The wide shot is the tilted pitch plus a margin of the town round it
		# (PitchView.csv wide_shot_margin, a fraction of the pitch's size),
		# never past the edge of the picture.
		var margin := maxf(0.0, PitchView.number("wide_shot_margin", 0.1))
		_frame_v = _home_v.grow_individual(_home_v.size.x * margin, _home_v.size.y * margin,
			_home_v.size.x * margin, _home_v.size.y * margin).intersection(ground_view)
	var pitch_zoom := _zoom_to_fit(_home_v)
	wide_zoom = minf(_zoom_to_fit(_frame_v), pitch_zoom)
	if ground_view.size.x > 1.0:
		# Tilted, the pitch is a long diamond: fit all of it in the frame
		# (the town fills the corners), but never zoom out past the picture.
		pitch_zoom = _zoom_to_contain(_home_v)
		wide_zoom = maxf(minf(_zoom_to_contain(_frame_v), pitch_zoom), _zoom_to_fit(ground_view))
	play_zoom = pitch_zoom * maxf(1.0, play_zoom)
	close_zoom = maxf(pitch_zoom * maxf(1.0, close_zoom), play_zoom)

	_want_zoom = wide_zoom
	_want_point = _frame_v.get_center()
	_held_point = _want_point
	global_position = _want_point
	zoom = Vector2(wide_zoom, wide_zoom)


# =============================================================
#  WHAT TO LOOK AT — main_scene calls one of these every frame
# =============================================================

## The whole pitch. Used for the whistle, the draft and full time.
## ============ HOLDING A SHOT ============
##
## The match asks the camera to follow the play every frame, which is right
## for ninety minutes and wrong for the eight seconds of a kick-off. While
## the view is locked, look_wide() and look_at_play() are ignored — only
## lock_view(false) gives the camera back.
var _locked := false


func lock_view(on: bool) -> void:
	_locked = on


func look_wide() -> void:
	if _locked:
		return
	_mode = Mode.WIDE
	_want_point = _frame_v.get_center()
	_want_zoom = wide_zoom


## Live play. `point` is the ball; `toward` is where it is heading, which is
## the ball's landing spot mid-pass and the ball itself otherwise.
func look_at_play(point: Vector2, toward: Vector2) -> void:
	if _locked:
		return
	_mode = Mode.PLAY
	var aim := view_xform * point.lerp(toward, lead)
	# Only re-aim once the ball has actually gone somewhere. Without this the
	# camera creeps a pixel at a time for the whole ninety minutes.
	if _held_point.distance_to(aim) > deadzone:
		_held_point = aim
	_want_point = _held_point
	_want_zoom = play_zoom


## A tight look at one spot — a shot, a tackle, a goal.
func look_close(point: Vector2) -> void:
	_mode = Mode.CLOSE
	_held_point = view_xform * point
	_want_point = _held_point
	_want_zoom = close_zoom


func mode() -> int:
	return _mode


# =============================================================
#  MOVING
# =============================================================

func _process(delta: float) -> void:
	if home_rect.size.x < 1.0 or home_rect.size.y < 1.0:
		return

	# exp() keeps the ease identical whatever the frame rate, which lerp()
	# with a raw delta does not.
	var move_weight := 1.0 - exp(-follow_speed * delta)
	var zoom_weight := 1.0 - exp(-zoom_speed * delta)

	var next_zoom := lerpf(zoom.x, _want_zoom, zoom_weight)
	next_zoom = maxf(next_zoom, wide_zoom)
	zoom = Vector2(next_zoom, next_zoom)

	var goal := _clamp_centre(_want_point, next_zoom)
	global_position = global_position.lerp(goal, move_weight)
	# Clamp again after moving, or the ease itself can slide the view off the
	# grass for a frame or two on a fast pass.
	global_position = _clamp_centre(global_position, next_zoom)


## The zoom at which this rectangle just fits on screen. Anything less would
## show the void beyond it.
func _zoom_to_fit(area: Rect2) -> float:
	var view := _view_size()
	if area.size.x < 1.0 or area.size.y < 1.0 or view.x < 1.0 or view.y < 1.0:
		return 1.0
	return maxf(view.x / area.size.x, view.y / area.size.y)


## The zoom at which ALL of this rectangle is on screen (the tilted pitch).
func _zoom_to_contain(area: Rect2) -> float:
	var view := _view_size()
	if area.size.x < 1.0 or area.size.y < 1.0 or view.x < 1.0 or view.y < 1.0:
		return 1.0
	return minf(view.x / area.size.x, view.y / area.size.y)


## Keep the visible rectangle inside the ground. If the ground is smaller
## than the screen on an axis, centre on it instead — clamping would be
## impossible.
func _clamp_centre(point: Vector2, at_zoom: float) -> Vector2:
	if at_zoom <= 0.0:
		return point
	var half := (_view_size() / at_zoom) * 0.5
	var out := point
	var area := _frame_v if _frame_v.size.x > 1.0 else _home_v

	if area.size.x <= half.x * 2.0:
		out.x = area.get_center().x
	else:
		out.x = clampf(point.x, area.position.x + half.x, area.end.x - half.x)

	if area.size.y <= half.y * 2.0:
		out.y = area.get_center().y
	else:
		out.y = clampf(point.y, area.position.y + half.y, area.end.y - half.y)

	return out


func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1152, 648)
	return vp.get_visible_rect().size
