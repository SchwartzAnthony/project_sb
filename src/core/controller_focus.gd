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

## True while the last thing the player touched was the controller (or the
## arrow keys), on any screen. The Tutorial uses it to put the highlight on
## the one thing it lights up.
static var pad_in_use := false

## True when the stick has come back to the middle since its last push.
## This is what turns a held stick into ONE step rather than forty.
var _stick_ready: bool = true

## Where the first push of the stick lands: false = the top-left button
## (a menu reads from there), true = the one nearest the middle (the match).
var start_in_middle := false


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


## The Tutorial lit this button (24 Oct 2026): a controller player gets the
## highlight put straight on it, instead of hunting for it with the d-pad.
static func point_at(button: Control) -> void:
	var b := button as BaseButton
	if not pad_in_use or b == null or not b.is_visible_in_tree() or b.disabled:
		return
	if b.focus_mode == Control.FOCUS_NONE:
		b.focus_mode = Control.FOCUS_ALL
	b.grab_focus()


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
			pad_in_use = false
			_drop_focus()
		_last_mouse = motion.position
		return

	if _is_off():
		return

	var way := _direction(event)
	if way != Vector2i.ZERO:
		_using_pad = true
		pad_in_use = true
		# Only keep the push when it moved something (24 Oct 2026): a second
		# ControllerFocus over a part of the screen with no buttons (the
		# pause layer in the match) swallowed every d-pad push before the
		# match's own one saw it.
		if _step(way):
			get_viewport().set_input_as_handled()
		return

	# CONFIRM presses whatever is highlighted. Godot does this for a focused
	# Button by itself with ui_accept, but our `confirm` action is the one
	# the player rebound in Settings, so it is honoured here too.
	# A CONTROLLER'S A always counts (24 Oct 2026): a window that puts the
	# highlight on its first button itself (the Tutorial question) never saw
	# the d-pad move, so A on its highlighted Yes did nothing.
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_using_pad = true
		pad_in_use = true
	if GameKeys.pressed(event, "confirm") and _using_pad:
		var here := _focused()
		# Only a button on its own screen (24 Oct 2026): the time-out Pub
		# opens over the match, and its own ControllerFocus pressed the
		# EXHAUST ZONE button left highlighted on the pitch behind it.
		if here != null and get_parent() != null and get_parent().is_ancestor_of(here):
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

func _step(way: Vector2i) -> bool:
	var options := _buttons()
	if options.is_empty():
		return false

	var here := _focused()
	if here == null or not options.has(here):
		# NOTHING HIGHLIGHTED YET. Start at the top-left-most button, which
		# is what a person reads first.
		var first := options[0]
		if start_in_middle:
			# THE MATCH (24 Oct 2026): the choice you are being asked for
			# (the cards, ATTACK / DEFEND, the coin numbers) opens in the
			# middle, and the speed buttons sit top left. Start at the button
			# nearest the middle of the screen.
			var middle := get_viewport().get_visible_rect().get_center()
			for button in options:
				if button.get_global_rect().get_center().distance_to(middle) \
						< first.get_global_rect().get_center().distance_to(middle):
					first = button
			_take(first)
			return true
		for button in options:
			var a := button.get_global_rect().position
			var b := first.get_global_rect().position
			if a.y < b.y - 4.0 or (absf(a.y - b.y) <= 4.0 and a.x < b.x):
				first = button
		_take(first)
		return true

	var from := here.get_global_rect().get_center()
	var best: BaseButton = null
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
		_take(best)
	return true


## Highlight a button. Many match buttons are built never to take focus
## (FOCUS_NONE), so Space cannot press them by accident while you play with
## the mouse; the controller has no other way in, so it opens them up the
## moment it walks onto one (24 Oct 2026, the coin toss numbers).
func _take(button: BaseButton) -> void:
	if button.focus_mode == Control.FOCUS_NONE:
		button.focus_mode = Control.FOCUS_ALL
	button.grab_focus()


## Every button on this screen that can actually be pressed, in the order
## they were added — which is the order they were built, which is the order
## they read.
func _buttons() -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	var root := get_parent()
	if root == null:
		return out
	_collect(root, out)
	return out


func _collect(node: Node, into: Array[BaseButton]) -> void:
	for child in node.get_children():
		# BaseButton, not Button (24 Oct 2026): the save mugs and the base
		# buildings are picture buttons (TextureButton), and a controller
		# could not reach them.
		var button := child as BaseButton
		# Buttons that never take focus count too: _take opens them up.
		if button != null and button.is_visible_in_tree() and not button.disabled:
			into.append(button)
		_collect(child, into)


func _focused() -> BaseButton:
	var owner_of := get_viewport().gui_get_focus_owner()
	return owner_of as BaseButton


func _drop_focus() -> void:
	var here := _focused()
	if here != null:
		here.release_focus()


## The screen's Back button. Named by MenuSupport.footer_bar(), so every
## screen that uses the standard footer answers to B without being asked.
func _find_back() -> BaseButton:
	for button in _buttons():
		if button.name == "BackButton":
			return button
	return null
