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
## A scripted PLAY MAKER pass has reached its man.
signal delivery_arrived

@export var radius: float = 6.0
@export var pass_speed: float = 380.0                     # px / second
@export var shot_speed: float = 760.0                     # a strike on goal
@export var delivery_speed: float = 520.0                 # a scripted PLAY MAKER pass
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

## A LOOSE ball is only collected by someone who actually reaches it. Without
## this the nearest unit was handed possession from anywhere on the pitch,
## which is what made the ball look like it teleported to the next player
## after the whistle.
@export var pickup_radius: float = 26.0
## Beat before a ball that has just come loose can be picked up at all, so a
## stopped pass is visibly loose rather than instantly re-collected.
@export var loose_settle_seconds: float = 0.35
## Safety valve: if a loose ball sits this long with nobody close enough to
## claim it, the nearest unit collects it anyway and play carries on.
@export var loose_timeout_seconds: float = 6.0

## An opponent this close makes the carrier release the ball early.
@export var pressure_radius: float = 82.0
## ...but never before holding it this long, or possession becomes a hot potato.
@export var min_hold_seconds: float = 0.9

## While true the ball keeps whoever it was given to and does nothing on its
## own — no dribble timer, no tackles, no interceptions. Set during a PLAY
## MAKER so the scripted relay is not hijacked by open play, WITHOUT having to
## freeze the players as well.
var scripted_possession: bool = false

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
var _scripted: bool = false
## How long the current ball has been loose, for the timeout above.
var _loose_age: float = 0.0
## Set only for an interception: who steals the pass, and how far along it.
var _thief: PlayerUnit = null
var _steal_at: float = -1.0
## How long the current carrier has had it, for the release-under-pressure rule.
var _held: float = 0.0


func _ready() -> void:
	z_index = 50


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius + 1.5, Color(0.05, 0.05, 0.08, 0.85))
	draw_circle(Vector2.ZERO, radius, Color(0.97, 0.97, 1.0))
	draw_circle(Vector2(-radius * 0.28, -radius * 0.28), radius * 0.34, Color(0.16, 0.16, 0.22))


func _physics_process(delta: float) -> void:
	# Scripted moves outrank `frozen`: during a PLAY MAKER the pitch is held
	# still, but the choreographed relay and the shot still have to play out.
	# Neither can be tackled or intercepted.
	if _shooting:
		_advance_shot(delta)
		return
	if _scripted:
		_advance_delivery(delta)
		return

	if frozen:
		# Stay at the carrier's feet even while frozen, so a unit moved by a
		# tween (a substitution) does not leave the ball behind.
		if is_instance_valid(carrier):
			global_position = carrier.global_position + carry_offset
		return

	if _in_flight:
		_advance_pass(delta)
	elif is_instance_valid(carrier):
		global_position = carrier.global_position + carry_offset

		# During a PLAY MAKER the ball belongs to the script, not to itself:
		# it stays exactly where it was put until the next scripted pass. The
		# UNITS still move freely — that separation is the whole point, and it
		# is why the pitch no longer turns into a waxwork during a relay.
		if scripted_possession:
			return

		_grace_left -= delta
		if _grace_left <= 0.0 and _try_tackle():
			return

		_held += delta
		_carry_left -= delta

		# Move it on before the press arrives. Without this the carrier waits
		# out its dribble timer, gets swarmed, and the ball dies in a scrum
		# instead of travelling — which is the thing you actually watch.
		var pressed := _held >= min_hold_seconds and is_under_pressure(pressure_radius)
		if _carry_left <= 0.0 or pressed:
			make_pass(pressed)
	else:
		if scripted_possession:
			return
		# Loose — nobody carrying, nothing in flight. Happens at kickoff, when
		# a carrier is substituted off, and whenever a pass is stopped by the
		# whistle. It is claimed by whoever actually RUNS to it, not by
		# whoever happens to be nearest, so possession never jumps across the
		# pitch on its own.
		_loose_left -= delta
		_loose_age += delta
		if _loose_left <= 0.0:
			_loose_left = 0.1
			var nearest := _nearest_unit()
			if nearest == null:
				return
			var reach := nearest.global_position.distance_to(global_position)
			if reach <= pickup_radius or _loose_age >= loose_timeout_seconds:
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


## A scripted pass straight to one unit — the PLAY MAKER relay and the goal
## kick. Cannot be intercepted or tackled; emits `delivery_arrived` on landing.
func deliver_to(unit: PlayerUnit) -> void:
	if not is_instance_valid(unit):
		delivery_arrived.emit()
		return
	carrier = null
	_in_flight = false
	_shooting = false
	_scripted = true
	_intended = unit
	_thief = null
	_steal_at = -1.0
	_from = global_position
	_to = unit.global_position
	_distance = maxf(_from.distance_to(_to), 1.0)
	_travelled = 0.0


## A pass that gets picked off. The ball sets out for `intended` exactly as a
## normal delivery would, and `thief` cuts across and takes it partway. Used
## for a turnover, so possession changes hands by someone reading the pass
## rather than by the ball simply appearing at the other team's feet.
##
## Still emits delivery_arrived when it settles, so callers await it the same
## way as any other scripted pass.
func intercept_pass(intended: PlayerUnit, thief: PlayerUnit, at: float = 0.55) -> void:
	if not is_instance_valid(thief):
		deliver_to(intended)
		return
	if not is_instance_valid(intended):
		deliver_to(thief)
		return

	deliver_to(intended)
	_thief = thief
	_steal_at = clampf(at, 0.05, 0.95)


## Where the ball will be when the thief cuts in. main_scene sends them there
## so the leap and the ball arrive together.
func steal_point() -> Vector2:
	if _steal_at < 0.0:
		return global_position
	return _from.lerp(_to, _steal_at)


func _advance_delivery(delta: float) -> void:
	if not is_instance_valid(_intended):
		_scripted = false
		_loose_left = 1.0
		_loose_age = 0.0
		delivery_arrived.emit()
		return

	_to = _intended.global_position
	_travelled += delivery_speed * delta
	var t := clampf(_travelled / _distance, 0.0, 1.0)
	global_position = _from.lerp(_to, t)

	# --- The cut-in ---
	# Partway to its intended man the ball changes owner. Re-aiming from HERE
	# rather than from the original spot is what makes it look intercepted:
	# the ball visibly turns out of its line toward the thief.
	if _steal_at >= 0.0 and t >= _steal_at and is_instance_valid(_thief):
		_intended = _thief
		_thief = null
		_steal_at = -1.0
		_from = global_position
		_to = _intended.global_position
		_distance = maxf(_from.distance_to(_to), 1.0)
		_travelled = 0.0
		return

	if t >= 1.0:
		# _take() first, while _scripted is still true, so anything listening
		# to possession_changed can tell a scripted pass from an open-play one.
		_take(_intended, false)
		_scripted = false
		delivery_arrived.emit()


func is_delivering() -> bool:
	return _scripted


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
		# loose-ball rule hands it to whoever runs onto it.
		_loose_left = 1.0
		_loose_age = 0.0
		shot_arrived.emit()


func has_carrier() -> bool:
	return is_instance_valid(carrier)


## Which side is on the ball: 0 = home, 1 = away, -1 = nobody (loose).
##
## Crucially this stays answered WHILE A PASS IS IN THE AIR. Without that,
## every unit lost its job for the whole of every pass — which is most of the
## match — and the two teams reverted to aimless milling about between touches.
func side_on_ball() -> int:
	if is_instance_valid(carrier):
		return 1 if carrier.is_enemy else 0
	if _in_flight or _scripted:
		if is_instance_valid(_intended):
			return 1 if _intended.is_enemy else 0
		return 1 if _pass_from_enemy else 0
	return -1


## The unit a pass is currently aimed at, or null. They go to meet it.
func intended_receiver() -> PlayerUnit:
	if (_in_flight or _scripted) and is_instance_valid(_intended):
		return _intended
	return null


func is_in_flight() -> bool:
	return _in_flight or _scripted or _shooting


## Where the ball is going to end up — the receiver for a pass, the carrier's
## feet otherwise. Defenders press THIS rather than the ball's current spot,
## so they arrive with it instead of trailing behind it.
func arrival_point() -> Vector2:
	var receiver := intended_receiver()
	if receiver != null:
		return receiver.global_position
	if is_instance_valid(carrier):
		return carrier.global_position
	return global_position


## True while an opponent is close enough that the carrier should move it on.
func is_under_pressure(radius: float) -> bool:
	if not is_instance_valid(carrier):
		return false
	for u in _units():
		var unit := u as PlayerUnit
		if unit == null or unit.is_enemy == carrier.is_enemy:
			continue
		if unit.global_position.distance_to(carrier.global_position) <= radius:
			return true
	return false


func is_carried_by(unit: PlayerUnit) -> bool:
	return is_instance_valid(carrier) and carrier == unit


## Freeze everything (the whistle: a PLAY MAKER, a HOLD UP!, a substitution).
##
## A pass caught in mid-air by the whistle is DROPPED where it is rather than
## paused and resumed. Resuming it made the ball glide the rest of the way to
## a player nobody had kicked it to any more, which read as the ball moving
## on its own. Now the whistle leaves a loose ball, and whoever runs to it
## when play restarts is the one who keeps it.
func set_frozen(value: bool) -> void:
	if value and not frozen:
		settle_in_place()
	frozen = value


## The carrier is leaving the pitch (a HOLD UP! substitution). Put the ball
## down where they were standing rather than letting it vanish with them.
func drop() -> void:
	carrier = null
	_in_flight = false
	_intended = null
	_loose_left = loose_settle_seconds
	_loose_age = 0.0


## Kill any pass in flight and leave the ball lying where it currently is.
## A shot or a scripted PLAY MAKER delivery is left alone: those are
## choreographed and have to finish, or the sequence that is awaiting them
## never returns.
func settle_in_place() -> void:
	if _shooting or _scripted:
		return
	if not _in_flight:
		return
	_in_flight = false
	_intended = null
	_loose_left = loose_settle_seconds
	_loose_age = 0.0


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
	_loose_age = 0.0
	_held = 0.0
	carrier = unit
	_carry_left = randf_range(carry_seconds.x, carry_seconds.y)
	_grace_left = possession_grace
	global_position = unit.global_position + carry_offset

	possession_changed.emit(unit)
	if intercepted:
		pass_intercepted.emit(unit)


## `hurried` is set when the carrier is releasing under pressure rather than
## because the dribble timer ran out.
func make_pass(hurried: bool = false) -> void:
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
	if hurried:
		# A hurried ball hoofed into a crowd is just a turnover. Pick the
		# man with the most room instead of any man at all.
		var best_room := -INF
		for mate in pool:
			var nearest_foe := INF
			for u in _units():
				var foe := u as PlayerUnit
				if foe == null or foe.is_enemy == mate.is_enemy:
					continue
				nearest_foe = minf(nearest_foe, foe.global_position.distance_to(mate.global_position))
			if is_inf(nearest_foe):
				nearest_foe = 999.0
			# Slightly prefer a nearer team-mate: a 40-yard ball to a free man
			# is still a worse idea than a short one to a fairly free man.
			var room := nearest_foe - carrier.global_position.distance_to(mate.global_position) * 0.15
			if room > best_room:
				best_room = room
				target = mate
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
			# Receiver left the pitch mid-pass. The ball arrives anyway and
			# lies there until somebody runs onto it.
			_in_flight = false
			_intended = null
			_loose_left = loose_settle_seconds
			_loose_age = 0.0


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
