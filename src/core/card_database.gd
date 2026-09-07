class_name CardDatabase
extends RefCounted

# =============================================================
#  CARD DATABASE — the CSVs ARE the game data
#
#  Everything is read straight out of res://data/*.csv when the match
#  starts. There is no import step and no .tres files to keep in sync.
#  Drop a CSV in, press play, it is in the game.
#
#  HOW FILES ARE RECOGNISED
#  File NAMES do not matter. Each CSV is classified by its header row:
#
#    contains "Unit Type"  + "Base Power Left"  -> unit cards
#    contains "Max Stamina"                     -> goalies
#    contains "Ability ID"                      -> abilities
#    contains "Key" + "Value"                   -> tuning
#
#  COLUMN ORDER DOES NOT MATTER EITHER. Columns are matched by header
#  name (case, spaces and underscores are ignored), so you can reorder
#  them, add your own, or leave optional ones out entirely. Unknown
#  columns are ignored rather than breaking the import.
#
#  ADDING A NEW CLASS / RACE — no code, no editor script:
#    1. Export a CSV with the same headers into res://data/
#    2. Put the artwork PNGs in res://assets/players/
#    3. Optionally add a row to Goalies.csv for its keeper
#    4. Optionally add res://src/formations/<class>_formation.tscn;
#       without one, a formation is generated from the pitch.
# =============================================================

const DATA_DIR := "res://data/"
const PLAYER_ART_DIRS: Array[String] = ["res://assets/players/", "res://assets/"]
const GOALIE_ART_DIRS: Array[String] = ["res://assets/goalies/", "res://assets/players/", "res://assets/"]
const FORMATION_DIR := "res://src/formations/"

static var _instance: CardDatabase

var players: Array[PlayerData] = []
var goalie_data: Array[GoalieData] = []
var abilities: Dictionary = {}      # ability_id (lower) -> AbilityData
var tuning: Dictionary = {}         # key (lower) -> String
var problems: Array[String] = []    # everything that looked wrong, for one tidy report


# =============================================================
#  SINGLETON  (a static var, so there is no autoload to register)
# =============================================================

static func get_db() -> CardDatabase:
	if _instance == null:
		_instance = CardDatabase.new()
		_instance.load_all()
	return _instance


## Re-read every CSV from disk. Handy while tuning.
static func reload() -> void:
	_instance = null
	get_db()


# =============================================================
#  LOADING
# =============================================================

func load_all() -> void:
	players.clear()
	goalie_data.clear()
	abilities.clear()
	tuning.clear()
	problems.clear()

	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		problems.append("Could not open %s" % DATA_DIR)
		_report()
		return

	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if not file_name.to_lower().ends_with(".csv"):
			continue
		_load_csv(DATA_DIR + file_name)

	_report()


func _load_csv(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		problems.append("Could not read %s" % path)
		return
	var rows := parse_csv(file.get_as_text())
	file.close()

	if rows.size() < 2:
		return

	# Map normalised header name -> column index.
	var columns: Dictionary = {}
	var header: PackedStringArray = rows[0]
	for i in header.size():
		var key := _normalise(header[i])
		if key != "":
			columns[key] = i

	var short_name := path.get_file()

	if columns.has("unittype") and columns.has("basepowerleft"):
		_read_units(rows, columns, short_name)
	elif columns.has("maxstamina"):
		_read_goalies(rows, columns, short_name)
	elif columns.has("abilityid"):
		_read_abilities(rows, columns, short_name)
	elif columns.has("key") and columns.has("value"):
		_read_tuning(rows, columns)
	# Anything else is simply not ours — silently skipped.


# --- Units ---------------------------------------------------

func _read_units(rows: Array, columns: Dictionary, source: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var name_text := _cell(row, columns, "name")
		if name_text == "":
			continue

		var card := PlayerData.new()
		card.unit_type = _cell(row, columns, "unittype")
		card.player_name = name_text
		card.attack_text = _cell(row, columns, "attack")
		card.defend_text = _cell(row, columns, "defend")
		card.element = _cell(row, columns, "element")
		card.base_power_left = _cell_int(row, columns, "basepowerleft")
		card.base_power_right = _cell_int(row, columns, "basepowerright")
		card.tier = _cell(row, columns, "tier")
		card.stufe = _cell(row, columns, "stufe")
		card.tool = _cell(row, columns, "tool")
		card.card_number = _cell_int(row, columns, "cardnumber")
		card.card_date = _cell_int(row, columns, "carddate")
		card.card_set = _cell(row, columns, "setname")
		card.created_by = _cell(row, columns, "createdby")

		var type_text := _cell(row, columns, "playertype")
		card.player_type = type_text if type_text != "" else "Normal"

		# Optional ability hooks — blank means "no ability", which is fine.
		card.attack_ability_id = _cell(row, columns, "attackability")
		card.defend_ability_id = _cell(row, columns, "defendability")

		var art_name := _cell(row, columns, "artwork")
		if art_name != "":
			card.artwork = _find_texture(art_name, PLAYER_ART_DIRS)
			if card.artwork == null:
				problems.append("%s: artwork '%s' not found for %s" % [source, art_name, name_text])

		if card.is_star():
			var formation_name := _cell(row, columns, "formation")
			if formation_name == "":
				formation_name = card.unit_type.to_lower().replace(" ", "_") + "_formation.tscn"
			var formation_path := FORMATION_DIR + formation_name
			if ResourceLoader.exists(formation_path):
				card.formation_scene = load(formation_path)

		if card.get_tier_index() < 0:
			problems.append("%s: '%s' has tier '%s' — expected I, II, III or IV"
				% [source, name_text, card.tier])

		players.append(card)


# --- Goalies -------------------------------------------------

func _read_goalies(rows: Array, columns: Dictionary, source: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var name_text := _cell(row, columns, "name")
		if name_text == "":
			continue

		var keeper := GoalieData.new()
		keeper.team = _cell(row, columns, "team")
		keeper.goalie_name = name_text
		keeper.max_stamina = _cell_int(row, columns, "maxstamina")
		# "Passive / Ability" normalises to "passiveability".
		keeper.ability_text = _first_cell(row, columns, ["passiveability", "abilitytext", "ability"])
		keeper.ability_id = _cell(row, columns, "abilityid")

		if keeper.max_stamina <= 0:
			problems.append("%s: goalie '%s' has Max Stamina %d — using 25"
				% [source, name_text, keeper.max_stamina])
			keeper.max_stamina = 25

		var art_name := _cell(row, columns, "artwork")
		if art_name != "":
			keeper.artwork = _find_texture(art_name, GOALIE_ART_DIRS)

		goalie_data.append(keeper)


# --- Abilities -----------------------------------------------

func _read_abilities(rows: Array, columns: Dictionary, source: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "abilityid")
		if id_text == "":
			continue

		var ability := AbilityData.new()
		ability.id = id_text
		ability.display_name = _cell(row, columns, "name")
		ability.trigger = _normalise(_cell(row, columns, "trigger"))
		ability.target = _cell(row, columns, "target").strip_edges().to_lower()
		ability.effect = _normalise(_cell(row, columns, "effect"))
		ability.value = _cell_int(row, columns, "value")
		ability.scope = _normalise(_cell(row, columns, "scope"))
		ability.notes = _cell(row, columns, "notes")

		var complaint := ability.validate()
		if complaint != "":
			problems.append("%s: ability '%s' — %s" % [source, id_text, complaint])
			continue

		abilities[id_text.to_lower()] = ability


# --- Tuning --------------------------------------------------

func _read_tuning(rows: Array, columns: Dictionary) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var key := _normalise(_cell(row, columns, "key"))
		if key == "":
			continue
		tuning[key] = _cell(row, columns, "value")


# =============================================================
#  QUERIES
# =============================================================

func get_ability(id_text: String) -> AbilityData:
	if id_text.strip_edges() == "":
		return null
	return abilities.get(id_text.strip_edges().to_lower())


func roster_for_class(unit_type: String) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var wanted := unit_type.strip_edges().to_lower()
	for card in players:
		if card.is_star():
			continue
		if card.unit_type.strip_edges().to_lower() == wanted:
			out.append(card)
	return out


func stars_for_class(unit_type: String) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var wanted := unit_type.strip_edges().to_lower()
	for card in players:
		if card.is_star() and card.unit_type.strip_edges().to_lower() == wanted:
			out.append(card)
	return out


## class name -> Array[PlayerData] of that class's Star Players.
func stars_by_class() -> Dictionary:
	var grouped: Dictionary = {}
	for card in players:
		if not card.is_star():
			continue
		var key := card.unit_type.strip_edges()
		if key == "":
			continue
		if not grouped.has(key):
			grouped[key] = [] as Array[PlayerData]
		(grouped[key] as Array[PlayerData]).append(card)
	return grouped


func goalie_for_team(team: String) -> GoalieData:
	var wanted := team.strip_edges().to_lower()
	for keeper in goalie_data:
		if keeper.team.strip_edges().to_lower() == wanted:
			return keeper
	return null


# --- Tuning accessors ----------------------------------------
# Every one falls back to the value passed in, so a missing or misspelled
# row in Tuning.csv degrades to the built-in default instead of crashing.

func tune_float(key: String, fallback: float) -> float:
	var raw := String(tuning.get(_normalise(key), ""))
	return float(raw) if raw.is_valid_float() else fallback


func tune_int(key: String, fallback: int) -> int:
	var raw := String(tuning.get(_normalise(key), ""))
	return int(raw) if raw.is_valid_int() else fallback


func tune_bool(key: String, fallback: bool) -> bool:
	var raw := String(tuning.get(_normalise(key), "")).strip_edges().to_lower()
	if raw in ["true", "yes", "1", "on"]:
		return true
	if raw in ["false", "no", "0", "off"]:
		return false
	return fallback


# =============================================================
#  HELPERS
# =============================================================

## "Base Power Left" / "base_power_left" / "BASEPOWERLEFT" all match.
static func _normalise(text: String) -> String:
	var out := ""
	for c in text.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()


func _first_cell(row: PackedStringArray, columns: Dictionary, keys: Array) -> String:
	for key in keys:
		var value := _cell(row, columns, String(key))
		if value != "":
			return value
	return ""


func _cell_int(row: PackedStringArray, columns: Dictionary, key: String) -> int:
	var raw := _cell(row, columns, key)
	return int(raw) if raw.is_valid_int() else 0


func _find_texture(file_name: String, dirs: Array[String]) -> Texture2D:
	for folder in dirs:
		var path: String = folder + file_name
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


func _report() -> void:
	print("[CardDB] %d cards, %d goalies, %d abilities, %d tuning values."
		% [players.size(), goalie_data.size(), abilities.size(), tuning.size()])
	if problems.is_empty():
		return
	print("[CardDB] %d thing(s) need attention in your CSVs:" % problems.size())
	for line in problems:
		print("         - ", line)


# =============================================================
#  CSV PARSER
#  Handles quoted fields and doubled quotes, which matters because your
#  ability text contains commas.
# =============================================================

static func parse_csv(content: String) -> Array:
	var rows: Array = []
	var current_row := PackedStringArray()
	var field := ""
	var in_quotes := false
	var i := 0

	while i < content.length():
		var c := content[i]
		if in_quotes:
			if c == '"':
				if i + 1 < content.length() and content[i + 1] == '"':
					field += '"'
					i += 1
				else:
					in_quotes = false
			else:
				field += c
		else:
			if c == '"':
				in_quotes = true
			elif c == ",":
				current_row.append(field)
				field = ""
			elif c == "\r":
				pass
			elif c == "\n":
				current_row.append(field)
				field = ""
				rows.append(current_row)
				current_row = PackedStringArray()
			else:
				field += c
		i += 1

	if not field.is_empty() or not current_row.is_empty():
		current_row.append(field)
		rows.append(current_row)

	return rows
