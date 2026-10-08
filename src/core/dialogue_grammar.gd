class_name DialogueGrammar
extends RefCounted

# =============================================================
#  DIALOGUE GRAMMAR — the little language in the Requires and Effects
#  columns of Dialogue.csv.
#
#  Nothing here knows about screens or CSV files. It takes a string and a
#  GameState and answers one of two questions: is this true, and what does
#  this change.
#
#  THE GRAMMAR, in full. Both columns take a list separated by
#  semicolons; every term in a Requires must pass.
#
#  REQUIRES                 true when
#    flag:brave             the flag is set
#    !flag:brave            the flag is NOT set
#    unlocked:Lorelei       you have unlocked it
#    !unlocked:Lorelei      you have not
#    count:gold>=10         a number comparison. >= > <= < = != all work
#    is:next_class=Lorelei  a stored word matches
#    !is:next_class=Lorelei it does not
#
#  EFFECTS                  does
#    flag:brave             set a flag
#    flag:brave=false       clear a flag
#    count:gold+10          add to a number
#    count:gold-5           take away
#    count:gold=0           set it outright
#    unlock:Lorelei         unlock a card, a class, anything by name
#    set:next_class=Lorelei remember a word
#    clear:next_class       forget it
#
#  count: and set: are the escape hatches. Base building is
#  count:wood+10. An achievement is flag:beat_the_keeper. A shop price
#  is count:gold-25. None of that needs new code — write it in the
#  spreadsheet and it works.
# =============================================================

const COMPARISONS: Array[String] = [">=", "<=", "!=", ">", "<", "="]


# =============================================================
#  RUNNING THE GRAMMAR
# =============================================================


## Does every term in `condition` hold? A blank condition is always true, so
## leaving the column empty means "always show this".
static func test(condition: String, state: GameState) -> bool:
	if condition.strip_edges() == "" or state == null:
		return true

	for term in _split(condition):
		if not _test_one(term, state):
			return false
	return true


## Apply every term in `effects` to `state`. Unknown terms are ignored here
## and reported by DialogueDB at load time instead, so a typo shows up once in
## the Output panel rather than silently every time the line plays.
static func apply(effects: String, state: GameState) -> void:
	if effects.strip_edges() == "" or state == null:
		return
	for term in _split(effects):
		_apply_one(term, state)


## Everything wrong with a Requires or Effects string, in plain words.
## Empty array means it is fine.
static func complaints(expression: String, is_effect: bool) -> Array[String]:
	var out: Array[String] = []
	if expression.strip_edges() == "":
		return out

	for term in _split(expression):
		var body := term
		if body.begins_with("!"):
			if is_effect:
				out.append("'%s' — effects cannot start with '!'" % term)
				continue
			body = body.substr(1).strip_edges()

		var colon := body.find(":")
		if colon <= 0:
			out.append("'%s' — expected something like 'flag:name'" % term)
			continue

		var kind := body.substr(0, colon).strip_edges().to_lower()
		var rest := body.substr(colon + 1).strip_edges()
		if rest == "":
			out.append("'%s' — nothing after the colon" % term)
			continue

		var allowed := ["flag", "count", "unlock", "set", "clear", "sign", "release", "recruit"] if is_effect \
			else ["flag", "count", "unlocked", "is"]
		if not allowed.has(kind):
			out.append("'%s' — '%s' is not one of %s" % [term, kind, ", ".join(allowed)])
			continue

		if kind == "recruit" and RecruitBook.parse(rest.split("=")[0]).is_empty():
			out.append("'%s' — expected a tier and a power, e.g. recruit:I0 or recruit:III3=Johannes" % term)
			continue

		if kind == "count":
			if is_effect and _count_operator(rest) == "":
				out.append("'%s' — expected count:name+1, count:name-1 or count:name=1" % term)
			elif not is_effect and _comparison_in(rest) == "":
				out.append("'%s' — expected a comparison, e.g. count:gold>=10" % term)

	return out


## Turn a condition into a sentence a PLAYER can read, for a locked building
## or a greyed-out option. "count:goals_with_brew_fire>=3" becomes
## "Needs goals with brew fire: 3 or more."
##
## Deliberately literal: it reads your counter names back to you, so a name
## like `goals_with_brew_fire` becomes readable on its own and a name like
## `gwbf` does not. That is a nudge toward naming counters in full words.
static func describe(condition: String) -> String:
	if condition.strip_edges() == "":
		return ""

	var parts: Array[String] = []
	for term in _split(condition):
		var negate := term.begins_with("!")
		var body := term.substr(1).strip_edges() if negate else term

		var colon := body.find(":")
		if colon <= 0:
			continue
		var kind := body.substr(0, colon).strip_edges().to_lower()
		var rest := body.substr(colon + 1).strip_edges()

		match kind:
			"flag":
				parts.append("%s%s" % ["not " if negate else "", _words(rest)])
			"unlocked":
				parts.append("%s%s" % ["without " if negate else "", _words(rest)])
			"count":
				var op := _comparison_in(rest)
				if op == "":
					parts.append("any %s" % _words(rest))
				else:
					var at := rest.find(op)
					var counter := _words(rest.substr(0, at))
					var wanted := rest.substr(at + op.length()).strip_edges()
					var phrase := "at least"
					match op:
						"<=": phrase = "at most"
						">": phrase = "more than"
						"<": phrase = "fewer than"
						"=": phrase = "exactly"
						"!=": phrase = "any number but"
					# ROUND AN: A KEY reads as a key, not as a number of them.
					if counter.ends_with(" key") and op == ">=" and wanted == "1" and not negate:
						parts.append("the %s (buy it at the Club House)" % counter)
					else:
						parts.append("%s: %s %s" % [counter, phrase, wanted])
			"is":
				parts.append(_words(rest.replace("=", " is ")))

	if parts.is_empty():
		return ""
	return "Needs " + ", ".join(parts) + "."


## `goals_with_brew_fire` -> `goals with brew fire`
static func _words(text: String) -> String:
	return text.strip_edges().replace("_", " ").replace(".", " ")


# =============================================================
#  INTERNALS
# =============================================================

static func _split(expression: String) -> Array[String]:
	var out: Array[String] = []
	# " and " is allowed as a friendlier separator than ";" for people writing
	# conditions in a spreadsheet cell.
	for piece in expression.replace(" and ", ";").split(";"):
		var term := String(piece).strip_edges()
		if term != "":
			out.append(term)
	return out


static func _test_one(term: String, state: GameState) -> bool:
	var negate := term.begins_with("!")
	var body := term.substr(1).strip_edges() if negate else term

	var colon := body.find(":")
	if colon <= 0:
		return true            # malformed; DialogueDB already complained

	var kind := body.substr(0, colon).strip_edges().to_lower()
	var rest := body.substr(colon + 1).strip_edges()
	var result := false

	match kind:
		"flag":
			result = state.has_flag(rest)
		"unlocked":
			result = state.is_unlocked(rest)
		"count":
			result = _test_count(rest, state)
		"is":
			var split := rest.split("=", true, 1)
			if split.size() == 2:
				result = state.text(String(split[0])).to_lower() \
					== String(split[1]).strip_edges().to_lower()
		_:
			return true        # unknown kind; do not hide the line over it

	return not result if negate else result


static func _test_count(rest: String, state: GameState) -> bool:
	var op := _comparison_in(rest)
	if op == "":
		return state.count(rest) > 0     # bare "count:gold" means "has any"

	var at := rest.find(op)
	var counter_name := rest.substr(0, at).strip_edges()
	var wanted := int(rest.substr(at + op.length()).strip_edges())
	var have := state.count(counter_name)

	match op:
		">=": return have >= wanted
		"<=": return have <= wanted
		"!=": return have != wanted
		">": return have > wanted
		"<": return have < wanted
		"=": return have == wanted
	return false


static func _apply_one(term: String, state: GameState) -> void:
	var colon := term.find(":")
	if colon <= 0:
		return

	var kind := term.substr(0, colon).strip_edges().to_lower()
	var rest := term.substr(colon + 1).strip_edges()
	if rest == "":
		return

	match kind:
		"flag":
			var parts := rest.split("=", true, 1)
			var on := true
			if parts.size() == 2:
				on = not (String(parts[1]).strip_edges().to_lower() in
					["false", "no", "0", "off"])
			state.set_flag(String(parts[0]), on)
		"count":
			_apply_count(rest, state)
		"unlock":
			state.unlock(rest)
		"set":
			var kv := rest.split("=", true, 1)
			if kv.size() == 2:
				state.set_text(String(kv[0]), String(kv[1]))
		"clear":
			state.set_text(rest, "")
		"sign":
			# ============ A PLAYER JOINS YOUR CLUB ============
			#
			# The foundation under "a new game gives you three Stars". Until
			# now a card in your CSVs was simply yours — every class's whole
			# roster was available from the first minute, so there was no such
			# thing as signing anybody and no such thing as a squad growing.
			#
			# `sign:Müller` in any Effects column marks one card as owned.
			# NOTHING READS IT unless `squad_ownership` in Tuning.csv is on,
			# so writing these rows today changes nothing and turning the row
			# on later changes everything. See squad_book.gd.
			SquadBook.sign(rest, state)
		"release":
			SquadBook.release(rest, state)
			# A RECRUIT LEAVES THE BASE ENTIRELY: his name is free again.
			RecruitBook.release(rest, state)
		"recruit":
			# A PLAIN PLAYER WITH A NAME OF HIS OWN. recruit:I0, recruit:I0=Johannes.
			# See recruit_book.gd - nothing shows until `named_recruits` is on.
			RecruitBook.recruit(rest, state, CardDatabase.get_db())


static func _apply_count(rest: String, state: GameState) -> void:
	var op := _count_operator(rest)
	if op == "":
		return
	var at := rest.find(op)
	var counter_name := rest.substr(0, at).strip_edges()
	var amount := int(rest.substr(at + 1).strip_edges())

	match op:
		"+": state.add_count(counter_name, amount)
		"-": state.add_count(counter_name, -amount)
		"=": state.set_count(counter_name, amount)


## The comparison used in a Requires term, or "" if there is none.
## Order matters: ">=" has to be found before ">".
static func _comparison_in(rest: String) -> String:
	for op in COMPARISONS:
		if rest.find(op) > 0:
			return op
	return ""


## The + - or = in an Effects count term, or "" if there is none.
static func _count_operator(rest: String) -> String:
	for op in ["+", "-", "="]:
		if rest.find(op) > 0:
			return op
	return ""
