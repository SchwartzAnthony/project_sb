class_name Progression
extends RefCounted

# =============================================================
#  PROGRESSION.CSV — "when does what happen"
#
#  This is the designer's control panel. One row = one thing the game
#  should do, and when. Nothing here needs a script opened.
#
#  THE COLUMNS
#    ID        a name for this row, unique. Also how "only once" is
#              remembered, so do not rename a row after shipping a save.
#    When      the moment it is checked. See the list below.
#    Requires  the condition, in the same language as Dialogue.csv:
#              count:matches_played>=3   flag:met_lorelei   unlocked:Brewery
#              Blank means "no condition".
#    Do        what happens, semicolons between several. See below.
#    Once      true = fire once ever and never again. Blank = every time
#              the condition passes.
#    Notes     for you; ignored by the game.
#
#  WHEN — the moments a row can be checked
#    game_start      the game is launched
#    menu_opened     the main menu appears
#    match_started   a match begins
#    match_ended     the final whistle
#    base_opened     the base screen is opened
#    story_ended     a dialogue scene finishes
#
#  DO — what a row can actually do
#    Everything Dialogue.csv Effects can do:
#      flag:brave        count:coins+10       unlock:Brewery
#      set:next_class=Lorelei                 clear:next_class
#    ...plus three that need the game itself:
#      story:prologue    play that dialogue scene
#      goto:base         change screen (menu, classes, builder, match, base)
#      announce:Text     put a line on screen and in the Output panel
#
#  A WORKED ROW
#      ID        chapter2_intro
#      When      match_ended
#      Requires  count:matches_played>=3
#      Do        story:chapter2;unlock:Brewery
#      Once      true
#
#  "After the player's third match, play chapter 2 and open the Brewery."
#  No code, and the startup report will tell you if `chapter2` does not
#  exist or if `matches_played` is a counter nothing ever fills in.
# =============================================================

const DATA_DIR := "res://data/"
## Actions that cannot be done from here because they need the scene tree.
## They are handed back to the caller instead.
const DEFERRED: Array[String] = ["story", "goto", "announce"]
## Flag prefix used to remember that a once-only row has fired.
const DONE_PREFIX := "progression_done_"

static var _instance: Progression

var rules: Array[Dictionary] = []
var problems: Array[String] = []


static func get_rules() -> Progression:
	if _instance == null:
		_instance = Progression.new()
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

	# A progression file is any CSV with both a When and a Do column.
	if not (columns.has("when") and columns.has("do")):
		return

	var short_name := path.get_file()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		var when_text := _cell(row, columns, "when")
		var do_text := _cell(row, columns, "do")
		if id_text == "" and when_text == "" and do_text == "":
			continue

		var where := "%s row %d" % [short_name, i + 1]
		if id_text == "":
			problems.append("%s: every progression row needs an ID" % where)
			continue
		if do_text == "":
			problems.append("%s: '%s' has nothing in Do" % [where, id_text])
			continue

		rules.append({
			"id": id_text,
			"when": CardDatabase._normalise(when_text),
			"requires": _cell(row, columns, "requires"),
			"do": do_text,
			"once": _cell(row, columns, "once").to_lower() in ["true", "yes", "1", "on"],
			"where": where,
		})


# =============================================================
#  FIRING
# =============================================================

## Check every row listening for `trigger`. State changes are applied here
## and now; anything needing the scene tree comes back for the caller to do.
##
## Rows fire in file order, so a row that unlocks something can be followed
## by one that reacts to it having been unlocked.
func fire(trigger: String, state: GameState) -> Array[Dictionary]:
	var deferred: Array[Dictionary] = []
	if state == null:
		return deferred

	var wanted := CardDatabase._normalise(trigger)

	for rule in rules:
		if String(rule["when"]) != wanted:
			continue

		var id_text := String(rule["id"])
		if bool(rule["once"]) and state.has_flag(DONE_PREFIX + id_text):
			continue
		if not DialogueGrammar.test(String(rule["requires"]), state):
			continue

		print("[progression] '%s' fired (%s)." % [id_text, trigger])

		for action in run_actions(String(rule["do"]), state):
			action["id"] = id_text
			deferred.append(action)

		if bool(rule["once"]):
			state.set_flag(DONE_PREFIX + id_text, true)

	return deferred


## Carry out a `Do` list. State changes (flags, counters, unlocks) happen
## immediately; anything needing the scene tree comes back for the caller.
##
## Shared so that a building clicked on the base screen behaves exactly like a
## Progression row firing — same words, same meaning, one implementation.
static func run_actions(do_text: String, state: GameState) -> Array[Dictionary]:
	var deferred: Array[Dictionary] = []
	if state == null or do_text.strip_edges() == "":
		return deferred

	for piece in do_text.split(";"):
		var term := String(piece).strip_edges()
		if term == "":
			continue

		var kind := ""
		var value := ""
		var colon := term.find(":")
		if colon > 0:
			kind = term.substr(0, colon).strip_edges().to_lower()
			value = term.substr(colon + 1).strip_edges()

		if DEFERRED.has(kind):
			deferred.append({"kind": kind, "value": value, "id": ""})
		else:
			DialogueGrammar.apply(term, state)

	return deferred


# =============================================================
#  VALIDATION
# =============================================================

func _validate() -> void:
	var seen: Dictionary = {}
	for rule in rules:
		var id_text := String(rule["id"])
		var key := CardDatabase._normalise(id_text)
		if seen.has(key):
			problems.append("%s: ID '%s' is already used by %s — 'Once' would be shared between them"
				% [rule["where"], id_text, seen[key]])
		else:
			seen[key] = rule["where"]

		for complaint in DialogueGrammar.complaints(String(rule["requires"]), false):
			problems.append("%s: Requires %s" % [rule["where"], complaint])

		for piece in String(rule["do"]).split(";"):
			var term := String(piece).strip_edges()
			if term == "":
				continue
			var colon := term.find(":")
			if colon <= 0:
				problems.append("%s: Do term '%s' — expected something like 'unlock:Brewery'"
					% [rule["where"], term])
				continue
			var kind := term.substr(0, colon).strip_edges().to_lower()
			if DEFERRED.has(kind):
				if term.substr(colon + 1).strip_edges() == "":
					problems.append("%s: '%s' has nothing after the colon"
						% [rule["where"], term])
				continue
			for complaint2 in DialogueGrammar.complaints(term, true):
				problems.append("%s: Do %s" % [rule["where"], complaint2])


## Every `story:` scene named anywhere, so the report can check they exist.
func story_targets() -> Array[String]:
	var out: Array[String] = []
	for rule in rules:
		for piece in String(rule["do"]).split(";"):
			var term := String(piece).strip_edges()
			if term.to_lower().begins_with("story:"):
				var scene := term.substr(6).strip_edges()
				if scene != "" and not out.has(scene):
					out.append(scene)
	return out


## Every condition string used, so the report can check the counters exist.
func all_conditions() -> Array[String]:
	var out: Array[String] = []
	for rule in rules:
		var condition := String(rule["requires"])
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
