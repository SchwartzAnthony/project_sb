class_name HoldPause
extends Node

# =============================================================
#  HOLD TO PAUSE  (Anthony, 24 Oct: "hold right click ... so that they can
#  pause and read the cards")
#
#  While the `hold_pause` key is held down (Keys.csv: Right Mouse, and a
#  controller button), the whole match stands still: the pitch, the duel
#  window, the shot window. Let go and it carries on exactly where it was.
#
#  HOW: it holds Engine.time_scale at 0. Every clock in the match reads that
#  (see game_speed.gd), so nothing needs telling, while the mouse still works
#  - you can hover a card and read its window while everything is frozen.
#  Letting go puts back the speed you had (1x, 2x, a held F ...).
#
#  It does nothing while the game is already paused underneath something
#  else (the Head Coach's box, the sub menu): that has its own pause.
# =============================================================

const ACTION := "hold_pause"

## True while the player is holding it. The duel and shot windows read this
## so the same click does not also skip them.
static var active := false

var _was_speed := 1.0


static func attach(match_scene: Node) -> Node:
	var made: Node = load("res://src/core/hold_pause.gd").new()
	made.name = "HoldPause"
	match_scene.add_child(made)
	return made


## Is this event the hold-to-pause key or button (pressed or let go)?
## The windows that skip on any click ask this first.
static func is_hold_event(event: InputEvent) -> bool:
	return event != null and InputMap.has_action(ACTION) and event.is_action(ACTION, true)


func _ready() -> void:
	# It has to hear the key let go even while the time is stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = false


func _process(_delta: float) -> void:
	var want := GameKeys.held(ACTION) and not get_tree().paused \
		and CardDatabase.get_db().tune_bool("hold_pause_on", true)
	if want:
		if not active:
			active = true
			_was_speed = Engine.time_scale
			print("[hold pause] Paused while held.")
		elif Engine.time_scale > 0.0:
			# Something changed the speed while held (a speed button, F):
			# that is the speed to go back to.
			_was_speed = Engine.time_scale
		Engine.time_scale = 0.0
	elif active:
		_release()


func _release() -> void:
	active = false
	Engine.time_scale = maxf(GameSpeed.MIN_SPEED, _was_speed)
	print("[hold pause] Carries on.")


## Safety net: the window loses focus while it is held and the let-go never
## arrives, so the match would stay frozen.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and active:
		_release()
	elif what == NOTIFICATION_PREDELETE and active:
		active = false
		Engine.time_scale = maxf(GameSpeed.MIN_SPEED, _was_speed)
