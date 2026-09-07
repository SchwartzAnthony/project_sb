class_name Ball
extends Node2D

# =============================================================
#  THE BALL
#
#  Created in code by main_scene.gd — there is no ball.tscn to wire up.
#  It draws itself, so it needs no art, and it is NOT a physics body:
#  interception is a plain distance check each frame. That is cheap,
#  deterministic, and still works under `--headless`.
#
#  POSSESSION MODEL
#    A carrier dribbles toward the opposing goal for a few seconds, then
#    passes to a random team-mate. While the pass is in flight, any
#    opponent standing within `intercept_radius` of the ball takes it —
#    and the same cycle restarts from their side.
# =============================================================

signal possession_changed(new_carrier: PlayerUnit)
signal pass_intercepted(thief: PlayerUnit)
signal tackled(thief: PlayerUnit, victim: PlayerUnit)
## A shot on goal has reached its target. main_scene awaits this.
signal shot_arrived

@export var radius: float = 6.0
@export var pass_speed: float = 380.0                     # px / second
@export var shot_speed: float = 760.0                     # a strike on goal
@export var carry_seconds: Vector2 = Vector2(1.6, 3.4)    # min, max
@export var intercept_radius: float = 45.0
## Fraction of the pass that is safe. Without this the defender already
## marking the passer steals it the instant the ball leaves their feet.
@export var intercept_grace: float = 0.18
## An opponent this close to the CARRIER takes the ball off them.
@export var tackle_radius: float = 22.0
## Seconds a new carrier is safe for, so two adjacent opponents do not
## trade the ball back and forth every single frame.
@export var possession_grace: float = 0.7
## Seconds a tackled unit stops chasing for. Without this the two of them
## stand on the same spot swapping possession forever.
@export var tackle_recovery: float = 2.5
@export var carry_offset: Vector2 = Vector2(0.0, 16.0)
## How often a pass looks for a team-mate further upfield rather than anyone.
@export var forward_pass_chance: float = 0.75

## Set by main_scene. Returns every PlayerUnit currently on the pitch.
var units_provider: Callable = Callable()

var carrier: PlayerUnit = null
var frozen: bool = false

var _in_flight: bool = false
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _travelled: float = 0.0
var _distance: float = 0.0
var _intended: PlayerUnit = null
var _pass_from_enemy: bool = false
var _carry_left: float = 0.0
var _loose_left: float = 0.0
var _grace_left: float = 0.0
var _shooting: bool = false


func _ready() -> void:
	z_index = 50


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius + 1.5, Color(0.05, 0.05, 0.08, 0.85))
	draw_circle(Vector2.ZERO, radius, Color(0.97, 0.97, 1.0))
	draw_circle(Vector2(-radius * 0.28, -radius * 0.28), radius * 0.34, Color(0.16, 0.16, 0.22))


func _physics_process(delta: float) -> void:
	if frozen:
		return

	# A shot on goal outranks everything: it cannot be tackled or intercepted.
	if _shooting:
		_advance_shot(delta)
		return

	if _in_flight:
		_advance_pass(delta)
	elif is_instance_valid(carrier):
		global_position = carrier.global_position + carry_offset
		_grace_left -= delta
		if _grace_left <= 0.0 and _try_tackle():
			return
		_carry_left -= delta
		if _carry_left <= 0.0:
			make_pass()
	else:
		# Loose — nobody carrying, nothing in flight. Happens at kickoff and
		# when a carrier is substituted off. Nearest unit collects it.
		_loose_left -= delta
		if _loose_left <= 0.0:
			_loose_left = 0.3
			var nearest := _nearest_unit()
			if nearest != null:
				_take(nearest, false)


# =============================================================
#  PUBLIC
# =============================================================

## Hand the ball straight to a unit. Used at kickoff and by the PLAY MAKER
## hand-off, where the rock/paper/scissors winner starts on the ball.
func give_to(unit: PlayerUnit) -> void:
	if not is_instance_valid(unit):
		return
	_in_flight = false
	_intended = null
	_take(unit, false)


## Strike the ball at a point — the keeper, or the goal mouth behind them.
## Nobody can intercept or tackle a shot; `shot_arrived` fires on impact.
func shoot(target: Vector2) -> void:
	carrier = null
	_in_flight = false
	_intended = null
	_shooting = true
	_from = global_position
	_to = target
	_distance = maxf(_from.distance_to(_to), 1.0)
	_travelled = 0.0


func is_shooting() -> bool:
	return _shooting


func _advance_shot(delta: float) -> void:
	_travelled += shot_speed * delta
	var t := clampf(_travelled / _distance, 0.0, 1.0)
	global_position = _from.lerp(_to, t)
	if t >= 1.0:
		_shooting = false
		# Give main_scene a moment to decide what happens next before the
		# loose-ball rule hands it to whoever is standing nearest.
		_loose_left = 1.0
		shot_arrived.emit()


func has_carrier() -> bool:
	return is_instance_valid(carrier)


func is_carried_by(unit: PlayerUnit) -> bool:
	return is_instance_valid(carrier) and carrier == unit


## Freeze everything mid-flight (used during the HOLD UP! substitution).
func set_frozen(value: bool) -> void:
	frozen = value


# =============================================================
#  INTERNALS
# =============================================================

func _units() -> Array:
	if units_provider.is_valid():
		return units_provider.call()
	return []


## An opponent standing on the carrier wins the ball.
func _try_tackle() -> bool:
	for u in _units():
		var unit := u as PlayerUnit
		if unit == null or unit == carrier or unit.is_enemy == carrier.is_enemy:
			continue
		if unit.steal_cooldown > 0.0:
			continue     # still recovering from losing it
		if unit.global_position.distance_to(global_position) <= tackle_radius:
			var victim := carrier
			victim.steal_cooldown = tackle_recovery
			_take(unit, false)
			tackled.emit(unit, victim)
			return true
	return false


func _take(unit: PlayerUnit, intercepted: bool) -> void:
	_in_flight = false
	carrier = unit
	_carry_left = randf_range(carry_seconds.x, carry_seconds.y)
	_grace_left = possession_grace
	global_position = unit.global_position + carry_offset

	possession_changed.emit(unit)
	if intercepted:
		pass_intercepted.emit(unit)


func make_pass() -> void:
	if not is_instance_valid(carrier):
		return

	var mates: Array[PlayerUnit] = []
	for u in _units():
		var unit := u as PlayerUnit
		if unit == null or unit == carrier:
			continue
		if unit.is_enemy == carrier.is_enemy:
			mates.append(unit)

	if mates.is_empty():
		_carry_left = randf_range(carry_seconds.x, carry_seconds.y)
		return

	# Bias passes upfield. With purely random targets the ball just sloshes
	# around its own half forever, the other team never gets near it, and no
	# interception is ever possible.
	var forward: Array[PlayerUnit] = []
	for mate in mates:
		if (mate.global_position.x - carrier.global_position.x) * carrier.attack_dir > 20.0:
			forward.append(mate)

	var pool := mates
	if not forward.is_empty() and randf() < forward_pass_chance:
		pool = forward

	var target: PlayerUnit = pool.pick_random()
	_pass_from_enemy = carrier.is_enemy
	_from = global_position
	_to = target.global_position
	_distance = maxf(_from.distance_to(_to), 1.0)
	_travelled = 0.0
	_intended = target
	carrier = null
	_in_flight = true


func _advance_pass(delta: float) -> void:
	_travelled += pass_speed * delta
	var t := clampf(_travelled / _distance, 0.0, 1.0)

	# Track the receiver if they have drifted since the pass was struck.
	if is_instance_valid(_intended):
		_to = _intended.global_position
	global_position = _from.lerp(_to, t)

	# --- Interception: any opponent close enough to the loose ball ---
	if t > intercept_grace:
		for u in _units():
			var unit := u as PlayerUnit
			if unit == null or unit.is_enemy == _pass_from_enemy:
				continue
			if unit.global_position.distance_to(global_position) <= intercept_radius:
				_take(unit, true)
				return

	if t >= 1.0:
		if is_instance_valid(_intended):
			_take(_intended, false)
		else:
			# Receiver left the pitch mid-pass — nearest unit collects.
			_in_flight = false
			var best := _nearest_unit()
			if best != null:
				_take(best, false)


func _nearest_unit() -> PlayerUnit:
	var best: PlayerUnit = null
	var best_d := INF
	for u in _units():
		var unit := u as PlayerUnit
		if unit == null:
			continue
		var d := unit.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = unit
	return best
