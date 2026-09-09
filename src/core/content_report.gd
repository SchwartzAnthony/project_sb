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
	var talents := TalentDB.get_db()
	var brews := BrewDB.get_db()
	var season := SeasonDB.get_db()
	var audio := AudioDB.get_db()
	var squads := TeamDB.get_db()

	lines.append("[content] %d cards, %d abilities, %d story lines across %d scene(s), %d stat rules, %d progression rows."
		% [cards.players.size(), cards.abilities.size(),
			story.line_count(), story.scenes.size(),
			stats.rules.size(), steps.rules.size()])
	lines.append("[content] %d building(s), %d visitor(s), %d talent(s) in %d tree(s), %d brew(s)."
		% [base.buildings.size(), base.visitors.size(),
			talents.talents.size(), talents.tree_names().size(), brews.brews.size()])
	lines.append("[content] %d fixture(s) in the season, the last being Match %d."
		% [season.fixtures.size(), season.last_number()])
	var modes := MatchMode.get_db()
	lines.append("[content] %d opposing team(s), %d sound cue(s), %d match mode(s): %s."
		% [squads.teams.size(), audio.cues.size(), modes.modes.size(),
			", ".join(_mode_words(modes))])

	for problem in modes.problems:
		warnings.append("modes: " + problem)

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
	for problem in talents.problems:
		warnings.append("talents: " + problem)
	for problem in brews.problems:
		warnings.append("brews: " + problem)
	for problem in season.problems:
		warnings.append("season: " + problem)
	for problem in squads.problems:
		warnings.append("teams: " + problem)
	for problem in audio.problems:
		warnings.append("audio: " + problem)

	_check_story_targets(story, steps, base)
	_check_counters(story, stats, steps, base, talents)
	_check_unlocks(story, steps, base, talents)
	_check_tuning_bonuses(talents)
	_check_tier_ladders(cards)


## ============ CAN EVERY CLASS FIELD A LEGAL TEAM? ============
##
## The rule is that a tier holds one card of each power — Tier I is a 0, a 1
## and a 2. A class with no 1-power Tier II card therefore cannot fill Tier
## II, and the match will field two cards there instead of three.
##
## That is invisible until you are watching a match and counting heads, so
## it is checked here and named: which class, which tier, which power.
func _check_tier_ladders(cards: CardDatabase) -> void:
	var ladder_lines: Array[String] = []
	for tier in TierLadder.TIERS:
		ladder_lines.append("Tier %s = %s" % [tier,
			", ".join(_powers_as_words(TierLadder.rungs(tier, cards)))])
	lines.append("[content] The ladder: %s." % "  ·  ".join(ladder_lines))

	# One pass per class, so a fault is reported against the class that owns it.
	var classes: Array[String] = []
	for card in cards.players:
		var key := card.unit_type.strip_edges()
		if key != "" and not classes.has(key):
			classes.append(key)
	classes.sort()

	# Duplicates first: a doubled file is the cause of most of the per-class
	# complaints below, so naming it first saves reading the rest.
	for problem in TierLadder.check_duplicate_names(cards):
		warnings.append("ladder: " + problem)

	for unit_type in classes:
		for problem in TierLadder.check_class(unit_type, cards):
			warnings.append("ladder: " + problem)

	for problem in TierLadder.check_mirrored_powers(cards):
		warnings.append("ladder: " + problem)


## "Season Match (90m, in the table)", "Quick Match (no clock, not recorded)"
static func _mode_words(modes: MatchMode) -> Array[String]:
	var out: Array[String] = []
	for key in modes.modes.keys():
		var entry: Dictionary = modes.modes[key]
		var clock := "no clock" if float(entry["timer"]) <= 0.0 \
			else "%dm" % int(float(entry["timer"]))
		out.append("%s (%s, %s)" % [entry["name"], clock,
			"in the table" if bool(entry["records"]) else "not recorded"])
	return out


static func _powers_as_words(powers: Array[int]) -> Array[String]:
	var out: Array[String] = []
	for power in powers:
		out.append(str(power))
	return out


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
	for extra2 in SeasonDB.get_db().story_targets():
		if not wanted_scenes.has(extra2):
			wanted_scenes.append(extra2)

	for wanted in wanted_scenes:
		if not known_keys.has(CardDatabase._normalise(wanted)):
			warnings.append("plays story '%s', but no CSV defines a Scene by that name. Scenes found: %s"
				% [wanted, ", ".join(known) if not known.is_empty() else "(none)"])


## Counters that are READ by a condition but never WRITTEN by anything.
func _check_counters(story: DialogueDB, stats: StatsRules, steps: Progression,
		base: BaseDB, talents: TalentDB) -> void:
	var written: Array[String] = stats.counter_patterns.duplicate()

	# The season keeps its own counters in code rather than through Stats.csv,
	# so they are added by hand here. Without this, a perfectly good
	# `count:season_wins>=3` in one of your CSVs would be reported as a typo.
	for season_counter in SeasonDB.COUNTERS:
		if not written.has(season_counter):
			written.append(season_counter)

	# Effects can also write counters directly — count:coins+10.
	for expression in _all_effects(story, steps, base, talents):
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
	for expression in _all_conditions(story, steps, base, talents):
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
func _check_unlocks(story: DialogueDB, steps: Progression, base: BaseDB,
		talents: TalentDB) -> void:
	var granted: Array[String] = []
	for expression in _all_effects(story, steps, base, talents):
		for term in _terms(expression):
			if term.to_lower().begins_with("unlock:"):
				granted.append(CardDatabase._normalise(term.substr(7)))

	var reported: Array[String] = []
	for expression in _all_conditions(story, steps, base, talents):
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


## A talent that raises a Tuning value only works if that value exists.
## `count:tune_pres_speed+12` (one `s` missing) silently does nothing, so it
## is checked here against the real Tuning.csv.
func _check_tuning_bonuses(talents: TalentDB) -> void:
	var db := CardDatabase.get_db()
	var reported: Array[String] = []

	for expression in talents.all_effects():
		for term in _terms(expression):
			if not term.to_lower().begins_with("count:tune"):
				continue
			var body := term.substr(6).strip_edges()
			var cut := body.length()
			for op in ["+", "-", "="]:
				var at := body.find(op)
				if at > 0:
					cut = mini(cut, at)
			var counter := body.substr(0, cut).strip_edges()
			var target := CardDatabase._normalise(counter).substr(4)
			if target == "" or reported.has(target):
				continue
			if not db.tuning.has(target):
				reported.append(target)
				warnings.append("a talent raises '%s', but Tuning.csv has no row of that name — the talent would do nothing"
					% counter)


# =============================================================
#  HELPERS
# =============================================================

func _all_conditions(story: DialogueDB, steps: Progression, base: BaseDB,
		talents: TalentDB) -> Array[String]:
	var out: Array[String] = steps.all_conditions()
	out.append_array(base.all_conditions())
	out.append_array(talents.all_conditions())
	out.append_array(BrewDB.get_db().all_conditions())
	out.append_array(SeasonDB.get_db().all_conditions())
	out.append_array(TeamDB.get_db().all_conditions())
	for cue in AudioDB.get_db().cues:
		var cue_condition := String(cue["requires"])
		if cue_condition.strip_edges() != "":
			out.append(cue_condition)
	for scene_key in story.scenes.keys():
		for line: DialogueLine in (story.scenes[scene_key] as Array):
			if line.requires.strip_edges() != "":
				out.append(line.requires)
			for choice in line.choices:
				if choice.requires.strip_edges() != "":
					out.append(choice.requires)
	return out


func _all_effects(story: DialogueDB, steps: Progression, base: BaseDB,
		talents: TalentDB) -> Array[String]:
	var out: Array[String] = []
	out.append_array(talents.all_effects())
	out.append_array(SeasonDB.get_db().all_effects())
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
##
## There is ONE implementation of this, in stats_rules.gd, and both this
## report and the post-match screen call it. It used to be written out twice,
## which is exactly how two files quietly start disagreeing about whether a
## counter exists.
static func _matches(name_text: String, pattern: String) -> bool:
	return StatsRules.matches_pattern(name_text, pattern)


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
