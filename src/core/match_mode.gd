class_name MatchMode
extends RefCounted

# =============================================================
#  MATCHMODES.CSV — the two kinds of match, and any you add
#
#  A SEASON MATCH is the league. It is against another human side, it goes
#  in the table, it runs the full ninety minutes with three Stars rotating
#  at HOLD UP, and winning one moves the season on towards its big unlock.
#
#  A QUICK MATCH is a single run for resources. No clock, one Star, nothing
#  written to the table. You play it to come away with wheat, coins, recipes
#  and achievement progress — which is how you get the buildings that later
#  produce those things for you.
#
#  Both are the same match code. The difference is a row in a spreadsheet.
#
#  THE COLUMNS  (data/MatchModes.csv)
#    ID              what a menu button's action names: match:quick
#    Name            what the player sees
#    Records Season  yes = the result goes in the table and moves the season
#                    on. no  = it never touches the table
#    Timer           minutes on the clock. 0 = NO CLOCK: the match ends when
#                    the rounds run out instead of when time does
#    Cycles          how many cycles (a season match is 3)
#    Rounds          rounds per cycle (a season match is 3)
#    Star Rotation   yes = HOLD UP swaps your Star between cycles.
#                    no  = one Star for the whole match
#    Opponent        what you are playing. `team` is another side. Anything
#                    else is read by whatever builds that kind of opponent —
#                    `nest` is the enemy mode, which is designed but not
#                    built yet (see ENEMIES_AND_QUICK_MATCH.md)
#    Requires        the usual condition language, so a mode can be locked
#    Description     the hover text on its button
#
#  ADDING A MODE is a row. A "Cup Tie" that is 5 cycles with no table entry,
#  a "Training" mode with one cycle and no opponent rewards — neither needs
#  a line of code.
# =============================================================

const DATA_DIR := "res://data/"
const META_KEY := "cw_match_mode"

## The mode a match falls back to when nothing was chosen — running
## main_scene.tscn straight from the editor, for instance.
const DEFAULT_ID := "season"

static var _instance: MatchMode = null

## id -> the row, as a Dictionary.
var modes: Dictionary = {}
var problems: Array[String] = []


static func get_db() -> MatchMode:
	if _instance == null:
		_instance = MatchMode.new()
		_instance.load_all()
	return _instance


## RE-READ THE SPREADSHEETS FROM DISK.
##
## NOT CALLED `reload()`. Every class_name in Godot is also a Script object,
## and Script already has a built-in reload() — so `BaseDB.reload()` resolved
## to THAT and printed
##
##     Cannot reload script while instances exist.
##
## while quietly never calling this at all. Naming it reload_files() is the
## whole fix. If you add a loader of your own, avoid reload(), free(),
## duplicate() and get_name() for the same reason.
static func reload_files() -> void:
	_instance = null
	get_db()


# =============================================================
#  LOADING
# =============================================================

func load_all() -> void:
	modes.clear()
	problems.clear()

	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		problems.append("Could not open %s" % DATA_DIR)
		return

	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if file_name.to_lower().ends_with(".csv"):
			_load_csv(DATA_DIR + file_name)

	if modes.is_empty():
		# No MatchModes.csv at all. Rather than refuse to play, fall back to
		# the season match the game has always been.
		modes[DEFAULT_ID] = _fallback_season_row()
		problems.append("No MatchModes.csv found — using a built-in season match. Add data/MatchModes.csv to change how a match is shaped.")


func _load_csv(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var rows := CardDatabase.parse_csv(file.get_as_text())
	file.close()
	if rows.size() < 2:
		return

	var columns: Dictionary = {}
	var header: PackedStringArray = rows[0]
	for i in header.size():
		var key := CardDatabase._normalise(header[i])
		if key != "":
			columns[key] = i

	# A modes file is any CSV with both Records Season and Star Rotation.
	# Nothing else in the project has either, so yours can be called anything.
	if not (columns.has("recordsseason") and columns.has("starrotation")):
		return

	var short_name := path.get_file()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		if id_text == "":
			continue

		var key := CardDatabase._normalise(id_text)
		if modes.has(key):
			problems.append("%s row %d: there is already a mode called '%s'."
				% [short_name, i + 1, id_text])
			continue

		modes[key] = {
			"id": id_text,
			"name": _first(_cell(row, columns, "name"), id_text),
			"records": _yes(_cell(row, columns, "recordsseason"), true),
			"timer": _number(_cell(row, columns, "timer"), 90.0),
			"cycles": _whole(_cell(row, columns, "cycles"), 3),
			"rounds": _whole(_cell(row, columns, "rounds"), 3),
			"rotation": _yes(_cell(row, columns, "starrotation"), true),
			"opponent": _first(_cell(row, columns, "opponent"), "team"),
			# WHICH SCREEN THE MODE PLAYS IN. `match` is the pitch; `adventure`
			# is the run. A word ScenePaths.for_name() understands, so a new
			# mode can point at a new screen without touching any code.
			"scene": _first(_cell(row, columns, "scene"), "match"),
			"requires": _cell(row, columns, "requires"),
			# WHAT PLAYING IT IS WORTH. Written in the same language as a
			# dialogue Effects column, so everything that works there works
			# here:  count:scrap+3 ; unlock:The Cup ; set:last_friendly=won
			#
			#   Rewards         applied whatever the score
			#   Rewards On Win  applied as well, only if you won
			#
			# This is how a friendly pays. See _full_time() in main_scene.gd.
			"rewards": _cell(row, columns, "rewards"),
			"rewards_win": _cell(row, columns, "rewardsonwin"),
			"description": _cell(row, columns, "description"),
			"where": "%s row %d" % [short_name, i + 1],
		}


static func _fallback_season_row() -> Dictionary:
	return {
		"id": DEFAULT_ID, "name": "Season Match", "records": true,
		"timer": 90.0, "cycles": 3, "rounds": 3, "rotation": true,
		"opponent": "team", "scene": "match", "requires": "",
		"rewards": "", "rewards_win": "", "description": "",
		"where": "(built in)",
	}


# =============================================================
#  ASKING IT THINGS
# =============================================================

func find(mode_id: String) -> Dictionary:
	var key := CardDatabase._normalise(mode_id)
	if modes.has(key):
		return modes[key]
	return {}


## Every mode you could start right now, in file order.
func available(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in modes.keys():
		var entry: Dictionary = modes[key]
		if DialogueGrammar.test(String(entry["requires"]), state):
			out.append(entry)
	return out


# =============================================================
#  RIDING INTO THE MATCH
#
#  Same trick TeamSelection and GameState use: parked on the SceneTree, so
#  it survives change_scene_to_file() with no autoload to register.
# =============================================================

## Say which mode the next match is. Called by whatever button starts it.
static func choose(tree: SceneTree, mode_id: String) -> void:
	if tree != null:
		tree.set_meta(META_KEY, mode_id)


## The mode the match should run as. Never empty — falls back to the season
## match, which is what the game did before modes existed.
static func current(tree: SceneTree) -> Dictionary:
	var db := get_db()
	var wanted := DEFAULT_ID
	if tree != null and tree.has_meta(META_KEY):
		wanted = String(tree.get_meta(META_KEY))

	var found := db.find(wanted)
	if found.is_empty():
		found = db.find(DEFAULT_ID)
	if found.is_empty():
		found = _fallback_season_row()
	return found


## Forget the chosen mode, so the next match is a season match again.
static func clear(tree: SceneTree) -> void:
	if tree != null and tree.has_meta(META_KEY):
		tree.remove_meta(META_KEY)


# =============================================================
#  HELPERS
# =============================================================

func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()


static func _first(text: String, fallback: String) -> String:
	return text if text.strip_edges() != "" else fallback


## "yes", "true", "y" and "1" are all yes. Blank keeps the default, so a
## column you have not filled in yet behaves the way the game always did.
static func _yes(text: String, fallback: bool) -> bool:
	var clean := text.strip_edges().to_lower()
	if clean == "":
		return fallback
	return clean in ["yes", "true", "y", "1", "on"]


static func _number(text: String, fallback: float) -> float:
	var clean := text.strip_edges()
	return float(clean) if clean.is_valid_float() else fallback


static func _whole(text: String, fallback: int) -> int:
	var clean := text.strip_edges()
	return int(clean) if clean.is_valid_int() else fallback
