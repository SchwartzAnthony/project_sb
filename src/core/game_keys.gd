class_name GameKeys
extends RefCounted

# =============================================================
#  THE KEYS — one spreadsheet, and the player may change any of them
#
#  ============ WHY THIS FILE EXISTS ============
#
#  Before this, every screen that wanted a key wrote the key into itself:
#  the pause menu knew about Escape, the HUD knew about A and F, the dialogue
#  screen knew about Space. Nobody could rebind anything, and adding a key
#  meant remembering all the places it might clash.
#
#  Now there is ONE list — res://data/Keys.csv — and everything reads it.
#
#      Action           the short word the game uses. Never shown to a player
#      Label            what the settings screen calls it
#      Group            which heading it sits under in Settings
#      Default Key      the key it starts on, written the way you would say
#                       it: Escape, Space, A, F12, Left Arrow
#      Default Button   the controller button, if it has one
#      Notes            for you, not the game
#
#  Add a row, and the action exists, is rebindable, and appears in Settings.
#  No code.
#
#  ============ HOW A SCREEN USES IT ============
#
#      func _input(event: InputEvent) -> void:
#          if GameKeys.pressed(event, "pause"):
#              ...
#
#  `pressed` is true for the key AND for the controller button AND for
#  whatever the player has rebound it to, which is the whole point: a screen
#  asks about the ACTION and never about the key.
#
#  ============ WHERE A CHANGED KEY IS KEPT ============
#
#  user://settings.json, beside your save, under "keys". The CSV is the
#  factory setting; that file is what the player changed. Deleting it puts
#  everything back to the spreadsheet.
# =============================================================

const KEYS_PATH := "res://data/Keys.csv"
const INSTALLED_KEY := "cw_keys_installed"

## Action -> { "label", "group", "key", "button", "notes" }
static var actions: Dictionary = {}
static var order: Array[String] = []


# =============================================================
#  SETTING THEM UP
# =============================================================

## Build the InputMap from the CSV and from whatever the player has changed.
## Safe to call as often as you like — it only does the work once per run,
## unless `force` says otherwise (the settings screen passes true after a
## rebind).
static func install(tree: SceneTree, force: bool = false) -> void:
	if tree != null and tree.has_meta(INSTALLED_KEY) and not force:
		return
	if tree != null:
		tree.set_meta(INSTALLED_KEY, true)

	actions.clear()
	order.clear()

	var rows := MenuSupport.read_csv(KEYS_PATH)
	if rows.is_empty():
		rows = _built_in()
		print("[keys] No usable %s — using the built-in keys." % KEYS_PATH)

	var changed := GameSettings.load_all().get("keys", {}) as Dictionary

	for row in rows:
		var action := MenuSupport.field(row, "Action").strip_edges()
		if action == "":
			continue
		var entry := {
			"label": MenuSupport.field(row, "Label", action.capitalize()),
			"group": MenuSupport.field(row, "Group", "General"),
			"key": MenuSupport.field(row, "Default Key"),
			"button": MenuSupport.field(row, "Default Button"),
			"notes": MenuSupport.field(row, "Notes"),
		}
		# What the player changed wins over the spreadsheet.
		if changed.has(action):
			entry["key"] = String(changed[action])
		actions[action] = entry
		order.append(action)
		_register(action, entry)

	print("[keys] %d action(s) ready." % order.size())


static func _register(action: String, entry: Dictionary) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)

	var code := key_from_text(String(entry["key"]))
	if code != KEY_NONE:
		var press := InputEventKey.new()
		press.physical_keycode = code
		InputMap.action_add_event(action, press)

	var button := button_from_text(String(entry["button"]))
	if button >= 0:
		var pad := InputEventJoypadButton.new()
		pad.button_index = button as JoyButton
		InputMap.action_add_event(action, pad)


## The bare minimum, used only if Keys.csv cannot be read at all. It keeps
## the game playable rather than leaving it with no keys.
static func _built_in() -> Array[Dictionary]:
	return [
		{"action": "pause", "label": "Pause / sub menu", "group": "General",
			"defaultkey": "Escape", "defaultbutton": "Start", "notes": ""},
		{"action": "confirm", "label": "Confirm", "group": "General",
			"defaultkey": "Space", "defaultbutton": "A", "notes": ""},
		{"action": "cancel", "label": "Back", "group": "General",
			"defaultkey": "Backspace", "defaultbutton": "B", "notes": ""},
	]


# =============================================================
#  ASKING ABOUT AN ACTION
# =============================================================

## Did this event just press the key (or button) bound to `action`?
##
## Repeat presses from holding the key down are ignored, which is what a menu
## almost always wants.
static func pressed(event: InputEvent, action: String) -> bool:
	if event == null:
		return false
	if not InputMap.has_action(action):
		# An action nobody registered is not an error worth crashing over —
		# it just never fires, and the Output panel says so once.
		return false
	return event.is_action_pressed(action, false, true)


## Is it being held down right now? For the formation overlay, which is
## shown while the key is down rather than toggled.
static func held(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


## What the settings screen prints beside an action: "Escape", "Space", "A".
static func label_for(action: String) -> String:
	var entry: Dictionary = actions.get(action, {})
	return String(entry.get("key", "—"))


static func describe(action: String) -> String:
	var entry: Dictionary = actions.get(action, {})
	return String(entry.get("label", action.capitalize()))


## Which actions sit under a heading, in the order the CSV lists them.
static func in_group(group: String) -> Array[String]:
	var out: Array[String] = []
	for action in order:
		if String((actions[action] as Dictionary).get("group", "")) == group:
			out.append(action)
	return out


static func groups() -> Array[String]:
	var out: Array[String] = []
	for action in order:
		var group := String((actions[action] as Dictionary).get("group", "General"))
		if not out.has(group):
			out.append(group)
	return out


# =============================================================
#  CHANGING ONE
# =============================================================

## Bind `action` to whatever key this event is. Returns "" when it worked, or
## a sentence saying why it did not — which is how the settings screen tells
## you that Escape is already the pause key.
static func rebind(tree: SceneTree, action: String, event: InputEventKey) -> String:
	if event == null or event.physical_keycode == KEY_NONE:
		return "That is not a key."
	var text := text_from_key(event.physical_keycode)

	for other in order:
		if other == action:
			continue
		if String((actions[other] as Dictionary).get("key", "")).to_lower() == text.to_lower():
			return "%s is already %s." % [text, describe(other)]

	var settings := GameSettings.load_all()
	var changed: Dictionary = settings.get("keys", {})
	changed[action] = text
	settings["keys"] = changed
	GameSettings.save_all(settings)

	install(tree, true)
	return ""


## Put every key back to what Keys.csv says.
static func reset_all(tree: SceneTree) -> void:
	var settings := GameSettings.load_all()
	settings["keys"] = {}
	GameSettings.save_all(settings)
	install(tree, true)


# =============================================================
#  WRITING A KEY THE WAY A PERSON WOULD
#
#  Keys.csv says "Escape", not "KEY_ESCAPE" or "4194305". These two
#  functions are the translation, and they are deliberately forgiving:
#  "Left Arrow", "left arrow" and "Left" all mean the same key.
# =============================================================

static func key_from_text(text: String) -> Key:
	var clean := text.strip_edges()
	if clean == "":
		return KEY_NONE

	match clean.to_lower():
		"escape", "esc":            return KEY_ESCAPE
		"space", "spacebar":        return KEY_SPACE
		"enter", "return":          return KEY_ENTER
		"backspace":                return KEY_BACKSPACE
		"tab":                      return KEY_TAB
		"shift":                    return KEY_SHIFT
		"ctrl", "control":          return KEY_CTRL
		"alt":                      return KEY_ALT
		"left arrow", "left":       return KEY_LEFT
		"right arrow", "right":     return KEY_RIGHT
		"up arrow", "up":           return KEY_UP
		"down arrow", "down":       return KEY_DOWN

	# Anything else is handed to Godot, which understands "A", "F12", "Comma"
	# and every other key name it prints itself.
	var code := OS.find_keycode_from_string(clean)
	if code == KEY_NONE:
		push_warning("[keys] Keys.csv says '%s', which is not a key name." % text)
	return code


static func text_from_key(code: Key) -> String:
	if code == KEY_NONE:
		return "—"
	return OS.get_keycode_string(code)


## "A", "Start", "Left Shoulder" -> a controller button. -1 for none, which
## is what an empty column means.
static func button_from_text(text: String) -> int:
	match text.strip_edges().to_lower():
		"a", "cross":                       return JOY_BUTTON_A
		"b", "circle":                      return JOY_BUTTON_B
		"x", "square":                       return JOY_BUTTON_X
		"y", "triangle":                     return JOY_BUTTON_Y
		"start", "menu":                     return JOY_BUTTON_START
		"back", "select", "view":            return JOY_BUTTON_BACK
		"left shoulder", "lb", "l1":         return JOY_BUTTON_LEFT_SHOULDER
		"right shoulder", "rb", "r1":        return JOY_BUTTON_RIGHT_SHOULDER
		"left stick", "l3":                  return JOY_BUTTON_LEFT_STICK
		"right stick", "r3":                 return JOY_BUTTON_RIGHT_STICK
		"dpad up":                           return JOY_BUTTON_DPAD_UP
		"dpad down":                         return JOY_BUTTON_DPAD_DOWN
		"dpad left":                         return JOY_BUTTON_DPAD_LEFT
		"dpad right":                        return JOY_BUTTON_DPAD_RIGHT
	# Triggers are axes rather than buttons on most pads, so they are not
	# bound here. A row asking for one is simply left without a button.
	return -1
