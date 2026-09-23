class_name BaseDB
extends RefCounted

# =============================================================
#  THE BASE — buildings and visitors, both from CSV
#
#  Two tables, loaded the same way as everything else. Drop a row in,
#  press play, it is on the base screen.
#
#  ------------------------------------------------------------
#  Buildings.csv — what stands in your base
#  ------------------------------------------------------------
#    ID           a unique name, used in the report and nowhere else
#    Name         what the player sees on the sign
#    Description  one line, shown under the name
#    Requires     when it becomes usable. Blank = always.
#                 Usually  unlocked:Brewery  , but any condition works:
#                 count:matches_played>=3 is just as valid.
#    Art          PNG name, looked for in assets/base/. Optional — a
#                 coloured plaque with the name is drawn without it.
#    X, Y         where it sits, as a fraction of the screen. 0,0 is the
#                 top-left corner and 1,1 the bottom-right. 0.5,0.5 is
#                 the middle.
#    Action       what clicking it does. Same words as Progression.csv:
#                 story:brewery_intro   goto:builder   unlock:something
#                 announce:Text         Blank = just show its description.
#    Notes        yours; ignored by the game.
#
#  A LOCKED building is still drawn, greyed out, with its requirement
#  shown underneath. Seeing what you have not earned yet is most of what
#  makes a base feel like a base.
#
#  ------------------------------------------------------------
#  Visitors.csv — who is standing about, and what they want
#  ------------------------------------------------------------
#    ID           unique
#    Name         shown under the portrait
#    Portrait     PNG name, looked for in assets/portraits/
#    Requires     when they turn up. Blank = always there.
#    Story        the Dialogue.csv Scene to play when clicked
#    X, Y         where they stand, same 0..1 fractions
#    Once         true = they leave for good once you have talked to them
#    Notes        yours
#
#  A visitor is just a portrait wired to a dialogue scene. Everything
#  about who they are and why they came is written in Dialogue.csv.
# =============================================================

## WHICH FOLDER THE BASE IS BUILT FROM.
##
## `res://data/` is the real base. The TUTORIAL BASE points this at
## `res://data/tutorial/` instead and reloads — see tutorial_base.gd — which
## is the whole trick behind "an enclosed environment that is separate to the
## game": same screen, same code, a different folder of spreadsheets.
##
## So it is a `static var` rather than a `const`. Put a Buildings.csv and a
## Visitors.csv in res://data/tutorial/ and that is the tutorial base; the
## real one never sees them.
static var DATA_DIR := "res://data/"
## Flag prefix remembering that a one-time visitor has been spoken to.
const TALKED_PREFIX := "visitor_talked_"

static var _instance: BaseDB

## Each entry: id, name, description, requires, art, x, y, action, where
var buildings: Array[Dictionary] = []
## Each entry: id, name, portrait, requires, story, x, y, once, where
var visitors: Array[Dictionary] = []
var problems: Array[String] = []


static func get_db() -> BaseDB:
	if _instance == null:
		_instance = BaseDB.new()
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
	buildings.clear()
	visitors.clear()
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

	# A buildings file has an Action column; a visitors file has a Story
	# column. Both need an ID, which is what tells them apart from every
	# other CSV in the folder.
	if not columns.has("id"):
		return
	var is_buildings := columns.has("action") and columns.has("name")
	# ============ A STORY COLUMN IS NOT ENOUGH ============
	#
	# Seasons.csv also has ID, Name and Story — so every season in the game
	# was being drawn on the base as a person standing in the yard, and
	# "The County League" was wandering about next to the Brewery. It was
	# invisible until the visitors were told not to overlap anything and
	# started reporting that there was no room for them.
	#
	# A VISITOR IS SOMEBODY WITH A FACE OR A ONE-TIME VISIT: a `Portrait`
	# column or an `Once` column. Both are things only a person has.
	var is_visitors := columns.has("story") and columns.has("name") \
		and (columns.has("portrait") or columns.has("once"))
	if not (is_buildings or is_visitors):
		return

	var short_name := path.get_file()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		if id_text == "":
			continue

		var entry := {
			"id": id_text,
			"name": _cell(row, columns, "name"),
			"requires": _cell(row, columns, "requires"),
			"x": _cell_float(row, columns, "x", 0.5),
			"y": _cell_float(row, columns, "y", 0.5),
			"where": "%s row %d" % [short_name, i + 1],
		}

		if is_buildings:
			entry["description"] = _cell(row, columns, "description")
			entry["art"] = _cell(row, columns, "art")
			entry["action"] = _cell(row, columns, "action")
			buildings.append(entry)
		else:
			entry["portrait"] = _cell(row, columns, "portrait")
			entry["story"] = _cell(row, columns, "story")
			entry["once"] = _cell(row, columns, "once").to_lower() in ["true", "yes", "1", "on"]
			visitors.append(entry)


# =============================================================
#  QUERIES
# =============================================================

## Everything on the base right now. Locked buildings are INCLUDED — the
## screen draws them greyed out, because seeing what you have not earned is
## the point of a base screen.
func buildings_for(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in buildings:
		var copy := entry.duplicate()
		copy["unlocked"] = DialogueGrammar.test(String(entry["requires"]), state)
		out.append(copy)
	return out


## Only the visitors actually present. Unlike buildings, someone who is not
## here is not here — you do not show a greyed-out person.
func visitors_for(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out

	for entry in visitors:
		if bool(entry["once"]) and state.has_flag(TALKED_PREFIX + String(entry["id"])):
			continue
		if not DialogueGrammar.test(String(entry["requires"]), state):
			continue
		out.append(entry.duplicate())
	return out


## Remember that a one-time visitor has been spoken to.
static func mark_talked(visitor_id: String, state: GameState) -> void:
	if state != null:
		state.set_flag(TALKED_PREFIX + visitor_id, true)


# =============================================================
#  VALIDATION
# =============================================================

func _validate() -> void:
	var seen: Dictionary = {}
	for entry in buildings + visitors:
		var key := CardDatabase._normalise(String(entry["id"]))
		if seen.has(key):
			problems.append("%s: ID '%s' is already used by %s"
				% [entry["where"], entry["id"], seen[key]])
		else:
			seen[key] = entry["where"]

		if String(entry["name"]).strip_edges() == "":
			problems.append("%s: '%s' has no Name, so nothing would be readable"
				% [entry["where"], entry["id"]])

		for complaint in DialogueGrammar.complaints(String(entry["requires"]), false):
			problems.append("%s: Requires %s" % [entry["where"], complaint])

		var x := float(entry["x"])
		var y := float(entry["y"])
		if x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
			problems.append("%s: X and Y are fractions of the screen between 0 and 1 — '%s' has %s, %s and would sit off-screen"
				% [entry["where"], entry["id"], x, y])

	for entry in buildings:
		var action := String(entry["action"])
		if action.strip_edges() == "":
			continue
		var colon := action.find(":")
		if colon <= 0:
			problems.append("%s: Action '%s' — expected something like 'story:name' or 'goto:builder'"
				% [entry["where"], action])


## Every dialogue Scene named by a visitor or a building, for the report.
func story_targets() -> Array[String]:
	var out: Array[String] = []
	for entry in visitors:
		var scene := String(entry["story"]).strip_edges()
		if scene != "" and not out.has(scene):
			out.append(scene)
	for entry in buildings:
		var action := String(entry["action"]).strip_edges()
		if action.to_lower().begins_with("story:"):
			var scene2 := action.substr(6).strip_edges()
			if scene2 != "" and not out.has(scene2):
				out.append(scene2)
	return out


func all_conditions() -> Array[String]:
	var out: Array[String] = []
	for entry in buildings + visitors:
		var condition := String(entry["requires"])
		if condition.strip_edges() != "":
			out.append(condition)
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


func _cell_float(row: PackedStringArray, columns: Dictionary, key: String,
		fallback: float) -> float:
	var raw := _cell(row, columns, key)
	return float(raw) if raw.is_valid_float() else fallback
