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
#    2. It never zooms OUT past the opening framing, so you can never see
#       past the edge of the grass.
#
#  EVERY NUMBER COMES FROM Tuning.csv. Set camera_enabled to false and the
#  match plays exactly as it did before, with no camera at all.
# =============================================================

enum Mode { WIDE, PLAY, CLOSE }

## The whole pitch as it was framed at kickoff. The view is never allowed
## outside this. Set once by main_scene before the camera goes live.
var home_rect: Rect2 = Rect2()

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
func setup(pitch: Rect2, db: CardDatabase) -> void:
	home_rect = pitch
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
	wide_zoom = _zoom_that_shows_all()
	play_zoom = wide_zoom * maxf(1.0, play_zoom)
	close_zoom = maxf(wide_zoom * maxf(1.0, close_zoom), play_zoom)

	_want_zoom = wide_zoom
	_want_point = home_rect.get_center()
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
	_want_point = home_rect.get_center()
	_want_zoom = wide_zoom


## Live play. `point` is the ball; `toward` is where it is heading, which is
## the ball's landing spot mid-pass and the ball itself otherwise.
func look_at_play(point: Vector2, toward: Vector2) -> void:
	if _locked:
		return
	_mode = Mode.PLAY
	var aim := point.lerp(toward, lead)
	# Only re-aim once the ball has actually gone somewhere. Without this the
	# camera creeps a pixel at a time for the whole ninety minutes.
	if _held_point.distance_to(aim) > deadzone:
		_held_point = aim
	_want_point = _held_point
	_want_zoom = play_zoom


## A tight look at one spot — a shot, a tackle, a goal.
func look_close(point: Vector2) -> void:
	_mode = Mode.CLOSE
	_held_point = point
	_want_point = point
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


## The zoom at which the whole pitch just fits on screen. Anything less would
## show the void beyond the grass.
func _zoom_that_shows_all() -> float:
	var view := _view_size()
	if home_rect.size.x < 1.0 or home_rect.size.y < 1.0 or view.x < 1.0 or view.y < 1.0:
		return 1.0
	return maxf(view.x / home_rect.size.x, view.y / home_rect.size.y)


## Keep the visible rectangle inside the pitch. If the pitch is smaller than
## the screen on an axis, centre on it instead — clamping would be impossible.
func _clamp_centre(point: Vector2, at_zoom: float) -> Vector2:
	if at_zoom <= 0.0:
		return point
	var half := (_view_size() / at_zoom) * 0.5
	var out := point

	if home_rect.size.x <= half.x * 2.0:
		out.x = home_rect.get_center().x
	else:
		out.x = clampf(point.x, home_rect.position.x + half.x, home_rect.end.x - half.x)

	if home_rect.size.y <= half.y * 2.0:
		out.y = home_rect.get_center().y
	else:
		out.y = clampf(point.y, home_rect.position.y + half.y, home_rect.end.y - half.y)

	return out


func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1152, 648)
	return vp.get_visible_rect().size
