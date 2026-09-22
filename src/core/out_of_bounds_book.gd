class_name OutOfBoundsBook
extends RefCounted

# =============================================================
#  HOW A ROUND BEGINS — data/OutOfBounds.csv
#
#  ============ WHAT IT REPLACES ============
#
#  "Remove the 1-10 system and use an out of bounds system: a hidden roll
#   decides who gives the ball away, that player kicks it out with an
#   animation window, the closest player from the other side walks to where
#   it went out and stands outside the line, THEN the PLAY MAKER starts and
#   both sides pick their tiers, whoever throws in chooses attack or defend,
#   and the throw goes to a team-mate who starts the relay."
#
#  A round used to begin by asking you to call a number between one and ten.
#  It worked, and it was a fairground game bolted onto a football match: you
#  were guessing a coin, not playing football. The new opening is a thing
#  that happens IN a match — somebody puts the ball out, the other side
#  throws it back in, and the side with the ball chooses what to do with it.
#
#  ============ IT IS THE SAME SHAPE AS Celebration.csv ============
#
#  On purpose. You have already learned this file:
#
#      one row is one beat, read top to bottom
#      `Seconds` is HOW LONG BEFORE THE NEXT ROW STARTS
#      delete every row and the round opens instantly, as it always could
#
#  ============ THE SIX THINGS IT CAN DO ============
#
#      roll       decides, out of sight, who gave the ball away
#      kick_out   he strikes it over the nearest touchline
#      walk_up    the nearest opponent walks to the spot and stands outside
#      window     the animation window: a caption and a picture
#      say        the big word across the middle of the pitch
#      sound      plays a cue. Usually with Seconds 0
#      wait       nothing but time
#
#  `roll` has to happen before `kick_out` and `walk_up`, because they are
#  about the player it picks. Put it anywhere and the game will run it first
#  anyway rather than kicking a ball nobody gave away — but write it first,
#  because a list that reads in the wrong order is a list that will be edited
#  in the wrong order.
#
#  ============ WORDS YOU CAN PUT IN Text ============
#
#      {loser}    the player who put it out
#      {thrower}  the player taking the throw
#      {side}     "you" or "them" — whose throw it is
#      {tier}     the tier the thrower was drafted at
# =============================================================

const FILE := "res://data/OutOfBounds.csv"

const ACTIONS: Array[String] = [
	"roll", "kick_out", "walk_up", "window", "say", "sound", "wait",
]

static var _steps: Array[Dictionary] = []
static var _problems: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_steps = []
	_problems = []
	_loaded = false


static func steps() -> Array[Dictionary]:
	if _loaded:
		return _steps
	_loaded = true
	_steps = []
	_problems = []

	for row in MenuSupport.read_csv(FILE):
		var action := MenuSupport.field(row, "Do").strip_edges().to_lower()
		if action == "":
			continue
		if not ACTIONS.has(action):
			_problems.append("Step '%s' says Do = '%s', which is not one of: %s"
				% [MenuSupport.field(row, "Step"), action, ", ".join(ACTIONS)])
			continue
		_steps.append({
			"step": MenuSupport.field(row, "Step").strip_edges(),
			"do": action,
			"seconds": maxf(0.0, MenuSupport.field_float(row, "Seconds", 0.0)),
			"text": MenuSupport.field(row, "Text").strip_edges(),
			"art": MenuSupport.field(row, "Art").strip_edges(),
			"animation": MenuSupport.field(row, "Animation").strip_edges(),
			"sound": MenuSupport.field(row, "Sound").strip_edges(),
		})

	# ============ THE ONE ORDERING RULE ============
	#
	# `kick_out` and `walk_up` are both about the player `roll` picks. Without
	# a roll first there is nobody to kick it out, so the match does the roll
	# itself — but the file should say so, because a reader who cannot see
	# where the decision happens will put the next beat in the wrong place.
	var rolled := -1
	for i in _steps.size():
		if String(_steps[i]["do"]) == "roll":
			rolled = i
			break
	if rolled < 0 and not _steps.is_empty():
		_problems.append("No `roll` row. The game will still decide who gave it away, but write the row — a list with an invisible step in it is a list that gets edited wrongly.")
	else:
		for i in _steps.size():
			var kind := String(_steps[i]["do"])
			if (kind == "kick_out" or kind == "walk_up") and i < rolled:
				_problems.append("'%s' (%s) happens before the `roll` that decides who it is about."
					% [_steps[i]["step"], kind])

	if _steps.is_empty():
		print("[out] No OutOfBounds.csv steps — a round opens straight into the picks.")
	else:
		print("[out] %d step(s) from OutOfBounds.csv, %.1fs before the picks."
			% [_steps.size(), total_seconds()])
	for problem in _problems:
		print("[out] %s" % problem)
	return _steps


static func problems() -> Array[String]:
	steps()
	return _problems


## How long the whole opening takes. Worth a glance: this happens NINE TIMES
## a match, so a second here is nine seconds of match.
static func total_seconds() -> float:
	var sum := 0.0
	for step in steps():
		sum += float(step["seconds"])
	return sum


static func fill(text: String, facts: Dictionary) -> String:
	var out := text
	for key in facts:
		out = out.replace("{%s}" % key, String(facts[key]))
	return out
