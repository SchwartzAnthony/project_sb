class_name ContentReport
extends RefCounted

# =============================================================
#  THE CONTENT REPORT — one place that tells you what is broken
#
#  Every loader collects its own complaints. This gathers them into a
#  single report and then does the checks NO single loader can do on its
#  own, because they run across files:
#
#    * a Progression row that plays a story scene which does not exist
#    * a condition testing a counter that nothing ever fills in
#      (almost always a typo — `count:goles>=3`)
#    * a condition testing an unlock that nothing ever grants,
#      so the content behind it can never be reached
#
#  That last pair is the important one. A misspelled counter does not
#  crash and does not warn — the condition is simply false forever and the
#  content silently never appears. That is the single most likely way to
#  lose an afternoon, so it is checked at startup and named out loud.
#
#  Nothing here ever stops the game. It prints and moves on.
# =============================================================

var lines: Array[String] = []
var warnings: Array[String] = []


static func build() -> ContentReport:
	var report := ContentReport.new()
	report._gather()
	return report


## Print the whole thing. Called once at startup.
static func print_report() -> void:
	build()._print()


# =============================================================
#  GATHERING
# =============================================================

func _gather() -> void:
	var cards := CardDatabase.get_db()
	var story := DialogueDB.get_db()
	var stats := StatsRules.get_rules()
	var steps := Progression.get_rules()
	var base := BaseDB.get_db()

	lines.append("[content] %d cards, %d abilities, %d story lines across %d scene(s), %d stat rules, %d progression rows."
		% [cards.players.size(), cards.abilities.size(),
			story.line_count(), story.scenes.size(),
			stats.rules.size(), steps.rules.size()])
	lines.append("[content] %d building(s), %d visitor(s)."
		% [base.buildings.size(), base.visitors.size()])

	for problem in cards.problems:
		warnings.append("cards: " + problem)
	for problem in story.problems:
		warnings.append("story: " + problem)
	for problem in stats.problems:
		warnings.append("stats: " + problem)
	for problem in steps.problems:
		warnings.append("progression: " + problem)
	for problem in base.problems:
		warnings.append("base: " + problem)

	_check_story_targets(story, steps, base)
	_check_counters(story, stats, steps, base)
	_check_unlocks(story, steps, base)


## A Progression row that says story:chapter9 when no CSV defines chapter9.
func _check_story_targets(story: DialogueDB, steps: Progression, base: BaseDB) -> void:
	var known: Array[String] = story.scene_names()
	var known_keys: Array[String] = []
	for name_text in known:
		known_keys.append(CardDatabase._normalise(name_text))

	var wanted_scenes: Array[String] = steps.story_targets()
	for extra in base.story_targets():
		if not wanted_scenes.has(extra):
			wanted_scenes.append(extra)

	for wanted in wanted_scenes:
		if not known_keys.has(CardDatabase._normalise(wanted)):
			warnings.append("plays story '%s', but no CSV defines a Scene by that name. Scenes found: %s"
				% [wanted, ", ".join(known) if not known.is_empty() else "(none)"])


## Counters that are READ by a condition but never WRITTEN by anything.
func _check_counters(story: DialogueDB, stats: StatsRules, steps: Progression,
		base: BaseDB) -> void:
	var written: Array[String] = stats.counter_patterns.duplicate()

	# Effects can also write counters directly — count:coins+10.
	for expression in _all_effects(story, steps, base):
		for term in _terms(expression):
			if term.to_lower().begins_with("count:"):
				var body := term.substr(6).strip_edges()
				var cut := body.length()
				for op in ["+", "-", "="]:
					var at := body.find(op)
					if at > 0:
						cut = mini(cut, at)
				var name_text := body.substr(0, cut).strip_edges()
				if name_text != "" and not written.has(name_text):
					written.append(name_text)

	var reported: Array[String] = []
	for expression in _all_conditions(story, steps, base):
		for term in _terms(expression):
			var body := term
			if body.begins_with("!"):
				body = body.substr(1).strip_edges()
			if not body.to_lower().begins_with("count:"):
				continue

			var rest := body.substr(6).strip_edges()
			var cut := rest.length()
			for op in [">=", "<=", "!=", ">", "<", "="]:
				var at := rest.find(op)
				if at > 0:
					cut = mini(cut, at)
			var counter := rest.substr(0, cut).strip_edges()
			if counter == "" or reported.has(counter):
				continue

			var found := false
			for pattern in written:
				if _matches(counter, pattern):
					found = true
					break
			if not found:
				reported.append(counter)
				warnings.append("counter '%s' is tested by a condition but nothing ever adds to it — check the spelling against Stats.csv"
					% counter)


## Unlocks that are TESTED but never GRANTED, so the content is unreachable.
func _check_unlocks(story: DialogueDB, steps: Progression, base: BaseDB) -> void:
	var granted: Array[String] = []
	for expression in _all_effects(story, steps, base):
		for term in _terms(expression):
			if term.to_lower().begins_with("unlock:"):
				granted.append(CardDatabase._normalise(term.substr(7)))

	var reported: Array[String] = []
	for expression in _all_conditions(story, steps, base):
		for term in _terms(expression):
			var body := term
			if body.begins_with("!"):
				# "not unlocked" is fine to test before anything grants it.
				continue
			if not body.to_lower().begins_with("unlocked:"):
				continue
			var thing := body.substr(9).strip_edges()
			var key := CardDatabase._normalise(thing)
			if key == "" or reported.has(key) or granted.has(key):
				continue
			reported.append(key)
			warnings.append("'%s' is required somewhere but nothing ever unlocks it — that content cannot be reached yet"
				% thing)


# =============================================================
#  HELPERS
# =============================================================

func _all_conditions(story: DialogueDB, steps: Progression, base: BaseDB) -> Array[String]:
	var out: Array[String] = steps.all_conditions()
	out.append_array(base.all_conditions())
	for scene_key in story.scenes.keys():
		for line: DialogueLine in (story.scenes[scene_key] as Array):
			if line.requires.strip_edges() != "":
				out.append(line.requires)
			for choice in line.choices:
				if choice.requires.strip_edges() != "":
					out.append(choice.requires)
	return out


func _all_effects(story: DialogueDB, steps: Progression, base: BaseDB) -> Array[String]:
	var out: Array[String] = []
	for rule in steps.rules:
		out.append(String(rule["do"]))
	for entry in base.buildings:
		var action := String(entry["action"])
		if action.strip_edges() != "":
			out.append(action)
	for scene_key in story.scenes.keys():
		for line: DialogueLine in (story.scenes[scene_key] as Array):
			if line.effects.strip_edges() != "":
				out.append(line.effects)
			for choice in line.choices:
				if choice.effects.strip_edges() != "":
					out.append(choice.effects)
	return out


static func _terms(expression: String) -> Array[String]:
	var out: Array[String] = []
	for piece in expression.replace(" and ", ";").split(";"):
		var term := String(piece).strip_edges()
		if term != "":
			out.append(term)
	return out


## Does a concrete counter name match a Stats.csv pattern that may contain
## {facts}? `goals_with_brew_fire` matches `goals_with_brew_{brew}`.
static func _matches(name_text: String, pattern: String) -> bool:
	var name_key := CardDatabase._normalise(name_text)

	# Split the pattern on {...} FIRST, before normalising, or the braces
	# would be stripped and the token would fuse into the literal text.
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


# =============================================================
#  PRINTING
# =============================================================

func _print() -> void:
	for line in lines:
		print(line)

	if warnings.is_empty():
		print("[content] Nothing looks wrong. ")
		return

	print("[content] %d thing(s) worth a look:" % warnings.size())
	for warning in warnings:
		print("          - ", warning)
	print("[content] None of the above stops the game — it just means that content will not appear.")
