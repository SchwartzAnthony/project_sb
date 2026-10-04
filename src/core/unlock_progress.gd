class_name UnlockProgress
extends RefCounted

# =============================================================
#  UNLOCK PROGRESS — "how close am I, and what is missing?"
#
#  One file that reads every CSV in the project and answers, for every
#  single thing you can earn:
#
#      have I got it?
#      if not, how far along am I?
#      and what EXACTLY is missing, in words?
#
#  Two screens are built on it and neither one has any of this logic in it:
#
#    match_stats_screen.gd   the bars that fill and shine after a match
#    unlock_board.gd         the "why is this locked?" page
#
#  ---------------------------------------------------------------
#  THE ONE RULE THAT MATTERS
#
#  Whether something is DONE is decided by DialogueGrammar.test() — the
#  exact same call the game itself makes when it decides whether to show a
#  building. The bar's fill FRACTION is worked out separately here, and it
#  is decoration.
#
#  That split is deliberate. If this file worked out "done" for itself, it
#  could disagree with the game, and you would have a screen cheerfully
#  saying 100% next to a building that never appears. It cannot happen:
#  there is only one answer to "have I got it", and it is not computed here.
#  ---------------------------------------------------------------
#
#  WHAT IT FINDS, WITH NO LIST TO MAINTAIN
#    Buildings   every row of Buildings.csv
#    Talents     every row of Talents.csv
#    Brews       every row of Brews.csv
#    Fixtures    every row of Season.csv
#    Unlocks     every  unlock:Something  written anywhere at all, with the
#                requirement of whatever row grants it
#    Achievements  every row of Achievements.csv, plus every  flag:something
#                  a Progression row sets
#
#  Write a new Progression row tomorrow and it is on both screens, with a
#  working progress bar, without touching a line of code.
# =============================================================

## The kinds, in the order the board shows them.
const KINDS: Array[String] = ["Unlock", "Building", "Talent", "Brew", "Fixture", "Achievement"]

var entries: Array[Dictionary] = []


static func build(state: GameState) -> UnlockProgress:
	var out := UnlockProgress.new()
	out._gather(state)
	return out


# =============================================================
#  ASKING IT THINGS
# =============================================================

func in_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		if String(entry["kind"]) == kind:
			out.append(entry)
	return out


func done_count() -> int:
	var total := 0
	for entry in entries:
		if bool(entry["done"]):
			total += 1
	return total


## The things you have NOT got, closest first. This is what the post-match
## screen shows: "here is what you are nearly at".
##
## Anything at zero is left out — a bar that has never moved tells the player
## nothing and would crowd out the ones that have.
func nearest(limit: int) -> Array[Dictionary]:
	var open_ones: Array[Dictionary] = []
	for entry in entries:
		if bool(entry["done"]):
			continue
		if float(entry["fraction"]) <= 0.001:
			continue
		open_ones.append(entry)

	# A building and the unlock that opens it are usually both called "Pub".
	# On the board, where you are reading carefully, seeing both is useful.
	# On a post-match summary it is just the same bar twice, so only the
	# furthest-along one of each name survives.
	var best_by_name: Dictionary = {}
	for entry in open_ones:
		var key := CardDatabase._normalise(String(entry["name"]))
		if not best_by_name.has(key) \
				or float((best_by_name[key] as Dictionary)["fraction"]) < float(entry["fraction"]):
			best_by_name[key] = entry
	open_ones.clear()
	for key in best_by_name.keys():
		open_ones.append(best_by_name[key])

	# An explicit insertion sort, highest fraction first. The list is short,
	# and it keeps two equal fractions in the order the CSVs listed them.
	var sorted: Array[Dictionary] = []
	for entry in open_ones:
		var at := sorted.size()
		for i in sorted.size():
			if float(sorted[i]["fraction"]) < float(entry["fraction"]):
				at = i
				break
		sorted.insert(at, entry)

	if limit <= 0 or sorted.size() <= limit:
		return sorted
	var trimmed: Array[Dictionary] = []
	for i in limit:
		trimmed.append(sorted[i])
	return trimmed


# =============================================================
#  GATHERING
# =============================================================

func _gather(state: GameState) -> void:
	entries.clear()
	if state == null:
		return

	var base := BaseDB.get_db()
	var talents := TalentDB.get_db()
	var brews := BrewDB.get_db()
	var season := SeasonDB.get_db()
	var steps := Progression.get_rules()
	var story := DialogueDB.get_db()

	# --- Buildings ---
	# The last argument is the ART, straight from the CSV's own Art column.
	# The unlock board draws it as the row's icon; a blank one gets a
	# labelled placeholder. No new spreadsheet was needed to give rows icons.
	for entry in base.buildings:
		_add(state, "Building", String(entry["name"]), String(entry["requires"]),
			String(entry["description"]), "Buildings.csv", "", "",
			String(entry.get("art", "")))

	# --- Talents. A talent also needs its parent taken and points in hand,
	#     neither of which lives in its Requires column, so they are spelled
	#     out here as extra conditions.
	for entry in talents.talents:
		var condition := String(entry["requires"])
		var parent := String(entry["parent"]).strip_edges()
		if parent != "":
			condition = _join(condition, "unlocked:%s" % parent)
		var cost := int(entry["cost"])
		if cost > 0:
			condition = _join(condition, "count:%s>=%d" % [TalentDB.POINTS, cost])
		_add(state, "Talent", String(entry["name"]), condition,
			String(entry["description"]), "Talents.csv",
			"unlocked:%s" % String(entry["id"]), String(entry["id"]),
			String(entry.get("art", "")))

	# --- Brews ---
	# Brews.csv calls its column Artwork rather than Art. That is the only
	# difference, and it is handled here rather than by renaming your column.
	for entry in brews.brews:
		_add(state, "Brew", String(entry["name"]), String(entry["requires"]),
			String(entry["description"]), "Brews.csv", "", "",
			String(entry.get("artwork", "")))

	# --- Fixtures. "Done" is not a condition — it is whether it was played. ---
	for entry in season.fixtures:
		var played := SeasonDB.result_for(String(entry["id"]), state) != ""
		var reached := SeasonDB.current_number(state) >= int(entry["number"])
		var total := maxi(1, season.last_number())
		entries.append({
			"kind": "Fixture",
			"name": "Match %d - %s" % [int(entry["number"]), entry["opponent"]],
			# Season.csv has no Art column, so a fixture always draws the
			# placeholder. Add one there and pass it here if you want icons.
			"art": "",
			"detail": String(entry["description"]),
			"requires": "",
			"done": played,
			"fraction": 1.0 if played else clampf(
				float(SeasonDB.current_number(state) - 1) / float(int(entry["number"])), 0.0, 0.99),
			"parts": [] as Array[Dictionary],
			"missing": "" if played else ("Next up." if reached
				else "Play the %d fixture%s before it." % [
					int(entry["number"]) - SeasonDB.current_number(state),
					"" if int(entry["number"]) - SeasonDB.current_number(state) == 1 else "s"]),
			"where": "Season.csv",
			"progress_text": "%d of %d played" % [SeasonDB.played(state), total],
		})

	# --- Every unlock anyone ever grants, with the condition of whatever
	#     grants it. This is where "why has the Brewery not appeared" is
	#     answered, because the Progression row that grants it is found here
	#     rather than named by hand.
	for granter in _granters(steps, talents, base, season, story):
		# DONE is "do I have it", never "could I get it". The Cup is granted by
		# winning the final, and that fixture has no condition of its own — so
		# testing the granter's condition would have called the Cup yours
		# before a ball was kicked.
		_add(state, "Unlock", String(granter["thing"]), String(granter["condition"]),
			String(granter["how"]), String(granter["where"]),
			"unlocked:%s" % String(granter["thing"]))

	# ============ ACHIEVEMENTS, WHICH ARE THE ROOT ============
	#
	# Every row of Achievements.csv, with its own condition and — the part
	# that matters on this screen — WHAT IT HANDS OVER. An achievement is the
	# only thing in the game that creates an unlock out of nothing, so this is
	# where a chain starts: "the Brewery needs the First Brew, which needs
	# three goals with a fire brew, and you have one."
	#
	# A hidden one stays off the board until it is earned, which is what
	# `Hidden` is for.
	for row in AchievementBook.rows():
		if bool(row["hidden"]) and not AchievementBook.earned(String(row["id"]), state):
			continue
		var gives := ""
		if not row["unlocks"].is_empty():
			gives = "unlocks " + ", ".join(row["unlocks"])
		_add(state, "Achievement", String(row["name"]), String(row["needs"]),
			String(row["description"]) if gives == "" else "%s  (%s)" % [row["description"], gives],
			"Achievements.csv",
			"flag:%s%s" % [AchievementBook.EARNED_PREFIX, String(row["id"]).to_lower()],
			"", String(row["art"]))

		# AND THE THINGS IT HANDS OVER, each with the achievement as the
		# reason. Without this an unlock granted only by an achievement had
		# no row on the board at all — you could not see why the Brewery was
		# shut, because nothing in Progression.csv mentioned it.
		for thing in row["unlocks"]:
			_add(state, "Unlock", String(thing), String(row["needs"]),
				"from the achievement '%s'" % row["name"], "Achievements.csv",
				"unlocked:%s" % String(thing))

	# --- Achievements: a flag a Progression row sets ---
	for rule in steps.rules:
		for piece in String(rule["do"]).split(";"):
			var term := String(piece).strip_edges()
			if not term.to_lower().begins_with("flag:"):
				continue
			var flag_name := term.substr(5).strip_edges()
			if flag_name == "" or flag_name.begins_with(Progression.DONE_PREFIX):
				continue
			_add(state, "Achievement", state.pretty(flag_name),
				String(rule["requires"]), "", String(rule["where"]),
				"flag:%s" % flag_name)

	_follow_chains()


# =============================================================
#  FOLLOWING THE CHAIN
#
#  THIS IS THE POINT OF THE WHOLE SCREEN.
#
#  The Pub building's Requires is `unlocked:Pub`. On its own that makes the
#  board say "the Pub needs the Pub unlocked", which is true, useless, and
#  exactly the runaround you get today from reading the spreadsheets by hand.
#
#  The real answer is one row further along: a Progression row grants
#  `unlock:Pub`, and IT is the one that wants the Brewery and five matches.
#  So an unmet `unlocked:X` is replaced by whatever X itself is waiting for,
#  and the bar inherits X's progress instead of sitting flat at zero.
#
#  It follows up to CHAIN_DEPTH links and never revisits something it has
#  already been through, so a pair of CSV rows that require each other makes
#  a stubborn entry rather than a frozen game.
#
#  TWO is the limit on purpose. "The Pub, which needs the Brewery, which
#  needs three fire-brewed goals" is a sentence. A third "which needs" is
#  not, and the honest thing at that point is to let the player open the
#  board and look up the next link themselves.
# =============================================================

const CHAIN_DEPTH := 2


func _follow_chains() -> void:
	# Indexed by the name OTHER rows use to require it. Unlocks are required
	# by name; talents are required by their ID, which is why a talent's `key`
	# is its ID rather than its name — otherwise `unlocked:swarm` would stay on
	# screen as raw spreadsheet text instead of "Swarm, which needs...".
	var by_name: Dictionary = {}
	for entry in entries:
		var kind := String(entry["kind"])
		if kind != "Unlock" and kind != "Talent":
			continue
		var key := CardDatabase._normalise(String(entry["key"]))
		if key != "" and not by_name.has(key):
			by_name[key] = entry

	for entry in entries:
		if bool(entry["done"]):
			continue

		# The visited list starts EMPTY for anything that is not itself an
		# Unlock. That matters more than it looks: the Pub building and the
		# `unlock:Pub` that opens it are both called "Pub", so seeding the list
		# with the entry's own name made the building refuse to look up the
		# unlock of the same name — and it went on saying "the Pub needs the
		# Pub", which is the exact uselessness this pass exists to remove.
		var visited: Array[String] = []
		if String(entry["kind"]) == "Unlock":
			visited.append(CardDatabase._normalise(String(entry["name"])))
		_expand(entry, by_name, visited, 0)


func _expand(entry: Dictionary, by_name: Dictionary, visited: Array[String],
		depth: int) -> void:
	if depth >= CHAIN_DEPTH:
		return

	var parts: Array[Dictionary] = entry["parts"]
	var changed := false

	for part in parts:
		if bool(part["done"]):
			continue
		var needs := String(part.get("needs", "")).strip_edges()
		if needs == "":
			continue

		var key := CardDatabase._normalise(needs)
		if key == "" or visited.has(key) or not by_name.has(key):
			continue

		var linked: Dictionary = by_name[key]
		if bool(linked["done"]):
			continue

		visited.append(key)
		_expand(linked, by_name, visited, depth + 1)

		# Say what the thing it is waiting for is itself waiting for, using its
		# readable NAME rather than whatever the CSV required it by — a talent
		# is required by its ID, and "unlocked:swarm" is spreadsheet text, not
		# an answer. When even that has nothing to report, do not end up
		# writing "which needs Not yet."
		var reason := String(linked["first_missing"])
		var readable := String(linked["name"])
		if reason == "Not yet." or reason.strip_edges() == "":
			part["text"] = "%s, which you have not earned yet" % readable
		else:
			part["text"] = "%s, which needs %s" % [readable, reason]
		part["fraction"] = float(linked["fraction"])
		if String(part["headline"]) == "" and String(linked["progress_text"]) != "":
			part["headline"] = String(linked["progress_text"])
		changed = true

	if changed:
		_recompute(entry)


## Rebuild an entry's fraction, its missing line and its headline from its
## parts, after the chain-follower has rewritten some of them.
func _recompute(entry: Dictionary) -> void:
	var parts: Array[Dictionary] = entry["parts"]
	if parts.is_empty():
		return

	var total := 0.0
	var missing: Array[String] = []
	var headline := ""
	for part in parts:
		total += float(part["fraction"])
		# The same requirement can arrive from two links of a chain — a talent
		# and its parent both wanting a talent point, say. Saying it twice
		# makes the line longer and no clearer.
		if not bool(part["done"]) and not missing.has(String(part["text"])):
			missing.append(String(part["text"]))
		if headline == "" and String(part["headline"]) != "":
			headline = String(part["headline"])

	# The same "never draw a full bar on an unfinished thing" rule as above.
	entry["fraction"] = clampf(total / float(parts.size()), 0.0,
		1.0 if bool(entry["done"]) else 0.99)
	entry["missing"] = "  and  ".join(missing) if not missing.is_empty() else "Not yet."
	entry["progress_text"] = headline
	entry["first_missing"] = "" if missing.is_empty() else (
		missing[0] + ("  (and more)" if missing.size() > 1 else ""))


## Everything in the project that says `unlock:Something`, and what it takes.
func _granters(steps: Progression, talents: TalentDB, base: BaseDB,
		season: SeasonDB, story: DialogueDB) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Array[String] = []

	var sources: Array[Dictionary] = []
	for rule in steps.rules:
		sources.append({"effects": String(rule["do"]), "condition": String(rule["requires"]),
			"how": "A Progression row.", "where": String(rule["where"])})
	for entry in talents.talents:
		sources.append({"effects": String(entry["effects"]),
			"condition": "unlocked:%s" % String(entry["id"]),
			"how": "Take the %s talent." % entry["name"], "where": "Talents.csv"})
	for entry in base.buildings:
		sources.append({"effects": String(entry["action"]),
			"condition": String(entry["requires"]),
			"how": "Click %s at the base." % entry["name"], "where": "Buildings.csv"})
	for entry in season.fixtures:
		# The condition is REACHING that fixture. Without it the reward would
		# have no requirement at all, and "no requirement" reads as "already
		# done" — which is how the Cup came to be yours before kick-off.
		sources.append({"effects": String(entry["on_win"]),
			"condition": "count:%s>=%d" % [SeasonDB.MATCH, int(entry["number"])],
			"how": "Win match %d against %s." % [
				int(entry["number"]), entry["opponent"]], "where": "Season.csv"})
	for scene_key in story.scenes.keys():
		for line: DialogueLine in (story.scenes[scene_key] as Array):
			sources.append({"effects": line.effects, "condition": line.requires,
				"how": "Something said in the story.", "where": "Dialogue.csv"})
			for choice in line.choices:
				sources.append({"effects": choice.effects, "condition": choice.requires,
					"how": "A choice in the story.", "where": "Dialogue.csv"})

	for source in sources:
		for piece in String(source["effects"]).split(";"):
			var term := String(piece).strip_edges()
			if not term.to_lower().begins_with("unlock:"):
				continue
			var thing := term.substr(7).strip_edges()
			var key := CardDatabase._normalise(thing)
			if thing == "" or seen.has(key):
				continue
			seen.append(key)
			out.append({
				"thing": thing,
				"condition": String(source["condition"]),
				"how": String(source["how"]),
				"where": String(source["where"]),
			})
	return out


## Add one thing you can earn. `done_test` overrides the condition when the
## two differ — a talent is "done" when you have TAKEN it, which is not the
## same as being able to afford it.
func _add(state: GameState, kind: String, name_text: String, condition: String,
		detail: String, where: String, done_test: String = "",
		lookup_key: String = "", art: String = "") -> void:
	if name_text.strip_edges() == "":
		return

	var truth := done_test if done_test != "" else condition
	# THE ONE RULE: the game decides, not this file.
	var done := DialogueGrammar.test(truth, state)

	var progress := progress_of(condition, state)
	var parts: Array[Dictionary] = progress["parts"]

	var missing: Array[String] = []
	for part in parts:
		if not bool(part["done"]):
			missing.append(String(part["text"]))

	# TWO RULES ABOUT THE BAR, BOTH LEARNED THE HARD WAY:
	#
	#   Something you have not got, with no requirement anyone can see, is at
	#   ZERO — not full. An empty condition passes every test, so without this
	#   it would draw as finished.
	#
	#   And an unfinished bar never reaches the end. A full bar next to
	#   "not yet" is the screen contradicting itself, and the player believes
	#   the bar.
	var bar := float(progress["fraction"])
	if not done:
		bar = 0.0 if condition.strip_edges() == "" else minf(bar, 0.99)

	entries.append({
		"kind": kind,
		"name": name_text,
		# The file name from the source CSV's Art column, for the row's icon.
		# Blank is normal and means "draw the placeholder".
		"art": art,
		# How other rows refer to this thing. A talent is required by its ID
		# (`unlocked:swarm`) but shown by its name (Swarm), and the chain
		# follower needs both to turn one into the other.
		"key": lookup_key if lookup_key != "" else name_text,
		"detail": detail,
		"requires": condition,
		# What "done" is tested against (round AC: the test environment
		# satisfies this directly, so an achievement counts as earned).
		"done_test": truth,
		"done": done,
		"fraction": 1.0 if done else bar,
		"parts": parts,
		"missing": "Yours." if done else (
			"  and  ".join(missing) if not missing.is_empty() else "Not yet."),
		"where": where,
		"progress_text": String(progress["headline"]),
		# The FIRST thing missing, on its own. When this entry is embedded in
		# somebody else's line ("the Pub, which needs ..."), only this is used
		# — a nested list of everything turns one sentence into three.
		"first_missing": "" if done else (
			String(missing[0]) + ("  (and more)" if missing.size() > 1 else "")
			if not missing.is_empty() else ""),
	})


# =============================================================
#  HOW FAR ALONG IS ONE CONDITION?
#
#  This is the only clever bit, and it is not very clever: a condition is a
#  list of terms, each term is worth the same, and a `count:` term is the
#  only one that can be part-done. `count:matches_won>=5` with three wins is
#  three fifths of a term.
# =============================================================

static func progress_of(condition: String, state: GameState) -> Dictionary:
	var parts: Array[Dictionary] = []
	if state == null or condition.strip_edges() == "":
		return {"fraction": 1.0, "parts": parts, "headline": ""}

	var total := 0.0
	var headline := ""

	for term in _terms(condition):
		var part := _part(term, state)
		parts.append(part)
		total += float(part["fraction"])
		# The first counting term is the one worth putting on the bar.
		if headline == "" and String(part["headline"]) != "":
			headline = String(part["headline"])

	if parts.is_empty():
		return {"fraction": 1.0, "parts": parts, "headline": ""}
	return {
		"fraction": clampf(total / float(parts.size()), 0.0, 1.0),
		"parts": parts,
		"headline": headline,
	}


static func _part(term_text: String, state: GameState) -> Dictionary:
	var negate := term_text.begins_with("!")
	var body := term_text.substr(1).strip_edges() if negate else term_text

	var colon := body.find(":")
	if colon <= 0:
		return {"text": body, "fraction": 1.0, "done": true, "headline": "", "needs": "", "term": term_text}

	var kind := body.substr(0, colon).strip_edges().to_lower()
	var rest := body.substr(colon + 1).strip_edges()
	var truth := DialogueGrammar.test(term_text, state)

	match kind:
		"count":
			var op := ""
			for candidate in [">=", "<=", "!=", ">", "<", "="]:
				if rest.find(candidate) > 0:
					op = candidate
					break
			if op == "":
				var any := state.count(rest)
				return {"text": "%s: any" % state.pretty(rest),
					"fraction": 1.0 if any > 0 else 0.0, "done": truth,
					"headline": "%d" % any, "needs": "", "term": term_text}

			var at := rest.find(op)
			var counter := rest.substr(0, at).strip_edges()
			var wanted_text := rest.substr(at + op.length()).strip_edges()
			var wanted := int(wanted_text) if wanted_text.is_valid_int() else 0
			var have := state.count(counter)

			# Only "at least this many" is a journey worth drawing a bar for.
			# "at most" and "not equal to" are already true or already lost.
			if op == ">=" or op == ">":
				var need := wanted + (1 if op == ">" else 0)
				var fraction := 1.0 if need <= 0 else clampf(float(have) / float(need), 0.0, 1.0)
				return {
					"text": "%s: %d of %d" % [state.pretty(counter), have, need],
					"fraction": 1.0 if truth else fraction,
					"done": truth,
					"headline": "%d of %d" % [mini(have, need), need],
					"needs": "",
					"term": term_text,
				}

			return {"text": DialogueGrammar.describe(term_text).trim_prefix("Needs ").trim_suffix("."),
				"fraction": 1.0 if truth else 0.0, "done": truth, "headline": "", "needs": "", "term": term_text}

		"unlocked":
			# `needs` is the hook the chain-follower below uses. Without it,
			# a locked building could only ever say "needs Pub", which is not
			# an answer to "why is the Pub locked".
			return {"text": ("without %s" % rest) if negate else ("needs %s" % rest),
				"fraction": 1.0 if truth else 0.0, "done": truth, "headline": "",
				"needs": "" if negate else rest, "term": term_text}

		"flag":
			return {"text": ("not %s" % state.pretty(rest)) if negate else state.pretty(rest),
				"fraction": 1.0 if truth else 0.0, "done": truth, "headline": "", "needs": "", "term": term_text}

		_:
			return {"text": body, "fraction": 1.0 if truth else 0.0,
				"done": truth, "headline": "", "needs": "", "term": term_text}


# =============================================================
#  "JUST GIVE ME IT" — used by the save inspector
#
#  Grant, by hand, everything one entry is still waiting for. A `count:x>=5`
#  is set to exactly 5, a flag is switched on, an unlock is granted.
#
#  It satisfies each requirement DIRECTLY rather than following the chain: if
#  something wants `unlocked:Pub`, you get the Pub, and you do not have to
#  play the five matches that would normally have earned it. That is the whole
#  point of a test tool.
#
#  Returns what it did, one line per change, for the screen to show.
static func satisfy(entry: Dictionary, state: GameState) -> Array[String]:
	var done_lines: Array[String] = []
	if state == null or entry.is_empty():
		return done_lines

	var parts: Array[Dictionary] = entry["parts"]
	for part in parts:
		if bool(part["done"]):
			continue
		var term := String(part.get("term", "")).strip_edges()
		if term == "":
			continue

		var negate := term.begins_with("!")
		var body := term.substr(1).strip_edges() if negate else term
		var colon := body.find(":")
		if colon <= 0:
			continue
		var kind := body.substr(0, colon).strip_edges().to_lower()
		var rest := body.substr(colon + 1).strip_edges()

		match kind:
			"count":
				var op := ""
				for candidate in [">=", "<=", "!=", ">", "<", "="]:
					if rest.find(candidate) > 0:
						op = candidate
						break
				if op == "":
					state.add_count(rest, 1)
					done_lines.append("%s +1" % rest)
					continue
				var at := rest.find(op)
				var counter := rest.substr(0, at).strip_edges()
				var wanted_text := rest.substr(at + op.length()).strip_edges()
				var wanted := int(wanted_text) if wanted_text.is_valid_int() else 0
				if op == ">":
					wanted += 1
				state.set_count(counter, wanted)
				done_lines.append("%s = %d" % [counter, wanted])
			"flag":
				state.set_flag(rest, not negate)
				done_lines.append("%s%s" % ["cleared " if negate else "", rest])
			"unlocked":
				if not negate:
					state.unlock(rest)
					done_lines.append("unlocked %s" % rest)
			"is":
				var equals := rest.find("=")
				if equals > 0:
					state.set_text(rest.substr(0, equals).strip_edges(),
						rest.substr(equals + 1).strip_edges())
					done_lines.append(rest)

	# Some things are not a condition at all — a talent is "taken", an unlock
	# is "held". Grant that directly too, or the entry would still show locked
	# with nothing left to satisfy.
	var kind_text := String(entry["kind"])
	if kind_text == "Unlock":
		state.unlock(String(entry["name"]))
		done_lines.append("unlocked %s" % entry["name"])
	elif kind_text == "Talent":
		state.unlock(String(entry["key"]))
		done_lines.append("took %s" % entry["name"])

	return done_lines


static func _terms(expression: String) -> Array[String]:
	var out: Array[String] = []
	for piece in expression.replace(" and ", ";").split(";"):
		var term := String(piece).strip_edges()
		if term != "":
			out.append(term)
	return out


static func _join(a: String, b: String) -> String:
	if a.strip_edges() == "":
		return b
	if b.strip_edges() == "":
		return a
	return "%s;%s" % [a, b]
