class_name Referee
extends RefCounted

# =============================================================
#  THE MAN WITH THE WHISTLE — data/Referee.csv
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "A % of causing fouls and getting yellow cards. A bar with 1-5 sections
#   that fill up. Once the yellow is committed, the % is high to be caught
#   when causing a foul. So when a foul happens and the bar isn't full, the
#   ref won't say anything."
#
#  ============ A FOUL IS NOW TWO QUESTIONS ============
#
#      1. DID A FOUL HAPPEN?     Fouls.csv, exactly as before. The more a
#                                side set off in a round, the likelier it is
#                                to have given one away doing it.
#
#      2. DID HE SEE IT?         THIS FILE. And if he did not, nothing
#                                happens at all — no card, no free kick, no
#                                whistle. You got away with it.
#
#  That second question is the whole feature, and it is worth saying why it
#  is good: a foul system where every foul is called is a tax. A foul system
#  where fouls go unseen UNTIL HIS PATIENCE RUNS OUT is a decision — because
#  you can see the bar filling, and you can choose to keep playing that way
#  or to stop.
#
#  ============ THE BAR ============
#
#      every trigger you set off      +Fill Per Trigger
#      every foul he does NOT see     +Fill Per Foul       (much bigger)
#
#  He has `Segments` of them — five out of the box, four for the strict one.
#  While the bar is filling, the chance he notices a foul is
#  `Caught Per Segment` for each segment already lit. When it is FULL it is
#  `Caught When Full`, which is 95 or 100 — so a full bar means the next foul
#  is a card, near enough every time.
#
#  AND ONCE YOU HAVE BEEN BOOKED HE IS WATCHING YOU: `Caught After Yellow`
#  replaces all of that, and it is high whatever the bar says. That is your
#  "once the yellow is committed, the % is high".
#
#  ============ RED COMES FROM YELLOWS ============
#
#  `Red Per Yellow` is added to the red share for every booking that side
#  already has. So a first card is almost never red and a third foul after
#  two bookings very often is — on top of the ordinary two-yellows-is-red
#  rule, which is still `foul_two_yellows_is_red` in Tuning.csv.
#
#  ============ WHY IT IS A SPREADSHEET AND NOT A NUMBER ============
#
#  Because "how strict is the referee" is a thing you will want to change per
#  competition, and the day you do, a friendly and a cup final want different
#  men. Three rows ship: the fallback, a lenient one for early seasons and a
#  strict one for a final. `referee_id` in Tuning.csv picks, and a Season.csv
#  row may override it.
#
#  ============ THE SWITCH THAT PUTS IT ALL BACK ============
#
#  `referee` FALSE and none of this runs: every foul is called the moment it
#  happens, exactly as before. That is how this went in without changing a
#  match you could already play.
# =============================================================

const FILE := "res://data/Referee.csv"

## Where his attention lives in the match. NOT in the save: a referee's
## patience is a thing about one afternoon, and carrying it into next week
## would be a bug nobody could ever trace.
static var _heat := {false: 0.0, true: 0.0}

static var _rows: Dictionary = {}
static var _problems: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_rows = {}
	_problems = []
	_loaded = false
	clear_heat()


static func clear_heat() -> void:
	_heat = {false: 0.0, true: 0.0}


static func _key(text: String) -> String:
	return CardDatabase._normalise(text)


# =============================================================
#  READING THE FILE
# =============================================================

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = {}
	_problems = []

	for row in MenuSupport.read_csv(FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		var entry := {
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"portrait": MenuSupport.field(row, "Portrait").strip_edges(),
			"segments": clampi(MenuSupport.field_int(row, "Segments", 5), 1, 10),
			"per_trigger": MenuSupport.field_float(row, "Fill Per Trigger", 0.25),
			"per_foul": MenuSupport.field_float(row, "Fill Per Foul", 0.6),
			"when_full": MenuSupport.field_float(row, "Caught When Full", 95.0),
			"per_segment": MenuSupport.field_float(row, "Caught Per Segment", 9.0),
			"after_yellow": MenuSupport.field_float(row, "Caught After Yellow", 80.0),
			"red_per_yellow": MenuSupport.field_float(row, "Red Per Yellow", 6.0),
			"empties_on": MenuSupport.field(row, "Empties On", "card").strip_edges().to_lower(),
			"says_nothing": MenuSupport.field(row, "Says Nothing").strip_edges(),
			"says_free": MenuSupport.field(row, "Says Free Kick").strip_edges(),
			"says_yellow": MenuSupport.field(row, "Says Yellow").strip_edges(),
			"says_red": MenuSupport.field(row, "Says Red").strip_edges(),
		}
		_rows[_key(id_text)] = entry

		# ---- the things a spreadsheet cannot check about itself ----
		if float(entry["when_full"]) < float(entry["per_segment"]) * float(entry["segments"]):
			_problems.append("'%s': a full bar is %.0f%% to be caught but the segments already add up to %.0f%%. The bar filling would make him LESS likely to notice, which is backwards."
				% [id_text, float(entry["when_full"]),
				   float(entry["per_segment"]) * float(entry["segments"])])
		if float(entry["per_trigger"]) <= 0.0 and float(entry["per_foul"]) <= 0.0:
			_problems.append("'%s' has nothing that fills his bar, so it never fills and he never books anybody."
				% id_text)

	if not _rows.has(_key("*")):
		_problems.append("Referee.csv has no `*` row. That is the fallback every competition without a referee of its own uses, so most matches would have nobody with a whistle.")

	print("[referee] %d referee(s)." % _rows.size())
	for problem in _problems:
		print("[referee] %s" % problem)


static func problems() -> Array[String]:
	_load()
	return _problems


static func every() -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	for key in _rows:
		out.append(_rows[key])
	return out


## The referee on the pitch, falling back to `*`. Never empty.
static func on_duty(db: CardDatabase) -> Dictionary:
	_load()
	var wanted := "*"
	if db != null:
		wanted = db.tune_text("referee_id", "*")
	var mine: Dictionary = _rows.get(_key(wanted), {})
	if not mine.is_empty():
		return mine
	var any: Dictionary = _rows.get(_key("*"), {})
	if not any.is_empty():
		return any
	return {"id": "*", "name": "The referee", "portrait": "", "segments": 5,
		"per_trigger": 0.25, "per_foul": 0.6, "when_full": 95.0, "per_segment": 9.0,
		"after_yellow": 80.0, "red_per_yellow": 6.0, "empties_on": "card",
		"says_nothing": "", "says_free": "", "says_yellow": "", "says_red": ""}


static func on(db: CardDatabase) -> bool:
	return db == null or db.tune_bool("referee", true)


# =============================================================
#  HIS ATTENTION
# =============================================================

## How full his bar is for that side, 0.0 to 1.0.
static func heat(side_is_enemy: bool, db: CardDatabase) -> float:
	var many := float(on_duty(db)["segments"])
	if many <= 0.0:
		return 0.0
	return clampf(float(_heat[side_is_enemy]) / many, 0.0, 1.0)


## How many segments are lit, and how many there are.
static func segments(side_is_enemy: bool, db: CardDatabase) -> Dictionary:
	var ref := on_duty(db)
	var many := int(ref["segments"])
	return {
		"lit": clampi(int(floor(float(_heat[side_is_enemy]))), 0, many),
		"of": many,
		"full": float(_heat[side_is_enemy]) >= float(many),
	}


static func is_full(side_is_enemy: bool, db: CardDatabase) -> bool:
	return bool(segments(side_is_enemy, db)["full"])


## A round has been played. Triggers raise his eyebrows.
static func watch_round(side_is_enemy: bool, triggers: int, db: CardDatabase) -> void:
	if not on(db):
		return
	var ref := on_duty(db)
	_heat[side_is_enemy] = minf(
		float(_heat[side_is_enemy]) + float(ref["per_trigger"]) * float(maxi(0, triggers)),
		float(ref["segments"]))


## DID HE SEE IT? The question the whole file exists to answer.
##
## `yellows` is how many bookings that side already has.
static func notices(side_is_enemy: bool, yellows: int, db: CardDatabase) -> bool:
	if not on(db):
		return true           # no referee system: everything is called
	var ref := on_duty(db)
	var chance := 0.0
	if yellows > 0:
		# HE IS WATCHING YOU. This replaces the bar entirely — being booked
		# once is worse for you than any amount of needle, which is what
		# "once the yellow is committed, the % is high" means.
		chance = float(ref["after_yellow"])
	elif is_full(side_is_enemy, db):
		chance = float(ref["when_full"])
	else:
		chance = float(ref["per_segment"]) * float(segments(side_is_enemy, db)["lit"])
	return randf() * 100.0 < chance


## A foul he did NOT see. It still fills the bar — and by a lot, because
## getting away with one is exactly when he starts paying attention.
static func got_away_with_it(side_is_enemy: bool, db: CardDatabase) -> void:
	if not on(db):
		return
	var ref := on_duty(db)
	_heat[side_is_enemy] = minf(
		float(_heat[side_is_enemy]) + float(ref["per_foul"]),
		float(ref["segments"]))


## He blew the whistle. Everything is forgiven — that is what `Empties On`
## means, and `card` is the out-of-the-box answer: a booking resets him.
static func whistled(side_is_enemy: bool, db: CardDatabase) -> void:
	if not on(db):
		return
	if String(on_duty(db)["empties_on"]) == "never":
		return
	_heat[side_is_enemy] = 0.0


## RED IS BUILT FROM YELLOWS — and this is the EXTRA only.
##
## ============ A BUG WORTH LEAVING THE STORY OF ============
##
## This used to return `base_red + per_yellow * yellows`, and the match then
## rolled it against a card that Fouls.csv had ALREADY decided. So every
## yellow got a second roll at becoming a red using the base share again, and
## `tools/referee_check.gd` printed 297 yellows against 204 reds — two reds
## for every three bookings, which is not football, it is a riot.
##
## Fouls.csv decides the base split and this adds the bump for bookings that
## side already has. With no yellows it adds NOTHING, which is exactly what
## "red is based on the amount of yellow that have actually been committed"
## means.
static func red_bonus(yellows: int, db: CardDatabase) -> float:
	if not on(db):
		return 0.0
	return clampf(float(on_duty(db)["red_per_yellow"]) * float(maxi(0, yellows)), 0.0, 100.0)


# =============================================================
#  WHAT HE SAYS
# =============================================================

## His line for a verdict — "", "free kick", "yellow" or "red".
static func says(verdict: String, db: CardDatabase) -> String:
	var ref := on_duty(db)
	match verdict:
		"yellow": return String(ref["says_yellow"])
		"red": return String(ref["says_red"])
		"free kick": return String(ref["says_free"])
		_: return String(ref["says_nothing"])


## In words, for the checker and for a screen: what he would do right now.
static func reading(side_is_enemy: bool, yellows: int, db: CardDatabase) -> String:
	var bits := segments(side_is_enemy, db)
	if yellows > 0:
		return "booked already — %.0f%% to be caught" % float(on_duty(db)["after_yellow"])
	if bool(bits["full"]):
		return "bar FULL — %.0f%% to be caught" % float(on_duty(db)["when_full"])
	return "%d of %d — %.0f%% to be caught" % [
		int(bits["lit"]), int(bits["of"]),
		float(on_duty(db)["per_segment"]) * float(bits["lit"])]
