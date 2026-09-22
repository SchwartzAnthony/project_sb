class_name CelebrationBook
extends RefCounted

# =============================================================
#  THE GOAL CELEBRATION — data/Celebration.csv
#
#  ============ THE QUESTION THIS ANSWERS ============
#
#  "Have the player who shot the goal slide on the ground and their teammates
#  surround them. Then show a window open for an animation when a goal is
#  shot, so that I can show a celebration of the player who shot the goal.
#  Need celebration confetti flying and cheering sounds of the crowd. ALLOW ME
#  TO DICTATE WHAT IS IN THE ANIMATION AND FOR HOW LONG. Then it goes back to
#  being with the goalie, as before."
#
#  The last sentence in capitals is why this is a spreadsheet and not a
#  function. Nothing about a goal celebration is a rule — it is a sequence of
#  moments, and which moments and how long each one lasts is a thing you will
#  change fifty times. So the code knows how to DO seven things and the
#  spreadsheet decides which of them happen, in what order, and for how long.
#
#  ============ ONE ROW IS ONE BEAT ============
#
#  The rows run TOP TO BOTTOM, in the order you wrote them. Move a row up and
#  it happens earlier. Delete every row and a goal is exactly what it was
#  before this existed: the word GOAL and a restart.
#
#      Step        yours. A name so you can find the row again
#      Who         you / them / both — whose goal this beat plays for
#      Do          what happens. The seven are listed below
#      Seconds     HOW LONG BEFORE THE NEXT ROW STARTS
#      Text        the words, for `say` and `window`
#      Art         an image file, for `window`
#      Animation   a row of Animations.csv, for `window`
#      Sound       a row of Audio.csv (or a file in assets/audio/)
#      Notes       yours
#
#  ============ THE SEVEN THINGS IT CAN DO ============
#
#      slide      the scorer drops and skids along the grass, away from the
#                 goal he has just scored in
#      swarm      everyone on his side runs in and rings him
#      confetti   starts the confetti. It keeps falling until the whole
#                 celebration ends, whatever comes after this row
#      window     opens the celebration window and puts Text / Art /
#                 Animation in it. SEVERAL window rows in a row swap what is
#                 inside without closing it, so it is a slideshow
#      say        the big word across the middle of the pitch
#      sound      plays a cue. Usually with Seconds 0
#      wait       nothing but time
#
#  ============ SECONDS IS A WAIT, NOT A LENGTH ============
#
#  This is the one thing worth reading twice. `Seconds` is how long the game
#  waits BEFORE RUNNING THE NEXT ROW — it is not how long the effect lasts.
#
#  So `confetti` with Seconds 0 starts the confetti and immediately moves on,
#  and the confetti carries on falling under everything that follows. A sound
#  with Seconds 0 starts playing and the list carries on over the top of it.
#  A `wait` row is the only one whose whole job is the number.
#
#  The one exception is `window`, which is a picture you are meant to look at:
#  it holds for its Seconds and then either swaps (if the next row is another
#  window) or closes.
#
#  ============ WORDS YOU CAN PUT IN Text ============
#
#      {scorer}   the name on the card that scored
#      {team}     the club that scored
#      {class}    that card's class
#      {tier}     the tier it was drafted at
#      {score}    "2 - 1", always your goals first
#
#  ============ THE NUMBERS THAT ARE NOT PER-BEAT ============
#
#  How far the slide goes, how wide the ring is, how much confetti there is:
#  those are shape rather than sequence, so they are rows of Tuning.csv.
#
#      goal_celebration              false turns the whole thing off
#      celebration_slide_distance    how far the skid carries him
#      celebration_swarm_radius      how close the ring stands
#      celebration_confetti_pieces   how many bits of paper
#      celebration_confetti_speed    how fast they fall
#      celebration_skippable         click or space to cut it short
# =============================================================

const FILE := "res://data/Celebration.csv"

## Everything `Do` is allowed to say. A row naming anything else is skipped
## and named once at load, which is how a typo becomes findable instead of
## becoming silence.
const ACTIONS: Array[String] = [
	"slide", "swarm", "confetti", "window", "say", "sound", "wait",
]

static var _steps: Array[Dictionary] = []
static var _loaded := false
static var _problems: Array[String] = []


static func forget() -> void:
	_steps = []
	_problems = []
	_loaded = false


## Every beat, in the order written.
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
			"who": _who_of(MenuSupport.field(row, "Who")),
			"do": action,
			"seconds": maxf(0.0, MenuSupport.field_float(row, "Seconds", 0.0)),
			"text": MenuSupport.field(row, "Text").strip_edges(),
			"art": MenuSupport.field(row, "Art").strip_edges(),
			"animation": MenuSupport.field(row, "Animation").strip_edges(),
			"sound": MenuSupport.field(row, "Sound").strip_edges(),
		})

	if _steps.is_empty():
		print("[celebration] No Celebration.csv steps — a goal is the word and the restart, as before.")
	else:
		print("[celebration] %d step(s) from Celebration.csv (%.1fs for your goals, %.1fs for theirs)."
			% [_steps.size(), total_seconds(true), total_seconds(false)])
	for problem in _problems:
		print("[celebration] %s" % problem)
	return _steps


## `you`, `them` or `both`. Anything blank or unrecognised means both, because
## a beat you forgot to label should happen rather than vanish.
static func _who_of(text: String) -> String:
	var word := text.strip_edges().to_lower()
	if word.begins_with("you") or word == "player" or word == "mine":
		return "you"
	if word.begins_with("them") or word == "they" or word == "enemy" or word == "their":
		return "them"
	return "both"


## The beats that play for one side's goal.
static func steps_for(scored_by_player: bool) -> Array[Dictionary]:
	var wanted := "you" if scored_by_player else "them"
	var out: Array[Dictionary] = []
	for step in steps():
		if String(step["who"]) == "both" or String(step["who"]) == wanted:
			out.append(step)
	return out


## How long one side's celebration takes, start to finish. Used by the
## checker so you can see the length without watching it, and worth a glance
## whenever a match starts feeling slow.
static func total_seconds(scored_by_player: bool) -> float:
	var sum := 0.0
	for step in steps_for(scored_by_player):
		sum += float(step["seconds"])
	return sum


static func problems() -> Array[String]:
	steps()
	return _problems


## Fill in {scorer}, {team} and the rest. A word nobody has a value for is
## left exactly as written rather than becoming an empty gap, so a mistyped
## placeholder shows up on screen instead of silently disappearing.
static func fill(text: String, facts: Dictionary) -> String:
	var out := text
	for key in facts:
		out = out.replace("{%s}" % key, String(facts[key]))
	return out
