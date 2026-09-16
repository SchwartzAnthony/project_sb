class_name ControllerFocus
extends CanvasLayer

# =============================================================
#  MOVING ABOUT WITH A CONTROLLER
#
#  The buttons already answered to a controller — A pressed whatever was
#  highlighted. What was missing was the HIGHLIGHT MOVING: a stick or the
#  arrow keys had nothing to walk between.
#
#  This wires that, for every screen, in one place.
#
#  ============ WHAT IT DOES ============
#
#      STICK / D-PAD / ARROWS   moves the highlight to the nearest button
#                               in that direction
#      A / ENTER / SPACE        presses it   (the `confirm` key)
#      B / BACKSPACE            the screen's Back button  (the `cancel` key)
#      ANY MOVEMENT             highlights something if nothing is yet
#      THE MOUSE                takes the highlight away again
#
#  The last one matters more than it sounds. A focus box left sitting on a
#  button while you are using the mouse looks like a bug, so touching the
#  mouse clears it and pushing the stick brings it back.
#
#  ============ HOW A SCREEN GETS IT ============
#
#  It does not have to do anything. MenuEscape.install(self) — which every
#  screen already calls — installs this too. A screen you write next year
#  gets controller navigation without knowing this file exists.
#
#  ============ HOW IT KNOWS WHERE TO GO ============
#
#  It does NOT use Godot's neighbour properties, which would mean wiring
#  every button to every other button by hand on every screen. It works out
#  the nearest button in the direction you pushed, from where the buttons
#  actually are on screen. So a screen that builds its buttons from a CSV —
#  which is most of them — is navigable the moment the CSV changes.
#
#  ============ TURNING IT OFF ============
#
#      pad_enabled     false in Settings > Controller, or
#      keyboard_focus  false in Tuning.csv for the arrow keys as well
# =============================================================

const NODE_NAME := "ControllerFocus"

## How far off the straight line a button may be and still count as "that
## way". Higher is more forgiving; too high and pressing right picks
## something below you.
const SPREAD := 1.4

var _last_mouse := Vector2.ZERO
var _using_pad := false

## True when the stick has come back to the middle since its last push.
## This is what turns a held stick into ONE step rather than forty.
var _stick_ready: bool = true


static func install(on: Node) -> ControllerFocus:
	if on == null:
		return null
	for child in on.get_children():
		if child is ControllerFocus:
			return child as ControllerFocus
	var made := ControllerFocus.new()
	made.name = NODE_NAME
	on.add_child(made)
	return made


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS


# =============================================================
#  INPUT
# =============================================================

func _input(event: InputEvent) -> void:
	# THE MOUSE WINS WHILE IT IS MOVING. Nothing looks more broken than a
	# focus box sitting on a button you are not using.
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _using_pad and motion.position.distance_to(_last_mouse) > 6.0:
			_using_pad = false
			_drop_focus()
		_last_mouse = motion.position
		return

	if _is_off():
		return

	var way := _direction(event)
	if way != Vector2i.ZERO:
		_using_pad = true
		_step(way)
		get_viewport().set_input_as_handled()
		return

	# CONFIRM presses whatever is highlighted. Godot does this for a focused
	# Button by itself with ui_accept, but our `confirm` action is the one
	# the player rebound in Settings, so it is honoured here too.
	if GameKeys.pressed(event, "confirm") and _using_pad:
		var here := _focused()
		if here != null:
			here.emit_signal("pressed")
			get_viewport().set_input_as_handled()
		return

	# CANCEL is the screen's own Back button, wherever it is. Every screen
	# builds its footer with MenuSupport.footer_bar(), which names that
	# button BackButton — so this finds it without any screen wiring it up.
	if GameKeys.pressed(event, "cancel"):
		var back := _find_back()
		if back != null and not back.disabled:
			back.emit_signal("pressed")
			get_viewport().set_input_as_handled()


## Is navigation switched off? A pad that the player turned off in Settings,
## or arrow keys they would rather kept out of the way.
func _is_off() -> bool:
	var settings := GameSettings.load_all()
	if not bool(settings.get("pad_enabled", true)):
		return true
	return false


## Which way an event is asking to go, or nothing. Covers the stick, the
## d-pad and the arrow keys in one place.
func _direction(event: InputEvent) -> Vector2i:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_LEFT:  return Vector2i(-1, 0)
			KEY_RIGHT: return Vector2i(1, 0)
			KEY_UP:    return Vector2i(0, -1)
			KEY_DOWN:  return Vector2i(0, 1)

	var pad := event as InputEventJoypadButton
	if pad != null and pad.pressed:
		match pad.button_index:
			JOY_BUTTON_DPAD_LEFT:  return Vector2i(-1, 0)
			JOY_BUTTON_DPAD_RIGHT: return Vector2i(1, 0)
			JOY_BUTTON_DPAD_UP:    return Vector2i(0, -1)
			JOY_BUTTON_DPAD_DOWN:  return Vector2i(0, 1)

	# THE STICK. A stick sends a stream of small values, so only a decisive
	# push counts and only once per push — otherwise one flick would run the
	# highlight across the whole screen.
	var stick := event as InputEventJoypadMotion
	if stick != null:
		var dead := float(GameSettings.load_all().get("pad_deadzone", 0.2))
		var past := absf(stick.axis_value) > maxf(0.6, dead + 0.3)
		if not past:
			_stick_ready = true
			return Vector2i.ZERO
		if not _stick_ready:
			return Vector2i.ZERO
		_stick_ready = false
		var sign_of := 1 if stick.axis_value > 0.0 else -1
		if stick.axis == JOY_AXIS_LEFT_X or stick.axis == JOY_AXIS_RIGHT_X:
			return Vector2i(sign_of, 0)
		if stick.axis == JOY_AXIS_LEFT_Y or stick.axis == JOY_AXIS_RIGHT_Y:
			return Vector2i(0, sign_of)

	return Vector2i.ZERO



# =============================================================
#  MOVING THE HIGHLIGHT
# =============================================================

func _step(way: Vector2i) -> void:
	var options := _buttons()
	if options.is_empty():
		return

	var here := _focused()
	if here == null or not options.has(here):
		# NOTHING HIGHLIGHTED YET. Start at the top-left-most button, which
		# is what a person reads first.
		var first := options[0]
		for button in options:
			var a := button.get_global_rect().position
			var b := first.get_global_rect().position
			if a.y < b.y - 4.0 or (absf(a.y - b.y) <= 4.0 and a.x < b.x):
				first = button
		first.grab_focus()
		return

	var from := here.get_global_rect().get_center()
	var best: Button = null
	var best_cost := INF

	for button in options:
		if button == here:
			continue
		var to := button.get_global_rect().get_center()
		var offset := to - from

		# HOW FAR THAT WAY, and how far off to the side. A button has to be
		# genuinely in the direction pushed, and among those the nearest
		# wins — with sideways distance counted heavier, so pressing right
		# prefers the button beside you over one diagonally away.
		var along := offset.x * float(way.x) + offset.y * float(way.y)
		if along <= 1.0:
			continue
		var across := absf(offset.x * float(way.y)) + absf(offset.y * float(way.x))
		var cost := along + across * SPREAD
		if cost < best_cost:
			best_cost = cost
			best = button

	if best != null:
		best.grab_focus()


## Every button on this screen that can actually be pressed, in the order
## they were added — which is the order they were built, which is the order
## they read.
func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	var root := get_parent()
	if root == null:
		return out
	_collect(root, out)
	return out


func _collect(node: Node, into: Array[Button]) -> void:
	for child in node.get_children():
		var button := child as Button
		if button != null and button.is_visible_in_tree() and not button.disabled \
				and button.focus_mode != Control.FOCUS_NONE:
			into.append(button)
		_collect(child, into)


func _focused() -> Button:
	var owner_of := get_viewport().gui_get_focus_owner()
	return owner_of as Button


func _drop_focus() -> void:
	var here := _focused()
	if here != null:
		here.release_focus()


## The screen's Back button. Named by MenuSupport.footer_bar(), so every
## screen that uses the standard footer answers to B without being asked.
func _find_back() -> Button:
	for button in _buttons():
		if button.name == "BackButton":
			return button
	return null
