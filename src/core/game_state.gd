class_name GameState
extends RefCounted

# =============================================================
#  GAME STATE — what the story remembers between scenes and runs
#
#  Four kinds of memory, and everything the game will ever need to
#  remember fits into one of them:
#
#    FLAGS     on/off facts.  "spared_the_keeper", "met_lorelei"
#    COUNTERS  numbers.       "wood" = 40, "wins" = 3, "chapter" = 2
#    TEXTS     words.         "next_class" = "Lorelei", "rival" = "Heatwave"
#    UNLOCKS   a list of names you have earned. Cards, classes, anything.
#
#  That is deliberately generic. When you add base building, an achievement
#  list or a shop, they are counters and flags — NOTHING in this file has to
#  change, and the dialogue CSV can already read and write them.
#
#  It saves to user://story_state.json, which lives beside the game's other
#  save data, NOT in your project folder. Nothing here ever writes to res://.
# =============================================================

## WHERE PROGRESS IS KEPT.
##
## A `static var` rather than a `const` for one reason: the TUTORIAL BASE
## points it at a save of its own so that nothing you do in there can touch
## your real game. See tutorial_base.gd.
static var SAVE_PATH := "user://story_state.json"
const META_KEY := "cw_game_state"

var flags: Dictionary = {}       # name (lower) -> true
var counters: Dictionary = {}    # name (lower) -> int
var texts: Dictionary = {}       # name (lower) -> String
var unlocks: Dictionary = {}     # name (lower) -> the original spelling

## THE NAME BOOK: key -> the spelling it was first written with.
##
## Names are squashed down to letters and digits so that "First Win" and
## "first_win" are the same flag. That is what you want for matching, and
## exactly what you do NOT want when something has to be shown to a player:
## "firstwin" on screen looks like a bug. So the first time a name is used,
## the spelling is kept here, and pretty() reads it back out.
var names: Dictionary = {}

## Everything that has been applied this session, newest last. Printed by the
## dialogue screen so you can see what your choices actually did.
var history: Array[String] = []


# =============================================================
#  ACCESS — one instance per run, parked on the SceneTree
#
#  Same trick TeamSelection uses: no autoload to register, and it survives
#  change_scene_to_file().
# =============================================================

static func fetch(tree: SceneTree) -> GameState:
	if tree == null:
		return GameState.new()
	if tree.has_meta(META_KEY):
		var existing := tree.get_meta(META_KEY) as GameState
		if existing != null:
			return existing

	var fresh := GameState.new()
	fresh.load_from_disk()
	tree.set_meta(META_KEY, fresh)
	return fresh


static func forget(tree: SceneTree) -> void:
	if tree != null and tree.has_meta(META_KEY):
		tree.remove_meta(META_KEY)


# =============================================================
#  READING
# =============================================================

func has_flag(flag_name: String) -> bool:
	return bool(flags.get(_key(flag_name), false))


func count(counter_name: String) -> int:
	return int(counters.get(_key(counter_name), 0))


func text(text_name: String, fallback: String = "") -> String:
	var raw := String(texts.get(_key(text_name), "")).strip_edges()
	return raw if raw != "" else fallback


func is_unlocked(thing: String) -> bool:
	return unlocks.has(_key(thing))


## Everything unlocked so far, in the spelling it was written with.
func unlocked_names() -> Array[String]:
	var out: Array[String] = []
	for key in unlocks.keys():
		out.append(String(unlocks[key]))
	out.sort()
	return out


# =============================================================
#  WRITING
# =============================================================

## A readable version of a stored name, for anything a player will see.
## Falls back to the squashed key when the spelling was never recorded — an
## old save, for instance — so it can never come back blank.
func pretty(key_or_name: String) -> String:
	var key := _key(key_or_name)
	var spelling := String(names.get(key, ""))
	if spelling == "":
		return key_or_name.strip_edges().capitalize()
	return spelling.replace("_", " ").strip_edges().capitalize()


func set_flag(flag_name: String, value: bool = true) -> void:
	var key := _remember(flag_name)
	if key == "":
		return
	if value:
		flags[key] = true
	else:
		flags.erase(key)
	history.append("flag %s = %s" % [key, value])


## `delta` adds to what is there. Use set_count() to overwrite instead.
func add_count(counter_name: String, delta: int) -> void:
	var key := _remember(counter_name)
	if key == "":
		return
	counters[key] = count(key) + delta
	history.append("%s %+d -> %d" % [key, delta, counters[key]])


func set_count(counter_name: String, value: int) -> void:
	var key := _remember(counter_name)
	if key == "":
		return
	counters[key] = value
	history.append("%s = %d" % [key, value])


func set_text(text_name: String, value: String) -> void:
	var key := _remember(text_name)
	if key == "":
		return
	var clean := value.strip_edges()
	if clean == "":
		texts.erase(key)
	else:
		texts[key] = clean
	history.append("%s = \"%s\"" % [key, clean])


func unlock(thing: String) -> void:
	var clean := thing.strip_edges()
	if clean == "":
		return
	unlocks[_remember(clean)] = clean
	history.append("unlocked %s" % clean)


func reset() -> void:
	flags.clear()
	counters.clear()
	texts.clear()
	unlocks.clear()
	names.clear()
	history.clear()


# =============================================================
#  SAVING
# =============================================================

func save_to_disk() -> void:
	var payload := {
		"flags": flags.keys(),
		"counters": counters,
		"texts": texts,
		"unlocks": unlocks.values(),
		"names": names,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[state] Could not write %s — progress will not persist." % SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var raw_text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		push_warning("[state] %s is not readable — starting fresh." % SAVE_PATH)
		return

	var data: Dictionary = parsed
	reset()

	for entry in _as_array(data.get("flags", [])):
		flags[_key(String(entry))] = true

	var saved_counters: Variant = data.get("counters", {})
	if saved_counters is Dictionary:
		for key in (saved_counters as Dictionary).keys():
			counters[_key(String(key))] = int((saved_counters as Dictionary)[key])

	var saved_texts: Variant = data.get("texts", {})
	if saved_texts is Dictionary:
		for key in (saved_texts as Dictionary).keys():
			texts[_key(String(key))] = String((saved_texts as Dictionary)[key])

	# The name book is read BEFORE anything else touches it, so that unlock()
	# below does not overwrite a good spelling with the same one.
	var saved_names: Variant = data.get("names", {})
	if saved_names is Dictionary:
		for key in (saved_names as Dictionary).keys():
			names[_key(String(key))] = String((saved_names as Dictionary)[key])

	for entry in _as_array(data.get("unlocks", [])):
		unlock(String(entry))

	history.clear()   # loading is not a choice you made


## Where the save actually lives on disk, for the "where is my progress" question.
static func save_location() -> String:
	return ProjectSettings.globalize_path(SAVE_PATH)


# =============================================================
#  HELPERS
# =============================================================

## Names are matched case- and space-insensitively, so "Spared The Keeper",
## "spared_the_keeper" and "sparedthekeeper" are the same flag. That stops a
## typo in a spreadsheet silently creating a second, never-read flag.
## Squash a name to its key AND keep the spelling, so it can be shown later.
func _remember(display: String) -> String:
	var key := _key(display)
	if key != "" and not names.has(key):
		names[key] = display.strip_edges()
	return key


static func _key(name_text: String) -> String:
	var out := ""
	for c in name_text.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


static func _as_array(value: Variant) -> Array:
	return value if value is Array else []
