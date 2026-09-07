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
# Steering is per-frame in _physics_process, NOT tween-driven. Tweens and
# ball-chasing fight over `position`; a single integrator does not.
var home_position: Vector2
var roam_radius: float = 40.0
var is_roaming: bool = false
var movement_frozen: bool = false     # HOLD UP! substitution pauses everyone

@export var walk_speed: float = 30.0        # px/s ambling around home
@export var chase_speed: float = 66.0       # px/s closing on the ball
@export var dribble_speed: float = 44.0     # px/s carrying it upfield
@export var interest_radius: float = 190.0  # only react to a ball this close

# --- Crowding ------------------------------------------------
# Units used to walk straight through each other and settle into the same
# few pixels. These three turn that into a shove: everybody keeps a little
# room, EXCEPT near the ball, where fighting over it is the point.
## How close another unit has to be before this one starts giving way.
@export var separation_radius: float = 52.0
## How hard the shove is, relative to the pull of wherever they are heading.
@export var separation_strength: float = 0.9
## Inside this distance of the ball the shove fades out, so a loose ball is
## genuinely contested instead of politely orbited.
@export var contest_radius: float = 70.0
## A sideways bias on the run to the ball, its direction fixed per unit, so a
## group converging on it takes curved routes instead of forming one queue.
@export var swerve_strength: float = 0.35

## Assigned at spawn by main_scene.
var ball: Ball = null
var play_bounds: Rect2 = Rect2()
var attack_dir: float = 1.0                 # +1 attacks right, -1 attacks left

## Counts down after this unit is tackled. While it is above zero the unit
## stops chasing the ball and cannot win it back, which is what stops two
## opponents standing on the same spot trading possession forever.
var steal_cooldown: float = 0.0

var _roam_target: Vector2
var _roam_wait: float = 0.0
## +1 or -1, fixed for this unit's lifetime: which way it bends around traffic.
var _swerve_sign: float = 1.0

@export var data: PlayerData:
	set(new_data):
		data = new_data
		if is_node_ready():
			update_display()

# --- Match state ---------------------------------------------
var is_enemy: bool = false

## Set explicitly at spawn. Flipping it puts the Star badge up (or takes it
## down), so nothing else has to remember to keep the marker in sync.
var is_star_player: bool = false:
	set(value):
		is_star_player = value
		_refresh_star_badge()

var is_playmaker: bool = false     # picked during the current round
var is_exhausted: bool = false     # already used this cycle

## The little marker riding above a Star Player. Created on demand.
var _star_badge: StarBadge = null


func _ready() -> void:
	# Fixed for life, so this unit always bends the same way round traffic
	# rather than dithering left and right on the spot.
	_swerve_sign = 1.0 if randf() < 0.5 else -1.0
	update_display()
	_refresh_star_badge()


# =============================================================
#  STAR BADGE
#
#  Purely cosmetic, and deliberately a SIBLING of Artwork rather than a
#  child: set_highlight() dims Artwork.modulate down to 0.25 for a spent
#  unit, and the badge must stay readable through that.
#
#  Size and height come from Tuning.csv (star_badge_radius,
#  star_badge_offset_y); the art itself comes from a PNG — see star_badge.gd.
# =============================================================

func _refresh_star_badge() -> void:
	if Engine.is_editor_hint() or not is_node_ready():
		return

	if not is_star_player:
		if _star_badge != null:
			_star_badge.visible = false
		return

	if _star_badge == null:
		_star_badge = StarBadge.new()
		_star_badge.name = "StarBadge"
		add_child(_star_badge)

	var radius := 9.0
	var offset_y := -34.0
	var pulse := 0.08
	var db := CardDatabase.get_db()
	if db != null:
		radius = db.tune_float("star_badge_radius", radius)
		offset_y = db.tune_float("star_badge_offset_y", offset_y)
		pulse = db.tune_float("star_badge_pulse", pulse)

	_star_badge.is_enemy = is_enemy
	_star_badge.badge_radius = radius
	_star_badge.pulse_amount = pulse
	_star_badge.set_process(pulse > 0.0)
	_star_badge.position = Vector2(0.0, offset_y)
	_star_badge.visible = true


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
#  MOVEMENT
#
#  Three modes, checked in priority order every physics frame:
#    1. I have the ball        -> dribble toward the opposing goal
#    2. The ball is near me    -> run at it (this is the "collision range"
#                                 you asked for, done as a radius check —
#                                 no Area2D overlap needed, and it works
#                                 headless)
#    3. Otherwise              -> amble around my formation slot
# =============================================================

func set_home(pos: Vector2) -> void:
	position = pos
	home_position = pos
	_pick_roam_target()
	start_roaming()


func start_roaming() -> void:
	if Engine.is_editor_hint():
		return
	is_roaming = true


func stop_roaming() -> void:
	is_roaming = false


func has_ball() -> bool:
	return ball != null and is_instance_valid(ball) and ball.is_carried_by(self)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or movement_frozen or not is_roaming:
		return

	steal_cooldown = maxf(0.0, steal_cooldown - delta)

	var target: Vector2
	var speed: float
	var chasing := false

	if has_ball():
		target = _dribble_target()
		speed = dribble_speed
	elif _ball_is_in_range():
		target = ball.global_position
		speed = chase_speed
		chasing = true
	else:
		_roam_wait -= delta
		if _roam_wait <= 0.0 or global_position.distance_to(_roam_target) < 5.0:
			_pick_roam_target()
		target = _roam_target
		speed = walk_speed

	# --- Steering ---
	# The old code was a straight move_toward(), which is why units walked
	# through each other and stacked up. Now the pull toward the target is one
	# force among three, and the sum decides the heading.
	var to_target := target - global_position
	var distance := to_target.length()
	if distance < 0.5:
		return

	var heading := to_target / distance

	# Bend the run, hard when far out and straightening up as they arrive, so
	# ten units converging on a loose ball take ten different lines.
	if chasing and not is_zero_approx(swerve_strength):
		var bend := clampf(distance / maxf(interest_radius, 1.0), 0.0, 1.0)
		heading += heading.orthogonal() * _swerve_sign * swerve_strength * bend

	heading += _separation() * separation_strength

	if heading.length_squared() < 0.000001:
		return

	# minf() with the remaining distance keeps the old arrival behaviour: they
	# stop on the target rather than jittering back and forth across it.
	global_position += heading.normalized() * minf(speed * delta, distance)
	_clamp_to_bounds()


## A push away from every other unit standing too close, strongest when they
## are almost touching and nothing at all at separation_radius.
func _separation() -> Vector2:
	var parent := get_parent()
	if parent == null or separation_radius <= 0.0:
		return Vector2.ZERO

	# Crowding round the ball is wanted, so the push fades as they close on it.
	# Without this the shove cancels the chase and nobody ever wins a tackle.
	var ease_off := 1.0
	if ball != null and is_instance_valid(ball) and contest_radius > 0.0:
		ease_off = clampf(
			global_position.distance_to(ball.global_position) / contest_radius, 0.2, 1.0)

	var push := Vector2.ZERO
	for sibling in parent.get_children():
		# Goalies share this container but are GoalieUnits, so they cast to
		# null here and stay out of the shoving.
		var other := sibling as PlayerUnit
		if other == null or other == self:
			continue

		var away := global_position - other.global_position
		var gap := away.length()
		if gap < 0.01:
			# Exactly superimposed. Break the tie by instance id so the two of
			# them always separate instead of pushing each other equally.
			push += Vector2(0.0, 1.0 if get_instance_id() > other.get_instance_id() else -1.0)
		elif gap < separation_radius:
			push += (away / gap) * (1.0 - gap / separation_radius)

	return push * ease_off


func _ball_is_in_range() -> bool:
	if ball == null or not is_instance_valid(ball) or steal_cooldown > 0.0:
		return false
	return global_position.distance_to(ball.global_position) <= interest_radius


func _dribble_target() -> Vector2:
	if play_bounds.size.x <= 1.0:
		return global_position + Vector2(attack_dir * 120.0, 0.0)
	var goal_x: float = play_bounds.end.x if attack_dir > 0.0 else play_bounds.position.x
	return Vector2(goal_x, global_position.y)


func _pick_roam_target() -> void:
	_roam_target = home_position + Vector2(
		randf_range(-roam_radius, roam_radius),
		randf_range(-roam_radius, roam_radius)
	)
	_roam_wait = randf_range(1.5, 4.0)


func _clamp_to_bounds() -> void:
	if play_bounds.size.x <= 1.0 or play_bounds.size.y <= 1.0:
		return
	global_position.x = clampf(global_position.x, play_bounds.position.x, play_bounds.end.x)
	global_position.y = clampf(global_position.y, play_bounds.position.y, play_bounds.end.y)


# --- Scripted moves (substitutions, pre-combat framing) ------
# These take over from the steering above by clearing is_roaming, so the
# two never fight over `position`.

func run_to(target: Vector2, duration: float = 0.6) -> void:
	var was_roaming := is_roaming
	is_roaming = false
	var tween := create_tween()
	tween.tween_property(self, "global_position", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	is_roaming = was_roaming


func return_home(duration: float = 0.35) -> void:
	# Used before a combat zoom-in so the camera frames a predictable spot.
	await run_to(home_position, duration)
