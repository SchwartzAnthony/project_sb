class_name StatsRules
extends RefCounted

# =============================================================
#  STATS.CSV — teaching the game what to count, without code
#
#  Requirements elsewhere are written against COUNTERS: "count:goals>=3".
#  Something has to actually put numbers into those counters, and that
#  something is this file plus res://data/Stats.csv.
#
#  The match reports plain EVENTS as they happen — a goal was scored, a duel
#  was won, a brew was drunk — each carrying a few FACTS about it. Every row
#  of Stats.csv says "when this event happens, add to this counter".
#
#  THE COLUMNS
#    Counter   the counter to add to. May contain {facts} — see below.
#    Event     which event feeds it: goal_scored, goal_conceded, duel_won,
#              duel_lost, brew_drunk, match_ended, match_started
#    When      optional filter. Blank means "every time".
#    Amount    how much to add. Blank means 1.
#    Notes     for you; ignored by the game.
#
#  {FACTS} IN A COUNTER NAME is the whole trick. Write
#
#      goals_with_brew_{brew},goal_scored,,,
#
#  and a goal by a player carrying the Fire Brew adds to
#  `goals_with_brew_fire`, while one carrying Water Brew adds to
#  `goals_with_brew_water` — one row, a counter per brew, and no code. A
#  goal by someone who drank nothing has no `brew` fact, so the row is
#  simply skipped rather than making a counter called "goals_with_brew_".
#
#  WHAT FACTS EXIST
#    goal_scored / goal_conceded   class, tier, card, brew, star
#    duel_won / duel_lost          class, tier, card, brew, star, opponent
#    brew_drunk                    class, tier, card, brew
#    match_ended                   class, result (win/loss/draw), scored,
#                                  conceded, margin
#    match_started                 class
#
#  THE `When` FILTER, semicolons between terms, all must pass:
#    result=win        the fact equals this
#    result!=draw      it does not
#    brew!=            the fact exists and is not blank
#    brew=             the fact is missing or blank
#    margin>=2         numeric comparison: >= <= > < = !=
# =============================================================

const DATA_DIR := "res://data/"
const COMPARISONS: Array[String] = [">=", "<=", "!=", ">", "<", "="]

static var _instance: StatsRules

## One entry per usable row of Stats.csv.
var rules: Array[Dictionary] = []
var problems: Array[String] = []
## Every counter name a rule can ever write, with {facts} left in. Used by the
## content report to catch a requirement that tests a counter nothing fills.
var counter_patterns: Array[String] = []


static func get_rules() -> StatsRules:
	if _instance == null:
		_instance = StatsRules.new()
		_instance.load_all()
	return _instance


static func reload() -> void:
	_instance = null
	get_rules()


# =============================================================
#  LOADING
# =============================================================

func load_all() -> void:
	rules.clear()
	problems.clear()
	counter_patterns.clear()

	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		problems.append("Could not open %s" % DATA_DIR)
		return

	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if file_name.to_lower().ends_with(".csv"):
			_load_csv(DATA_DIR + file_name)


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

	# A stats file is any CSV with both a Counter and an Event column.
	if not (columns.has("counter") and columns.has("event")):
		return

	var short_name := path.get_file()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var counter := _cell(row, columns, "counter")
		var event := _cell(row, columns, "event")
		if counter == "" and event == "":
			continue

		var where := "%s row %d" % [short_name, i + 1]
		if counter == "":
			problems.append("%s: an Event with no Counter to add to" % where)
			continue
		if event == "":
			problems.append("%s: counter '%s' has no Event to listen for" % [where, counter])
			continue

		var amount_text := _cell(row, columns, "amount")
		var amount := 1
		if amount_text != "":
			if amount_text.is_valid_int():
				amount = int(amount_text)
			else:
				problems.append("%s: Amount '%s' is not a whole number" % [where, amount_text])

		rules.append({
			"counter": counter,
			"event": CardDatabase._normalise(event),
			"when": _cell(row, columns, "when"),
			"amount": amount,
			"where": where,
		})
		if not counter_patterns.has(counter):
			counter_patterns.append(counter)


# =============================================================
#  RECORDING
# =============================================================

## Called by the match whenever something happens worth counting.
## `facts` is a plain Dictionary of String -> String or number.
func record(event: String, facts: Dictionary, state: GameState) -> void:
	if state == null:
		return
	var wanted := CardDatabase._normalise(event)

	for rule in rules:
		if String(rule["event"]) != wanted:
			continue
		if not _passes(String(rule["when"]), facts):
			continue

		var counter := _fill(String(rule["counter"]), facts)
		if counter == "":
			continue        # a {fact} was missing — this row is not for us
		state.add_count(counter, int(rule["amount"]))


## Replace {fact} with its value. Returns "" if any {fact} is missing or
## blank, which is how "only count this when the fact applies" is expressed.
static func _fill(pattern: String, facts: Dictionary) -> String:
	var out := pattern
	while true:
		var open_at := out.find("{")
		if open_at < 0:
			break
		var close_at := out.find("}", open_at)
		if close_at < 0:
			break

		var key := out.substr(open_at + 1, close_at - open_at - 1)
		var value := String(facts.get(key, "")).strip_edges()
		if value == "":
			return ""
		out = out.substr(0, open_at) + value + out.substr(close_at + 1)
	return out


static func _passes(filter: String, facts: Dictionary) -> bool:
	if filter.strip_edges() == "":
		return true

	for piece in filter.split(";"):
		var term := String(piece).strip_edges()
		if term == "":
			continue
		if not _passes_one(term, facts):
			return false
	return true


static func _passes_one(term: String, facts: Dictionary) -> bool:
	for op in COMPARISONS:
		var at := term.find(op)
		if at <= 0:
			continue

		var key := term.substr(0, at).strip_edges()
		var wanted := term.substr(at + op.length()).strip_edges()
		var have := String(facts.get(key, "")).strip_edges()

		# Blank on the right means "exists" / "does not exist".
		if wanted == "":
			if op == "!=":
				return have != ""
			if op == "=":
				return have == ""

		if have.is_valid_float() and wanted.is_valid_float():
			var a := float(have)
			var b := float(wanted)
			match op:
				">=": return a >= b
				"<=": return a <= b
				"!=": return not is_equal_approx(a, b)
				">": return a > b
				"<": return a < b
				"=": return is_equal_approx(a, b)

		match op:
			"!=": return have.to_lower() != wanted.to_lower()
			"=": return have.to_lower() == wanted.to_lower()
			_: return false

	# No operator at all — treat a bare word as "this fact exists".
	return String(facts.get(term, "")).strip_edges() != ""


func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()
