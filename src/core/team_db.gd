class_name TeamDB
extends RefCounted

# =============================================================
#  TEAMS.CSV — who you play against
#
#  Until now the opposition was "some cards of a class, picked at random",
#  and the only handle you had on it was Season.csv's Class column. You
#  could not say "this fixture fields a weak Lorelei side" or "this one is
#  the toughest team in the league".
#
#  A team is one row. It names the cards it fields, and the game works out
#  its own power level from them — so you cannot write a team that says it
#  is weak and then field five Tier IV Stars.
#
#  THE COLUMNS
#    ID          short and unique. Season.csv's Team column names this.
#    Name        what the player sees.
#    Class       the class its cards come from. Blank = any.
#    Cards       the card names it fields, separated by | (a pipe).
#                BLANK = "any cards of that class", which is exactly what
#                the game did before this file existed.
#    Power       how strong you INTEND it to be, 1 to 10. Used for matching
#                a team to the player. Leave it blank and it is worked out
#                from the cards.
#    Requires    optional. A team whose condition fails is never picked.
#    Keeper      a row of Goalies.csv. Blank = the class default.
#    Description one line.
#    Notes       yours.
#
#  A WORKED ROW
#      ID      reedbank
#      Name    Reedbank Wanderers
#      Class   Lorelei
#      Cards   Silver-Rhine Lorelei|Rose Water Lorelei|Lorelei of the Deep River
#      Power   2
#
#  ------------------------------------------------------------
#  MATCHING A TEAM TO THE PLAYER
#
#  `for_power()` finds the team closest to a power you ask for, which is how
#  a quick match stays a fair fight as your own squad improves. Season.csv
#  can still name an exact team, and that always wins over matching.
#  ------------------------------------------------------------
#
#  POWER IS MEASURED, NOT CLAIMED. `measured_power()` reads the actual cards
#  and reports the average, so the startup report can tell you when a team
#  marked Power 2 is really a 4.
# =============================================================

const DATA_DIR := "res://data/"
const SEPARATORS: Array[String] = ["|", ";"]

static var _instance: TeamDB

var teams: Array[Dictionary] = []
var problems: Array[String] = []


static func get_db() -> TeamDB:
	if _instance == null:
		_instance = TeamDB.new()
		_instance.load_all()
	return _instance


static func reload() -> void:
	_instance = null
	get_db()


# =============================================================
#  LOADING
# =============================================================

func load_all() -> void:
	teams.clear()
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

	# A teams file is any CSV with both a Cards and a Power column. Nothing
	# else in the project has both, so yours can be called anything.
	if not (columns.has("cards") and columns.has("power")):
		return

	var short_name := path.get_file()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		var name_text := _cell(row, columns, "name")
		if id_text == "" and name_text == "":
			continue

		var where := "%s row %d" % [short_name, i + 1]
		if id_text == "":
			problems.append("%s: every team needs an ID" % where)
			continue

		var power_text := _cell(row, columns, "power")
		teams.append({
			"id": id_text,
			"name": name_text if name_text != "" else id_text,
			"class": _cell(row, columns, "class"),
			"cards": _split(_cell(row, columns, "cards")),
			"power": int(power_text) if power_text.is_valid_int() else -1,
			"requires": _cell(row, columns, "requires"),
			"keeper": _cell(row, columns, "keeper"),
			"description": _cell(row, columns, "description"),
			"where": where,
		})


static func _split(text: String) -> Array[String]:
	var joined := text
	for separator in SEPARATORS:
		joined = joined.replace(separator, "|")
	var out: Array[String] = []
	for piece in joined.split("|"):
		var name_text := String(piece).strip_edges()
		if name_text != "":
			out.append(name_text)
	return out


# =============================================================
#  ASKING IT THINGS
# =============================================================

func find(team_id: String) -> Dictionary:
	var key := CardDatabase._normalise(team_id)
	for entry in teams:
		if CardDatabase._normalise(String(entry["id"])) == key:
			return entry
	return {}


## The teams you could face right now.
func available(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in teams:
		if DialogueGrammar.test(String(entry["requires"]), state):
			out.append(entry)
	return out


## The team closest to the power you ask for.
##
## THIS IS HOW A QUICK MATCH STAYS FAIR. Ask for the power of the player's
## own squad and you get an opponent of about that strength, whatever they
## have built. A tie is broken by whichever row comes first in the file, so
## the result is the same every time rather than jittering between two teams.
func for_power(wanted: int, state: GameState, avoid_class: String = "") -> Dictionary:
	var best: Dictionary = {}
	var best_gap := 999

	for entry in available(state):
		if avoid_class != "" and String(entry["class"]) != "" \
				and CardDatabase._normalise(String(entry["class"])) == CardDatabase._normalise(avoid_class):
			continue
		var gap := absi(rated_power(entry) - wanted)
		if gap < best_gap:
			best_gap = gap
			best = entry

	return best


## What a team is worth: the Power column if it has one, otherwise measured.
func rated_power(entry: Dictionary) -> int:
	if entry.is_empty():
		return 0
	var claimed := int(entry["power"])
	return claimed if claimed >= 0 else measured_power(entry)


## The real average attack of the cards a team fields, 0 when it names none.
##
## This is what makes the Power column trustworthy: it can be checked.
func measured_power(entry: Dictionary) -> int:
	var cards := resolve_cards(entry)
	if cards.is_empty():
		return 0
	var total := 0
	for card in cards:
		total += card.get_attack_power()
	return int(round(float(total) / float(cards.size())))


## The actual PlayerData for a team's named cards. Names that match nothing
## are skipped here and named by the startup report, so one typo costs you a
## card rather than the whole team.
func resolve_cards(entry: Dictionary) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	if entry.is_empty():
		return out

	var cards := CardDatabase.get_db()
	for wanted in (entry["cards"] as Array[String]):
		var key := CardDatabase._normalise(wanted)
		for card in cards.players:
			if CardDatabase._normalise(card.player_name) == key:
				out.append(card)
				break
	return out


# =============================================================
#  VALIDATION
# =============================================================

func _validate() -> void:
	var cards := CardDatabase.get_db()
	var seen: Dictionary = {}

	for entry in teams:
		var where := String(entry["where"])
		var key := CardDatabase._normalise(String(entry["id"]))

		if seen.has(key):
			problems.append("%s: team ID '%s' is already used by %s"
				% [where, entry["id"], seen[key]])
		else:
			seen[key] = where

		# A named card that does not exist would silently shrink the team.
		for wanted in (entry["cards"] as Array[String]):
			var found := false
			for card in cards.players:
				if CardDatabase._normalise(card.player_name) == CardDatabase._normalise(wanted):
					found = true
					break
			if not found:
				problems.append("%s: '%s' fields a card called '%s', which is not in any unit CSV — check the spelling"
					% [where, entry["name"], wanted])

		var wanted_class := String(entry["class"]).strip_edges()
		if wanted_class != "":
			var known := false
			for card in cards.players:
				if CardDatabase._normalise(card.unit_type) == CardDatabase._normalise(wanted_class):
					known = true
					break
			if not known:
				problems.append("%s: '%s' is not a class any card belongs to"
					% [where, wanted_class])

		# THE HONEST CHECK: does the Power column match the cards?
		var claimed := int(entry["power"])
		if claimed >= 0 and not (entry["cards"] as Array[String]).is_empty():
			var measured := measured_power(entry)
			if absi(claimed - measured) >= 2:
				problems.append("%s: '%s' is marked Power %d, but its cards average %d. Matching will treat it as %d — change the column or change the cards."
					% [where, entry["name"], claimed, measured, claimed])

		for complaint in DialogueGrammar.complaints(String(entry["requires"]), false):
			problems.append("%s: Requires %s" % [where, complaint])


func all_conditions() -> Array[String]:
	var out: Array[String] = []
	for entry in teams:
		var condition := String(entry["requires"])
		if condition.strip_edges() != "":
			out.append(condition)
	return out


func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()
