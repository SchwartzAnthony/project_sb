class_name AdventureStrike
extends Node2D

# =============================================================
#  THE BALL, THE KICK, AND THE HIT — Phase 4
#
#  Until now a fight was a list of sentences in a panel. This is the part
#  you watch: the last player drafted runs up, kicks the ball at the enemy
#  you focused, the enemy flinches, and a damage number floats off it.
#  Enemies striking back get the same treatment in reverse.
#
#  ============ WHY IT IS ITS OWN FILE ============
#
#  The encounter decides WHAT happens; this decides what it LOOKS like.
#  Keeping them apart means the numbers can be re-balanced without touching
#  animation, and the animation can be replaced with real artwork without
#  touching a single rule.
#
#  Every duration is a row in Tuning.csv, so the whole fight can be sped up
#  or slowed down without opening a script:
#
#      adventure_kick_seconds      the ball's flight
#      adventure_flinch_seconds    the shove backwards on a hit
#      adventure_float_seconds     how long a damage number hangs
#
#  ============ IT WORKS WITH NO ART ============
#
#  The ball is drawn, the flinch is a tween on a position, the number is a
#  Label. Nothing here needs a single image, so it is watchable today and
#  gets better the moment you draw something.
# =============================================================

## HOW BIG THE BALL IS. In Tuning.csv under `adventure_ball_size`, written
## here by adventure_scene.gd as a run opens — same arrangement as the player
## radius next door. It is smaller than it was: the old ball was nearly half
## a player across, which is why it read as a melon.
static var BALL_RADIUS := 7.0


## Kick the ball from one point to another and return when it lands.
##
## `arc_height` is how far it rises on the way — a flat pass for a short
## distance, a lofted shot for a long one, worked out from the gap so it
## always looks like a kick rather than a slide.
## ============ IT KICKS THE BALL THEY ARE ALREADY CARRYING ============
##
## Pass the run's own ball node as `use_ball` and THAT is what flies. The
## first version made a new ball for every kick, so the one on the grass sat
## still while phantom balls came out of nowhere. Now the real ball leaves
## their feet, arcs at the enemy, and is put back where it started — so the
## party still has it for the next round.
##
## With no ball passed in it makes a temporary one, which is what the
## headless test rig and any future caller without a ball will get.
static func kick(parent: Node2D, from: Vector2, to: Vector2,
		seconds: float = 0.42, use_ball: Node2D = null) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	var borrowed := use_ball != null and is_instance_valid(use_ball)
	var ball: Node2D
	var came_from := Vector2.ZERO

	if borrowed:
		ball = use_ball
		came_from = ball.position       # put it back here afterwards
	else:
		ball = AdventureStrike.new()
		parent.add_child(ball)
	ball.z_index = 40
	ball.position = from

	# CLAIM THE BALL. The party passes it about constantly now, including
	# while you are choosing a target — so anything that moves it has to know
	# when a shot is already in the air. This mark is what says so; the scene
	# checks it in _ball_is_busy() before passing.
	if borrowed:
		ball.set_meta("busy", true)

	var gap := from.distance_to(to)
	var arc_height := clampf(gap * 0.28, 24.0, 150.0)
	var clock := 0.0
	var span := maxf(0.05, seconds)

	# Hand-stepped rather than a tween, because the arc needs the ball's
	# height to follow a curve while x and y both travel — which is one
	# line here and three tweens otherwise.
	while clock < span:
		clock += parent.get_process_delta_time()
		var t := clampf(clock / span, 0.0, 1.0)
		var flat := from.lerp(to, t)
		# sin() gives 0 at both ends and 1 in the middle: a clean arc.
		ball.position = flat - Vector2(0.0, sin(t * PI) * arc_height)
		ball.rotation += parent.get_process_delta_time() * 14.0
		ball.queue_redraw()
		await parent.get_tree().process_frame
		if not is_instance_valid(parent) or not is_instance_valid(ball):
			# LET GO ON THE WAY OUT. A scene change mid-kick would otherwise
			# leave the claim set and the ball would never be passed again.
			if borrowed and is_instance_valid(ball):
				ball.set_meta("busy", false)
			return

	if borrowed:
		# Hand it back. The run's ball belongs to the party, not to us.
		ball.position = came_from
		ball.rotation = 0.0
		ball.set_meta("busy", false)
		ball.queue_redraw()
	else:
		ball.queue_free()


## A short shove away from whoever hit it, then back. Reads as "that
## connected" without needing a hurt animation to exist.
static func flinch(what: Node2D, away_from: Vector2,
		seconds: float = 0.22) -> void:
	if what == null or not is_instance_valid(what):
		return
	var home := what.position
	var push := (what.position - away_from).normalized() * 18.0
	if push == Vector2.ZERO:
		push = Vector2(18.0, 0.0)

	var shove := what.create_tween()
	shove.tween_property(what, "position", home + push, seconds * 0.35)
	shove.tween_property(what, "position", home, seconds * 0.65)
	await shove.finished


## The number that floats up off whatever was hit. Red for damage taken,
## accent for damage you dealt.
static func number(parent: Node2D, at: Vector2, text: String,
		good: bool, seconds: float = 0.9) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	var label := Label.new()
	label.text = text
	label.z_index = 50
	label.position = at + Vector2(-20.0, -30.0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if good else Color(0.92, 0.42, 0.38))
	# An outline, so a number is readable over grass or over an enemy.
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# adventure-look: ON THE ISOMETRIC FIELD the number stands upright on a
	# small holder at the spot, and floats straight up the screen.
	if parent.has_meta("upright"):
		var holder := Node2D.new()
		var up: Transform2D = parent.get_meta("upright")
		holder.transform = Transform2D(up.x, up.y, at)
		holder.set_meta("float_on_top", true)
		parent.add_child(holder)
		label.position = Vector2(-20.0, -30.0)
		holder.add_child(label)
		var lift := label.create_tween()
		lift.set_parallel(true)
		lift.tween_property(label, "position", label.position + Vector2(0.0, -44.0), seconds)
		lift.tween_property(label, "modulate:a", 0.0, seconds).set_delay(seconds * 0.45)
		await lift.finished
		if is_instance_valid(holder):
			holder.queue_free()
		return
	parent.add_child(label)

	var rise := label.create_tween()
	rise.set_parallel(true)
	rise.tween_property(label, "position",
		label.position + Vector2(0.0, -44.0), seconds)
	rise.tween_property(label, "modulate:a", 0.0, seconds).set_delay(seconds * 0.45)
	await rise.finished
	if is_instance_valid(label):
		label.queue_free()


## A quick run up and back, for the player taking the shot. They step out of
## the line, kick, and jog back into it.
static func step_up(who: Node2D, towards: Vector2, seconds: float = 0.26) -> void:
	if who == null or not is_instance_valid(who):
		return
	var home := who.position
	var forward := home + (towards - home).normalized() * 34.0
	var move := who.create_tween()
	move.tween_property(who, "position", forward, seconds)
	await move.finished


func _draw() -> void:
	draw_circle(Vector2.ZERO, BALL_RADIUS, Color(0.95, 0.95, 0.92))
	draw_arc(Vector2.ZERO, BALL_RADIUS, 0.0, TAU, 16, Color(0.20, 0.20, 0.20), 1.6, true)
	# Two panel lines that rotate with the ball, so the spin is visible.
	draw_line(Vector2(-BALL_RADIUS * 0.7, 0.0), Vector2(BALL_RADIUS * 0.7, 0.0),
		Color(0.30, 0.30, 0.30), 1.4)
	draw_line(Vector2(0.0, -BALL_RADIUS * 0.7), Vector2(0.0, BALL_RADIUS * 0.7),
		Color(0.30, 0.30, 0.30), 1.4)
