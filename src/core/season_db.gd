class_name SeasonDB
extends RefCounted

# =============================================================
#  SEASON.CSV — the fixture list, and the end of the game
#
#  Before this file the game had no shape: you could play matches forever
#  and nothing ever finished. A season is ten fixtures and then a final.
#  It is one spreadsheet. Add a row, you have an eleventh fixture; delete
#  rows, you have a shorter season.
#
#  THE COLUMNS
#    ID           a short name for the fixture, unique. Also how the result
#                 is remembered, so do not rename one after shipping a save.
#    Match        the fixture number: 1, 2, 3... They are played in this
#                 order regardless of what order the rows sit in.
#    Opponent     who you are playing. Shown on the season screen.
#    Team         a row of Teams.csv — the exact side you face, with the
#                 exact cards it fields. BLANK = fall back to Class.
#    Class        which class the opposition fields — "Lorelei",
#                 "Lorelei". Ignored when Team names a team. BLANK and no
#                 Team = pick one at random, which is what the game did
#                 before either file existed.
#    Difficulty   a flat power bonus to every enemy card, for this fixture
#                 only. 0 = a fair fight. Keep it in the 0-3 range: cards are
#                 0-5 power, so 4 would be close to unbeatable.
#    Final        true on the LAST fixture. Winning it makes you champions.
#    Requires     an optional condition, same language as everywhere else.
#                 A fixture whose condition fails is skipped.
#    On Win       things that happen when you win it — unlock:Cup Room,
#                 count:coins+50, announce:Well played. Same words as
#                 Progression.csv's Do column.
#    On Loss      the same, for a defeat. A draw gets neither.
#    Description  one line, shown on the season screen.
#    Notes        yours.
#
#  A WORKED ROW
#      ID          md07
#      Match       7
#      Opponent    Cinderworks Reserves
#      Class       Lorelei
#      Difficulty  2
#      On Win      unlock:Away Kit
#
#  WHAT IT REMEMBERS  (all ordinary counters, so any CSV can test them)
#    season_match            the fixture number you play next
#    season_wins / _draws / _losses
#    season_points           3 for a win, 1 for a draw
#    season_goals_for / season_goals_against
#    season_number           1 for your first season, 2 after a reset...
#    flag season_over        the final has been played
#    flag season_champion    ...and you won it
# =============================================================

const DATA_DIR := "res://data/"

const MATCH := "season_match"
const WINS := "season_wins"
const DRAWS := "season_draws"
const LOSSES := "season_losses"
const POINTS := "season_points"
const GOALS_FOR := "season_goals_for"
const GOALS_AGAINST := "season_goals_against"
const NUMBER := "season_number"

const OVER_FLAG := "season_over"
const CHAMPION_FLAG := "season_champion"

## A fixture's result is stored as text: "3-1" and so on.
const RESULT_PREFIX := "season_result_"

## Every counter this file writes. The startup report reads this so that
## `count:season_wins>=3` in one of your CSVs is not reported as a typo.
const COUNTERS: Array[String] = [MATCH, WINS, DRAWS, LOSSES, POINTS,
	GOALS_FOR, GOALS_AGAINST, NUMBER]

static var _instance: SeasonDB

var fixtures: Array[Dictionary] = []
var problems: Array[String] = []


static func get_db() -> SeasonDB:
	if _instance == null:
		_instance = SeasonDB.new()
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
	fixtures.clear()
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

	_sort_by_number()
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

	# A season file is any CSV with a Match number and an Opponent. No other
	# file in the project has both, so the fixture list can be called
	# anything you like.
	if not (columns.has("match") and columns.has("opponent")):
		return

	var short_name := path.get_file()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		var opponent := _cell(row, columns, "opponent")
		if id_text == "" and opponent == "":
			continue

		var where := "%s row %d" % [short_name, i + 1]
		if id_text == "":
			problems.append("%s: every fixture needs an ID" % where)
			continue

		fixtures.append({
			"id": id_text,
			# WHICH COMPETITION THIS FIXTURE BELONGS TO. Blank means "the
			# first one", so a fixture list written before Seasons.csv
			# existed still works exactly as it did. See season_book.gd.
			"season": _cell(row, columns, "season"),
			"number": _cell_int(row, columns, "match", 0),
			"opponent": opponent,
			"team": _cell(row, columns, "team"),
			"class": _cell(row, columns, "class"),
			"difficulty": _cell_int(row, columns, "difficulty", 0),
			"final": _cell(row, columns, "final").to_lower() in ["true", "yes", "1", "on"],
			"requires": _cell(row, columns, "requires"),
			"on_win": _cell(row, columns, "onwin"),
			"on_loss": _cell(row, columns, "onloss"),
			# A DIALOGUE BEFORE THIS FIXTURE. A Dialogue.csv scene name, or
			# blank for none — see season_screen.gd, which plays it on the
			# way to the team sheet.
			"story": _cell(row, columns, "story"),
			"description": _cell(row, columns, "description"),
			"where": where,
		})


func _sort_by_number() -> void:
	# An explicit insertion sort rather than sort_custom: it runs once at
	# load, it is easy to read, and it keeps two rows with the same number in
	# the order the file had them.
	var sorted: Array[Dictionary] = []
	for entry in fixtures:
		var at := sorted.size()
		for i in sorted.size():
			if int(sorted[i]["number"]) > int(entry["number"]):
				at = i
				break
		sorted.insert(at, entry)
	fixtures = sorted
	_keep_only_the_chosen_season()


# =============================================================
#  WHERE THE SEASON IS
# =============================================================

## The fixture number to play next. Counters start at 0, seasons at 1.
static func current_number(state: GameState) -> int:
	if state == null:
		return 1
	return maxi(1, state.count(MATCH))


## The fixture to play next, or {} when the season is finished.
func current(state: GameState) -> Dictionary:
	var wanted := current_number(state)
	for entry in fixtures:
		if int(entry["number"]) == wanted and DialogueGrammar.test(String(entry["requires"]), state):
			return entry
	return {}


## The fixture most recently played — what "play it again" reruns.
func previous(state: GameState) -> Dictionary:
	var wanted := current_number(state) - 1
	if SeasonDB.is_over(state):
		wanted = last_number()
	for entry in fixtures:
		if int(entry["number"]) == wanted:
			return entry
	return {}


func last_number() -> int:
	var highest := 0
	for entry in fixtures:
		highest = maxi(highest, int(entry["number"]))
	return highest


static func is_over(state: GameState) -> bool:
	return state != null and state.has_flag(OVER_FLAG)


## ============ ONE COMPETITION AT A TIME ============
##
## Season.csv can hold the fixtures of every competition you ever write. The
## Season column says which is which, and only the chosen one is loaded — so
## everything downstream (the table, "next up", the final) sees one season
## and needed no changes at all.
##
## A fixture with a blank Season column belongs to whichever competition is
## first in Seasons.csv, which is why an older fixture list still works.
func _keep_only_the_chosen_season() -> void:
	var chosen := SeasonBook.chosen_id()
	if chosen == "":
		return

	var first := SeasonBook.first_id()
	var kept: Array[Dictionary] = []
	for entry in fixtures:
		var belongs := String(entry.get("season", "")).strip_edges()
		if belongs == "":
			belongs = first
		if CardDatabase._normalise(belongs) == CardDatabase._normalise(chosen):
			kept.append(entry)

	if kept.is_empty():
		problems.append("Season: no fixture in Season.csv has Season = '%s'. Showing every fixture instead."
			% chosen)
		return
	fixtures = kept


## How many fixtures have actually been played.
static func played(state: GameState) -> int:
	if state == null:
		return 0
	return state.count(WINS) + state.count(DRAWS) + state.count(LOSSES)


## The stored result of one fixture, "3-1", or "" if it has not been played.
static func result_for(fixture_id: String, state: GameState) -> String:
	if state == null:
		return ""
	return state.text(RESULT_PREFIX + fixture_id)


## The line at the top of the season screen once it is all over.
static func verdict(state: GameState) -> String:
	if state == null or not is_over(state):
		return ""
	if state.has_flag(CHAMPION_FLAG):
		return "CHAMPIONS"
	return "RUNNERS-UP"


# =============================================================
#  RECORDING A RESULT
#
#  Called once, at the final whistle. Everything it changes is an ordinary
#  counter or flag, so your other CSVs can test all of it.
# =============================================================

## Returns what happened, for the season screen to show, plus any actions
## from the On Win / On Loss columns that need the scene tree.
func record(scored: int, conceded: int, state: GameState) -> Dictionary:
	var summary := {
		"fixture": {},
		"outcome": "draw",
		"scored": scored,
		"conceded": conceded,
		"was_final": false,
		"season_over": false,
		"champion": false,
		"actions": [] as Array[Dictionary],
	}
	if state == null:
		return summary

	var fixture := current(state)
	if fixture.is_empty():
		# No fixture left — a friendly. Nothing is recorded.
		return summary

	var outcome := "draw"
	if scored > conceded:
		outcome = "win"
	elif scored < conceded:
		outcome = "loss"

	summary["fixture"] = fixture
	summary["outcome"] = outcome

	match outcome:
		"win":
			state.add_count(WINS, 1)
			state.add_count(POINTS, 3)
		"draw":
			state.add_count(DRAWS, 1)
			state.add_count(POINTS, 1)
		_:
			state.add_count(LOSSES, 1)

	state.add_count(GOALS_FOR, scored)
	state.add_count(GOALS_AGAINST, conceded)
	state.set_text(RESULT_PREFIX + String(fixture["id"]), "%d-%d" % [scored, conceded])

	if state.count(NUMBER) < 1:
		state.set_count(NUMBER, 1)

	# The rewards. Same grammar as everywhere else, so a fixture can unlock a
	# building, set a flag or play a line just like a Progression row can.
	var reward := String(fixture["on_win"]) if outcome == "win" else String(fixture["on_loss"])
	var deferred: Array[Dictionary] = Progression.run_actions(reward, state)
	summary["actions"] = deferred

	var was_final := bool(fixture["final"]) or int(fixture["number"]) >= last_number()
	summary["was_final"] = was_final

	if was_final:
		state.set_flag(OVER_FLAG, true)
		summary["season_over"] = true
		if outcome == "win":
			state.set_flag(CHAMPION_FLAG, true)
			summary["champion"] = true
	else:
		state.set_count(MATCH, int(fixture["number"]) + 1)

	print("[season] %s %d-%d %s — played %d, %d point(s)." % [
		fixture["opponent"], scored, conceded, outcome.to_upper(),
		played(state), state.count(POINTS)])

	return summary


## Wipe the record and go round again, keeping everything you unlocked.
## The season number goes up so content can say "in your second season".
static func new_season(state: GameState) -> void:
	if state == null:
		return
	var next := maxi(1, state.count(NUMBER)) + 1

	state.set_count(MATCH, 1)
	state.set_count(WINS, 0)
	state.set_count(DRAWS, 0)
	state.set_count(LOSSES, 0)
	state.set_count(POINTS, 0)
	state.set_count(GOALS_FOR, 0)
	state.set_count(GOALS_AGAINST, 0)
	state.set_count(NUMBER, next)
	state.set_flag(OVER_FLAG, false)
	state.set_flag(CHAMPION_FLAG, false)

	var doomed: Array[String] = []
	for key in state.texts.keys():
		if String(key).begins_with(CardDatabase._normalise(RESULT_PREFIX)):
			doomed.append(String(key))
	for key in doomed:
		state.texts.erase(key)

	print("[season] Season %d begins. %d result(s) cleared." % [next, doomed.size()])


# =============================================================
#  VALIDATION
# =============================================================

func _validate() -> void:
	var cards := CardDatabase.get_db()
	var seen_ids: Dictionary = {}
	var seen_numbers: Dictionary = {}
	var finals := 0

	for entry in fixtures:
		var where := String(entry["where"])
		var key := CardDatabase._normalise(String(entry["id"]))

		if seen_ids.has(key):
			problems.append("%s: fixture ID '%s' is already used by %s — results would be shared between them"
				% [where, entry["id"], seen_ids[key]])
		else:
			seen_ids[key] = where

		var number := int(entry["number"])
		if number < 1:
			problems.append("%s: fixture '%s' has no Match number, so it can never be played"
				% [where, entry["id"]])
		elif seen_numbers.has(number):
			problems.append("%s: Match %d is also %s — one of them will never be played"
				% [where, number, seen_numbers[number]])
		else:
			seen_numbers[number] = where

		if String(entry["opponent"]).strip_edges() == "":
			problems.append("%s: fixture '%s' has no Opponent" % [where, entry["id"]])

		if bool(entry["final"]):
			finals += 1

		var difficulty := int(entry["difficulty"])
		if difficulty > 3:
			problems.append("%s: Difficulty %d is very high — cards are 0-5 power, so the opposition would be close to unbeatable"
				% [where, difficulty])

		# A class nobody plays is almost always a spelling mistake, and it
		# would silently fall back to a random opponent.
		var wanted := String(entry["class"]).strip_edges()
		if wanted != "":
			var known := false
			for card in cards.players:
				if CardDatabase._normalise(card.unit_type) == CardDatabase._normalise(wanted):
					known = true
					break
			if not known:
				problems.append("%s: '%s' is not a class any card belongs to — the opposition would be picked at random instead"
					% [where, wanted])

		for complaint in DialogueGrammar.complaints(String(entry["requires"]), false):
			problems.append("%s: Requires %s" % [where, complaint])
		for column in ["on_win", "on_loss"]:
			for piece in String(entry[column]).split(";"):
				var term := String(piece).strip_edges()
				if term == "":
					continue
				var colon := term.find(":")
				if colon <= 0:
					problems.append("%s: %s term '%s' — expected something like 'unlock:Cup Room'"
						% [where, column.capitalize(), term])
					continue
				if Progression.DEFERRED.has(term.substr(0, colon).strip_edges().to_lower()):
					continue
				for complaint2 in DialogueGrammar.complaints(term, true):
					problems.append("%s: %s %s" % [where, column.capitalize(), complaint2])

	if fixtures.is_empty():
		return

	# Without a final the season never ends, which is the whole thing this
	# file exists to fix — so it is worth saying out loud.
	if finals == 0:
		problems.append("Season: no fixture has Final set to true. The last one (Match %d) will be treated as the final."
			% last_number())
	elif finals > 1:
		problems.append("Season: %d fixtures are marked Final. The season ends at the first one reached."
			% finals)

	# A gap in the numbering strands everything after it.
	for wanted_number in range(1, last_number() + 1):
		if not seen_numbers.has(wanted_number):
			problems.append("Season: there is no Match %d, so the season would stop there. Renumber the fixtures 1 to %d."
				% [wanted_number, last_number()])
			break


func all_conditions() -> Array[String]:
	var out: Array[String] = []
	for entry in fixtures:
		var condition := String(entry["requires"])
		if condition.strip_edges() != "":
			out.append(condition)
	return out


func all_effects() -> Array[String]:
	var out: Array[String] = []
	for entry in fixtures:
		for column in ["on_win", "on_loss"]:
			var effect := String(entry[column])
			if effect.strip_edges() != "":
				out.append(effect)
	return out


func story_targets() -> Array[String]:
	var out: Array[String] = []
	for entry in fixtures:
		for column in ["on_win", "on_loss"]:
			for piece in String(entry[column]).split(";"):
				var term := String(piece).strip_edges()
				if term.to_lower().begins_with("story:"):
					var scene := term.substr(6).strip_edges()
					if scene != "" and not out.has(scene):
						out.append(scene)
	return out


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
