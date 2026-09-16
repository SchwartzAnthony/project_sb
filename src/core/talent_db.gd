class_name TalentDB
extends RefCounted

# =============================================================
#  TALENTS.CSV — the talent tree
#
#  A talent is a thing you choose. It sits in a TREE (a column), on a
#  TIER (a row), and usually hangs off a PARENT talent you must take
#  first. Taking it spends talent points and applies its Effects.
#
#  THE COLUMNS
#    ID           unique. Other rows point at this, and taking the talent
#                 unlocks this name — so  unlocked:high_press  works
#                 anywhere afterwards.
#    Name         what the player sees
#    Tree         which column it belongs to. Any word. New word = new tree.
#    Tier         which row, 1 at the top. Just for layout.
#    Parent       the ID that must be taken first. Blank = a root talent.
#    Requires     an EXTRA condition on top of the parent. Blank = none.
#    Cost         talent points. Blank or 0 = free.
#    Effects      what taking it does, in the usual language:
#                 count:tune_press_speed+12   unlock:Fire Brew   flag:x
#    Description  one line for the player
#    Art          PNG name in assets/talents/. Optional.
#    Notes        yours
#
#  ------------------------------------------------------------
#  CHANGING A TUNING NUMBER FROM A TALENT
#  ------------------------------------------------------------
#  Any counter named  tune_<something>  is ADDED to the Tuning.csv value
#  of that name before a match. So:
#
#      Effects:  count:tune_press_speed+12
#
#  makes press_speed 92 + 12 = 104 for that save, forever, with no code.
#  It works for any row in Tuning.csv. Whole numbers only, so it suits
#  speeds, radii and counts rather than the 0-to-1 chances.
#
#  ------------------------------------------------------------
#  WHERE TALENT POINTS COME FROM
#  ------------------------------------------------------------
#  A row in Progression.csv:
#
#      talent_point,match_ended,unlocked:Talent Tree,count:talent_points+1,,
#
#  Delete that row and nothing earns points. Set every Cost to blank and
#  the tree becomes "take everything you have unlocked", which is a
#  perfectly good design too.
# =============================================================

const DATA_DIR := "res://data/"
## The counter talents are paid for with.
const POINTS := "talent_points"

static var _instance: TalentDB

## Each entry: id, name, tree, tier, parent, requires, cost, effects,
## description, art, where
var talents: Array[Dictionary] = []
var problems: Array[String] = []


static func get_db() -> TalentDB:
	if _instance == null:
		_instance = TalentDB.new()
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
	talents.clear()
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

	_validate()


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

	# A talents file is any CSV with an ID, a Tree and a Tier column.
	if not (columns.has("id") and columns.has("tree") and columns.has("tier")):
		return

	var short_name := path.get_file()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		if id_text == "":
			continue

		talents.append({
			"id": id_text,
			"name": _cell(row, columns, "name"),
			"tree": _cell(row, columns, "tree"),
			"tier": _cell_int(row, columns, "tier", 1),
			"parent": _cell(row, columns, "parent"),
			"requires": _cell(row, columns, "requires"),
			"cost": _cell_int(row, columns, "cost", 0),
			"effects": _cell(row, columns, "effects"),
			"description": _cell(row, columns, "description"),
			"art": _cell(row, columns, "art"),
			"where": "%s row %d" % [short_name, i + 1],
		})


# =============================================================
#  QUERIES
# =============================================================

## Tree names, in the order they first appear in the file — so reordering
## the spreadsheet reorders the columns on screen.
func tree_names() -> Array[String]:
	var out: Array[String] = []
	for entry in talents:
		var tree := String(entry["tree"])
		if tree != "" and not out.has(tree):
			out.append(tree)
	return out


func in_tree(tree: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in talents:
		if String(entry["tree"]) == tree:
			out.append(entry)
	return out


func find(talent_id: String) -> Dictionary:
	var key := CardDatabase._normalise(talent_id)
	for entry in talents:
		if CardDatabase._normalise(String(entry["id"])) == key:
			return entry
	return {}


## Taking a talent unlocks its ID, so this is just an unlock test. That
## means  unlocked:high_press  works in any Requires anywhere in the game.
static func is_taken(entry: Dictionary, state: GameState) -> bool:
	if state == null or entry.is_empty():
		return false
	return state.is_unlocked(String(entry["id"]))


## Three states, in the order they are checked:
##   "taken"      already yours
##   "available"  parent taken, condition met, points affordable
##   "locked"     anything else — the screen greys it and says why
static func status(entry: Dictionary, state: GameState, db: TalentDB) -> String:
	if is_taken(entry, state):
		return "taken"
	if state == null:
		return "locked"

	var parent := String(entry["parent"]).strip_edges()
	if parent != "" and not state.is_unlocked(parent):
		return "locked"
	if not DialogueGrammar.test(String(entry["requires"]), state):
		return "locked"
	if state.count(POINTS) < int(entry["cost"]):
		return "locked"
	return "available"


## Why a talent cannot be taken, in words a player can read.
static func why_locked(entry: Dictionary, state: GameState, db: TalentDB) -> String:
	if state == null:
		return ""

	var parent := String(entry["parent"]).strip_edges()
	if parent != "" and not state.is_unlocked(parent):
		var mother := db.find(parent)
		var mother_name := String(mother["name"]) if not mother.is_empty() else parent
		return "Take %s first." % mother_name

	var requires := String(entry["requires"])
	if not DialogueGrammar.test(requires, state):
		return DialogueGrammar.describe(requires)

	var cost := int(entry["cost"])
	if state.count(POINTS) < cost:
		return "Costs %d talent point%s — you have %d." % [
			cost, "" if cost == 1 else "s", state.count(POINTS)]
	return ""


# =============================================================
#  TAKING ONE
# =============================================================

## Spend the points, unlock the ID, apply the Effects. Returns any actions
## that need the scene tree (a talent could play a story, for instance).
static func take(entry: Dictionary, state: GameState, db: TalentDB) -> Array[Dictionary]:
	var nothing: Array[Dictionary] = []
	if state == null or entry.is_empty():
		return nothing
	if status(entry, state, db) != "available":
		return nothing

	var cost := int(entry["cost"])
	if cost > 0:
		state.add_count(POINTS, -cost)

	# Unlocking the ID is what "taken" means, so it is remembered and
	# testable everywhere without a second mechanism.
	state.unlock(String(entry["id"]))
	print("[talents] took '%s'." % entry["name"])

	return Progression.run_actions(String(entry["effects"]), state)


# =============================================================
#  VALIDATION
# =============================================================

func _validate() -> void:
	var seen: Dictionary = {}
	for entry in talents:
		var key := CardDatabase._normalise(String(entry["id"]))
		if seen.has(key):
			problems.append("%s: talent ID '%s' is already used by %s"
				% [entry["where"], entry["id"], seen[key]])
		else:
			seen[key] = entry["where"]

	for entry in talents:
		if String(entry["name"]).strip_edges() == "":
			problems.append("%s: talent '%s' has no Name" % [entry["where"], entry["id"]])
		if String(entry["tree"]).strip_edges() == "":
			problems.append("%s: talent '%s' has no Tree, so it has no column to live in"
				% [entry["where"], entry["id"]])

		var parent := String(entry["parent"]).strip_edges()
		if parent != "":
			if find(parent).is_empty():
				problems.append("%s: Parent '%s' is not a talent that exists"
					% [entry["where"], parent])
			elif CardDatabase._normalise(parent) == CardDatabase._normalise(String(entry["id"])):
				problems.append("%s: '%s' is its own Parent" % [entry["where"], entry["id"]])
			else:
				var mother := find(parent)
				if String(mother["tree"]) != String(entry["tree"]):
					problems.append("%s: '%s' is in tree '%s' but its Parent '%s' is in '%s' — a line cannot be drawn between two columns"
						% [entry["where"], entry["id"], entry["tree"], parent, mother["tree"]])
				elif int(mother["tier"]) >= int(entry["tier"]):
					problems.append("%s: '%s' is on Tier %d but its Parent is on Tier %d — a child must sit below its parent"
						% [entry["where"], entry["id"], int(entry["tier"]), int(mother["tier"])])

		for complaint in DialogueGrammar.complaints(String(entry["requires"]), false):
			problems.append("%s: Requires %s" % [entry["where"], complaint])
		for complaint2 in DialogueGrammar.complaints(String(entry["effects"]), true):
			problems.append("%s: Effects %s" % [entry["where"], complaint2])

		if int(entry["cost"]) < 0:
			problems.append("%s: Cost cannot be negative" % entry["where"])

	_check_loops()


## A talent whose parent chain comes back round to itself would hang the
## screen, so it is caught here rather than at 3am.
func _check_loops() -> void:
	for entry in talents:
		var seen: Array[String] = [CardDatabase._normalise(String(entry["id"]))]
		var at := String(entry["parent"]).strip_edges()
		var steps := 0
		while at != "" and steps < 64:
			var key := CardDatabase._normalise(at)
			if seen.has(key):
				problems.append("%s: '%s' is part of a Parent loop — follow the Parent column and it comes back to itself"
					% [entry["where"], entry["id"]])
				break
			seen.append(key)
			var mother := find(at)
			if mother.is_empty():
				break
			at = String(mother["parent"]).strip_edges()
			steps += 1


func all_conditions() -> Array[String]:
	var out: Array[String] = []
	for entry in talents:
		var condition := String(entry["requires"])
		if condition.strip_edges() != "":
			out.append(condition)
	return out


func all_effects() -> Array[String]:
	var out: Array[String] = []
	for entry in talents:
		var effects := String(entry["effects"])
		if effects.strip_edges() != "":
			out.append(effects)
	return out


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


func _cell_int(row: PackedStringArray, columns: Dictionary, key: String,
		fallback: int) -> int:
	var raw := _cell(row, columns, key)
	return int(raw) if raw.is_valid_int() else fallback
