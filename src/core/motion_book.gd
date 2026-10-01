class_name MotionBook
extends RefCounted

# =============================================================
#  HOW THINGS MOVE — data/Motion.csv
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "The general animation feel of the buttons, screen move and more."
#
#  So: every movement in the game, in one spreadsheet. Not because movement
#  is complicated, but because FEEL IS A NUMBER YOU CHANGE AND LOOK AT, and
#  a feel buried in fifteen scripts is a feel nobody ever tunes.
#
#  ============ THE COLUMNS ============
#
#      Moment     what is moving. `button_press`, `window_open`, `goal`
#      Seconds    how long it takes
#      Move X/Y   how far it travels, in pixels, from where it ends up
#      Scale      how big it starts. UNDER 1 grows into place, over 1
#                 shrinks into place — and those two read completely
#                 differently: growing is arriving, shrinking is being put away
#      Ease       `out` fast then settling, `in` slow then arriving,
#                 `both` for something heavy, `none` for a machine
#      Shake      pixels of screen shake. Multiplied by `juice_scale`
#
#  ============ THE RULE THAT MAKES IT READ AS ONE GAME ============
#
#  EVERY NUMBER IN HERE IS SMALL AND FAST. Two pixels, three per cent, a
#  tenth of a second. The temptation with a file like this is to make
#  everything bigger, and the result is a game that feels like it is wading.
#  A button that moves two pixels reads as pressable; a button that moves ten
#  reads as broken.
#
#  The one exception is `goal`, which is allowed to be loud, because it is the
#  thing the whole match is for.
#
#  ============ IT CANNOT BREAK ANYTHING ============
#
#  A moment with no row simply does not move — the thing appears where it was
#  always going to be. So you can delete every row in this file and the game
#  still works; it just stops feeling like anything.
# =============================================================

const FILE := "res://data/Motion.csv"

static var _rows: Dictionary = {}
static var _problems: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_rows = {}
	_problems = []
	_loaded = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = {}
	_problems = []

	for row in MenuSupport.read_csv(FILE):
		var moment := MenuSupport.field(row, "Moment").strip_edges()
		if moment == "":
			continue
		var entry := {
			"moment": moment,
			"seconds": maxf(0.0, MenuSupport.field_float(row, "Seconds", 0.12)),
			"move": Vector2(
				MenuSupport.field_float(row, "Move X", 0.0),
				MenuSupport.field_float(row, "Move Y", 0.0)),
			"scale": maxf(0.01, MenuSupport.field_float(row, "Scale", 1.0)),
			"ease": MenuSupport.field(row, "Ease", "out").strip_edges().to_lower(),
			"shake": maxf(0.0, MenuSupport.field_float(row, "Shake", 0.0)),
		}
		_rows[CardDatabase._normalise(moment)] = entry

		# A MOVEMENT THAT TAKES NO TIME IS NOT A MOVEMENT. It is worth saying
		# out loud, because a 0 in Seconds with a Move of 40 looks like a
		# setting and behaves like nothing at all.
		if entry["seconds"] <= 0.0 and (entry["move"] != Vector2.ZERO
				or not is_equal_approx(float(entry["scale"]), 1.0)):
			_problems.append("'%s' has Seconds 0 but something to move or scale, so none of it happens. Give it a tenth of a second or clear the other columns."
				% moment)
		if entry["seconds"] > 1.0:
			_problems.append("'%s' takes %.2f seconds. Anything over about half a second reads as the game being slow rather than the game being smooth."
				% [moment, float(entry["seconds"])])

	print("[motion] %d moment(s)." % _rows.size())
	for problem in _problems:
		print("[motion] %s" % problem)


static func problems() -> Array[String]:
	_load()
	return _problems


static func every() -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	for key in _rows:
		out.append(_rows[key])
	return out


## One moment, or {} when nothing is written for it — which means "do not
## move", and is a perfectly good answer.
static func of(moment: String) -> Dictionary:
	_load()
	return _rows.get(CardDatabase._normalise(moment), {})


static func _curve(which: String) -> Tween.EaseType:
	match which:
		"in": return Tween.EASE_IN
		"both": return Tween.EASE_IN_OUT
		_: return Tween.EASE_OUT


# =============================================================
#  DOING IT
# =============================================================

## PLAY A MOMENT ON A CONTROL. One line at every call site:
##
##     MotionBook.play(button, "button_press")
##
## Safe to call with a moment that does not exist, on a node that is being
## freed, or while the tree is paused — it simply does nothing, which is what
## lets it be sprinkled around without a guard at every call.
static func play(on: Control, moment: String) -> void:
	if on == null or not is_instance_valid(on) or not on.is_inside_tree():
		return
	var spec := of(moment)
	if spec.is_empty() or float(spec["seconds"]) <= 0.0:
		return

	var home: Vector2 = on.position
	var move: Vector2 = spec["move"]
	var size_now: float = float(spec["scale"])

	# PIVOT IN THE MIDDLE, or scaling pulls the thing towards its top-left
	# corner and reads as a slide rather than a swell.
	on.pivot_offset = on.size * 0.5

	on.position = home + move
	on.scale = Vector2(size_now, size_now)

	var tween := on.create_tween()
	tween.set_parallel(true)
	# PROCESS_ALWAYS so a menu that opens while the game is paused still
	# animates. A pause menu that snaps into place while everything else
	# glides is the one that looks wrong.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ease(_curve(String(spec["ease"])))
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(on, "position", home, float(spec["seconds"]))
	tween.tween_property(on, "scale", Vector2.ONE, float(spec["seconds"]))


## THE PRESS FEEL, on any button, in one call:
##
##     MotionBook.press_feel(button)
##
## Hover lifts it, press pushes it down, release springs it back. Three rows
## of Motion.csv and no code at the call site.
static func press_feel(button: BaseButton) -> void:
	if button == null:
		return
	var control := button as Control
	if control == null:
		return
	button.mouse_entered.connect(func() -> void: play(control, "button_hover"))
	button.mouse_exited.connect(func() -> void: play(control, "button_release"))
	button.button_down.connect(func() -> void: play(control, "button_press"))
	button.button_up.connect(func() -> void: play(control, "button_release"))


## How many pixels of shake a moment asks for, after `juice_scale`.
## 0 when the moment has none, so a caller can write one line.
static func shake_for(moment: String, db: CardDatabase) -> float:
	var spec := of(moment)
	if spec.is_empty():
		return 0.0
	var scale := 1.0
	if db != null:
		scale = db.tune_float("juice_scale", 1.0)
	return float(spec["shake"]) * scale
