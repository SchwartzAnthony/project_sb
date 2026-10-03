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
#              duel_lost, brew_drunk, match_ended, match_started,
#              save_made, shot_taken, stamina_spent, player_turned,
#              player_recruited
#              and from the ability engine (rounds Z / AA): token_made,
#              swan_made, counter_placed, ore_gained, ore_spent,
#              emblem_basic, card_played
#    When      optional filter. Blank means "every time".
#    Amount    how much to add. Blank means 1. May also be a {fact}, so
#              `{stamina}` adds however much stamina that shot actually cost.
#    Group     which panel of the post-match screen it appears in — "Goals",
#              "Duels", "Keeper", anything you like. Blank = "Match".
#    Label     what the post-match screen calls it. Blank = the counter name
#              tidied up.
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
#    shot_taken                    class, tier, card, brew, star, power
#    save_made                     class (the KEEPER's side), power, stamina
#    stamina_spent                 class, stamina
#    player_turned                 card, class, set, tier   (round X: the
#                                  last of three beers - transform_book.gd)
#    player_recruited              card, tier               (round X: a
#                                  recruit: action - recruit_book.gd)
#    token_made                    class, tier, card (the card REPLACED),
#                                  kind (rose / swan), by
#    swan_made                     class, tier, card, element
#    counter_placed                kind (burn / song / power / victory),
#                                  class, tier, card (who placed it), on,
#                                  on_class
#    ore_gained / ore_spent        class, tier, card, amount
#    emblem_basic                  emblem (the Star's name), effect, class,
#                                  tier, card - an Emblem's Basic side went off
#    card_played                   class, tier, card, first (yes the first
#                                  time that card plays this match)
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

		# Amount is normally a plain number. It may instead be a {fact}, which
		# is how "add however much stamina that save cost" is written without
		# a line of code.
		var amount_text := _cell(row, columns, "amount")
		var amount := 1
		var amount_fact := ""
		if amount_text != "":
			if amount_text.begins_with("{") and amount_text.ends_with("}"):
				amount_fact = amount_text.substr(1, amount_text.length() - 2).strip_edges()
			elif amount_text.is_valid_int():
				amount = int(amount_text)
			else:
				problems.append("%s: Amount '%s' is not a whole number, and not a {fact} either"
					% [where, amount_text])

		rules.append({
			"counter": counter,
			"event": CardDatabase._normalise(event),
			"when": _cell(row, columns, "when"),
			"amount": amount,
			"amount_fact": amount_fact,
			"group": _cell(row, columns, "group"),
			"label": _cell(row, columns, "label"),
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

		var amount := int(rule["amount"])
		var fact_name := String(rule["amount_fact"])
		if fact_name != "":
			var raw := String(facts.get(fact_name, "")).strip_edges()
			if not raw.is_valid_float():
				continue     # no such fact on this event — skip, do not add 0
			amount = int(round(float(raw)))
		if amount == 0:
			continue
		state.add_count(counter, amount)


# =============================================================
#  LOOKING A COUNTER BACK UP
#
#  The post-match screen has a concrete counter — `goals_by_tier_IV` — and
#  wants to know which panel it belongs in and what to call it. That means
#  matching it back against the PATTERN it came from, braces and all.
# =============================================================

## The Stats.csv row that could have produced this counter, or {} if none.
func row_for(counter_name: String) -> Dictionary:
	for rule in rules:
		if matches_pattern(counter_name, String(rule["counter"])):
			return rule
	return {}


## Which panel of the post-match screen a counter belongs in.
func group_for(counter_name: String) -> String:
	var rule := row_for(counter_name)
	if rule.is_empty():
		return ""
	return String(rule["group"]).strip_edges()


## Does a concrete counter name match a pattern that may contain {facts}?
## `goals_with_brew_fire` matches `goals_with_brew_{brew}`.
##
## The pattern is split on the braces BEFORE anything is normalised — squash
## it first and the braces vanish, fusing the token into the literal text
## either side of it and matching nothing ever again.
static func matches_pattern(counter_name: String, pattern: String) -> bool:
	var name_key := CardDatabase._normalise(counter_name)

	var literals: Array[String] = []
	var rest := pattern
	while true:
		var open_at := rest.find("{")
		if open_at < 0:
			literals.append(rest)
			break
		var close_at := rest.find("}", open_at)
		if close_at < 0:
			literals.append(rest)
			break
		literals.append(rest.substr(0, open_at))
		rest = rest.substr(close_at + 1)

	if literals.size() == 1:
		return name_key == CardDatabase._normalise(literals[0])

	var at := 0
	for i in literals.size():
		var piece := CardDatabase._normalise(literals[i])
		if piece == "":
			continue
		if i == 0:
			if not name_key.begins_with(piece):
				return false
			at = piece.length()
			continue
		var found := name_key.find(piece, at)
		if found < 0:
			return false
		at = found + piece.length()

	# A pattern ending in a token needs something to have filled it.
	if pattern.ends_with("}"):
		return name_key.length() > at
	return true


## Every Group named in Stats.csv, in the order the file lists them.
func group_names() -> Array[String]:
	var out: Array[String] = []
	for rule in rules:
		var group := String(rule["group"]).strip_edges()
		if group != "" and not out.has(group):
			out.append(group)
	return out


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
