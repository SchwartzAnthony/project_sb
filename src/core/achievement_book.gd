class_name AchievementBook
extends RefCounted

# =============================================================
#  ACHIEVEMENTS — data/Achievements.csv
#
#  ============ WHAT YOU SAID THIS IS ============
#
#  "Achievements = for new content, systems, players, resources, etc.
#   EVERYTHING NEEDS TO BE UNLOCKED HERE FIRST."
#
#  So this is the root of the game. The Talent Tree chooses among what
#  achievements have handed over; a Brewery section cannot be worked in until
#  an achievement opens it; a room in the base is not there until one says so.
#  Nothing else is allowed to be the first gate.
#
#  ============ A ROW ============
#
#      ID            yours
#      Name          what it is called on the board
#      Description   what you did to get it
#      Needs         the condition. count:goals>=10, flag:x, unlocked:y,
#                    joined with semicolons — THE SAME WORDS as everywhere
#      Unlocks       what it hands over. Semicolons for more than one
#      Reward        anything else that should happen, in the Do language:
#                    give:coins+50, flag:x, announce:Text, story:chapter2
#      Art           an icon in assets/icons/
#      Hidden        yes keeps it off the board until it is earned
#
#  ============ WHY IT IS NOT A NEW VOCABULARY ============
#
#  The game already had one way to say "you have this": `unlock:Brewery`
#  grants it, `unlocked:Brewery` tests it, and GameState remembers it. A
#  second, parallel system for achievements would mean two answers to "is the
#  Brewery open", and one day they would disagree.
#
#  So an achievement's `Unlocks` column is turned into exactly those words.
#  Everything downstream — buildings, talents, classes, Stadium layers,
#  Brewery sections — keeps testing `unlocked:` and never knows this file
#  exists. Which is the point: you can move where something is granted from
#  without touching the thing that is granted.
#
#  ============ WHEN IT IS CHECKED ============
#
#  `review()` walks every row, grants any whose Needs have just come true,
#  and returns what was earned. It is called when a screen opens and when a
#  match ends — often enough that nothing is ever left waiting, cheap enough
#  that it does not matter (a few dozen condition tests).
#
#  It is IDEMPOTENT. An achievement already earned is skipped, so calling it
#  a hundred times grants nothing twice.
# =============================================================

const FILE := "res://data/Achievements.csv"
## The flag an earned achievement sets. `flag:earned_first_win` works as a
## condition anywhere in the game, which is how one achievement can require
## another without this file inventing a way to say so.
const EARNED_PREFIX := "earned_"

static var _rows: Array[Dictionary] = []
static var _problems: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_rows = []
	_problems = []
	_loaded = false


static func rows() -> Array[Dictionary]:
	if _loaded:
		return _rows
	_loaded = true
	_rows = []
	_problems = []

	var seen: Dictionary = {}
	for row in MenuSupport.read_csv(FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		var key := id_text.to_lower()
		if seen.has(key):
			_problems.append("Two rows share the ID '%s'. An ID is how the game remembers you earned it, so they have to be different." % id_text)
			continue
		seen[key] = true

		_rows.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"description": MenuSupport.field(row, "Description").strip_edges(),
			"needs": MenuSupport.field(row, "Needs").strip_edges(),
			"unlocks": _list_of(MenuSupport.field(row, "Unlocks")),
			"reward": MenuSupport.field(row, "Reward").strip_edges(),
			"art": MenuSupport.field(row, "Art").strip_edges(),
			"hidden": MenuSupport.field(row, "Hidden").strip_edges().to_lower().begins_with("y"),
		})

		# AN ACHIEVEMENT THAT UNLOCKS NOTHING AND REWARDS NOTHING is a row
		# that does nothing at all, and it will look like it is broken rather
		# than like it was left half-written.
		var last: Dictionary = _rows[-1]
		if last["unlocks"].is_empty() and String(last["reward"]) == "":
			_problems.append("'%s' unlocks nothing and rewards nothing — it will be earned and then do nothing." % id_text)
		if String(last["needs"]) == "":
			_problems.append("'%s' has an empty Needs, so it is earned the moment the game starts." % id_text)

	if _rows.is_empty():
		print("[achievements] No Achievements.csv — nothing is gated behind one.")
	else:
		print("[achievements] %d achievement(s) from Achievements.csv." % _rows.size())
	for problem in _problems:
		print("[achievements] %s" % problem)
	return _rows


static func problems() -> Array[String]:
	rows()
	return _problems


static func _list_of(text: String) -> Array[String]:
	var out: Array[String] = []
	for part in text.split(";", false):
		var clean := String(part).strip_edges()
		if clean != "":
			out.append(clean)
	return out


# =============================================================
#  EARNING THEM
# =============================================================

## Has this one been earned?
static func earned(id_text: String, state: GameState) -> bool:
	if state == null:
		return false
	return state.has_flag(EARNED_PREFIX + id_text.to_lower())


## Walk every row, grant anything newly true, and return what was earned.
##
## Safe to call as often as you like: an achievement already earned is
## skipped, so nothing is ever granted twice.
static func review(state: GameState) -> Array[Dictionary]:
	var won: Array[Dictionary] = []
	if state == null:
		return won

	for row in rows():
		var id_text := String(row["id"])
		if earned(id_text, state):
			continue
		var needs := String(row["needs"])
		if needs == "":
			continue     # already complained about at load; never auto-grant
		if not DialogueGrammar.test(needs, state):
			continue

		# ============ REMEMBER IT FIRST ============
		#
		# Before anything is granted, so that a Reward which itself sets a
		# condition cannot make this row fire twice inside one review.
		state.set_flag(EARNED_PREFIX + id_text.to_lower(), true)

		# ---- what it hands over ----
		for thing in row["unlocks"]:
			state.unlock(String(thing))

		# ---- and anything else, in the ordinary Do language ----
		var reward := String(row["reward"])
		if reward != "":
			Progression.run_actions(reward, state)

		won.append(row)
		print("[achievements] EARNED: %s%s" % [row["name"],
			"" if row["unlocks"].is_empty() else "  ->  " + ", ".join(row["unlocks"])])

	return won


## Everything, with whether it is earned and whether it should be shown.
## What the board draws.
static func board(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in rows():
		var got := earned(String(row["id"]), state)
		if bool(row["hidden"]) and not got:
			continue
		var entry := row.duplicate(true)
		entry["earned"] = got
		out.append(entry)
	return out


static func earned_count(state: GameState) -> int:
	var many := 0
	for row in rows():
		if earned(String(row["id"]), state):
			many += 1
	return many


## EVERY NAME ANY ACHIEVEMENT CAN HAND OVER. Used by the checker to answer
## "is this thing reachable at all, or have I written a building nobody can
## ever open?" — which is the question this file makes it possible to ask.
static func everything_unlockable() -> Array[String]:
	var out: Array[String] = []
	for row in rows():
		for thing in row["unlocks"]:
			var clean := String(thing)
			if not out.has(clean):
				out.append(clean)
	return out
