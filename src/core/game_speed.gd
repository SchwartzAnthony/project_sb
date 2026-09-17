class_name GameSpeed
extends RefCounted

# =============================================================
#  GAME SPEED — one dial that speeds up everything
#
#  Like the clock buttons in SimCity. 1x, 2x, 4x, 8x, and a HOLD key for a
#  temporary blast of 20x.
#
#  HOW IT WORKS, IN ONE SENTENCE
#    It sets Engine.time_scale, which is Godot's own global clock.
#
#  That is worth understanding because it is why this file is so short and
#  why it is reliable. Everything in the game reads that clock without being
#  told to: the match minutes, every `create_timer`, every animation, the
#  camera easing, the duel cut-away's pacing. There is no list of things to
#  remember to speed up, and nothing can be accidentally left out.
#
#  It is also GLOBAL and survives changing scene, so the speed you picked
#  during a match is still the speed you have at the base. Set it back to 1x
#  before you finish, or leave it — it is remembered either way.
#
#  EVERY NUMBER COMES FROM Tuning.csv:
#    game_speed_steps   the buttons, comma separated: "1,2,4,8"
#    game_speed_turbo   how fast the HOLD key goes
#    game_speed_start   which speed a match begins at
# =============================================================

const DEFAULT_STEPS: Array[float] = [1.0, 2.0, 4.0, 8.0]
const MIN_SPEED := 0.1
const MAX_SPEED := 40.0


static func current() -> float:
	return Engine.time_scale


static func set_speed(value: float) -> void:
	var wanted := clampf(value, MIN_SPEED, MAX_SPEED)
	Engine.time_scale = wanted
	# TELL THE JUICE WHAT NORMAL IS NOW. A slow-motion dip that is running
	# when you change the speed would otherwise put the OLD speed back when
	# it finishes, and you would be left on a speed you did not choose.
	Juice.speed_changed(wanted)


## Back to normal. Worth calling before a screen where fast time is silly.
##
## This also cancels any slow-motion dip outright, which is what makes it
## safe to call when leaving a fight: the clock is straight afterwards, no
## matter what was half way through happening.
static func reset() -> void:
	Engine.time_scale = 1.0
	Juice.speed_changed(1.0)
	Juice.release()


## The buttons, read out of Tuning.csv. A bad row falls back to 1,2,4,8
## rather than leaving you with no buttons at all.
static func steps(db: CardDatabase) -> Array[float]:
	if db == null:
		return DEFAULT_STEPS.duplicate()

	var out: Array[float] = []
	for piece in db.tune_text("game_speed_steps", "1,2,4,8").split(","):
		var text := String(piece).strip_edges()
		if text.is_valid_float():
			var value := clampf(float(text), MIN_SPEED, MAX_SPEED)
			if not out.has(value):
				out.append(value)

	if out.is_empty():
		push_warning("[speed] game_speed_steps in Tuning.csv is not a list of numbers like \"1,2,4,8\". Using the default.")
		return DEFAULT_STEPS.duplicate()
	return out


static func turbo(db: CardDatabase) -> float:
	if db == null:
		return 20.0
	return clampf(db.tune_float("game_speed_turbo", 20.0), MIN_SPEED, MAX_SPEED)


## "2x", "0.5x" — short enough for a button.
static func label_for(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%dx" % int(roundf(value))
	return "%.1fx" % value


# =============================================================
#  IS FAST FORWARD UNLOCKED?
#
#  ============ WHY THIS LIVES HERE ============
#
#  There are two sets of speed buttons — the HUD strip in the corner and the
#  pause menu behind Escape — and the rule used to be written in the HUD. So
#  the corner locked 4x and the pause menu happily handed it over, which is
#  not a half-finished feature but a way of saying the lock is decoration.
#
#  A rule that two screens obey belongs in neither of them. Both ask here.
#
#      game_speed_buttons        the plain on/off
#      game_speed_buttons_needs  a Requires condition as well, so it can be
#                                earned: unlocked:Fast Forward, handed out
#                                by a talent, an achievement or a season
#      game_speed_locked_words   what a locked button says when pressed
# =============================================================

## Has the player earned the faster speeds?
static func unlocked(db: CardDatabase, state: GameState) -> bool:
	if db == null:
		return false
	if not db.tune_bool("game_speed_buttons", false):
		return false
	var need := db.tune_text("game_speed_buttons_needs", "").strip_edges()
	if need == "" or state == null:
		return true
	return DialogueGrammar.test(need, state)


## Is THIS step locked? The first step is the speed the match already runs
## at, so it is never locked — locking it would be locking the game.
static func step_locked(value: float, db: CardDatabase, state: GameState) -> bool:
	if unlocked(db, state):
		return false
	var all := steps(db)
	return not all.is_empty() and not is_equal_approx(value, all[0])


static func locked_words(db: CardDatabase) -> String:
	if db == null:
		return "Not unlocked yet."
	return db.tune_text("game_speed_locked_words",
		"Fast forward is not unlocked yet.")
