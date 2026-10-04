class_name PlayMakerStarts
extends RefCounted

# =============================================================
#  HOW A PLAY MAKER STARTS  (round AC, your answer to Q060)
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "I agree and lets implement all of them": a throw-in, a corner or goal
#  kick, the keeper claiming it, a referee's drop-ball, and a rare storm
#  gust - in a spreadsheet.
#
#  ============ data/PlayMakerStarts.csv ============
#
#    Start     which one. One of:
#                throw_in      over the nearest touchline (what it always was)
#                corner        a defender near his own goal puts it behind
#                goal_kick     an attacker near their goal puts it over
#                keeper_claim  an attacker loses it and the keeper catches it
#                drop_ball     the referee stops play and drops the ball
#                storm_gust    the wind takes the ball somewhere else
#    Zone      where the ball has to be when play stops for this row to be
#              possible:  wide (near a touchline)  middle  any
#              (Waiting play keeps the ball in quarters 2 and 3, so it is never
#              near a goal when play stops - which is why the corner, goal
#              kick and keeper rows say `any`: they happen where the player
#              who gave it away is standing.)
#    Chance    a weight, not a percentage. Every possible row's Chance is
#              added up and one is drawn. 0 switches a row off.
#    Restart   who decides which way round the next round is played:
#                chooses   the player taking it picks ATTACK or DEFEND
#                          (the throw-in screen, as before)
#                attacks   the side restarting attacks Tier I (your Q061)
#                race      the old clash: both sides go for it, the winner
#                          attacks
#                coin      a random side restarts and attacks
#    Call      the big word across the pitch ("THROW-IN", "CORNER")
#    Caption   the line under the little animation window. {loser} is the
#              player who gave it away, {thrower} the one taking it,
#              {keeper} the keeper.
#
#  The BEATS - the order things happen in, how long each takes, the sounds -
#  are still data/OutOfBounds.csv. Its `say` row shows {call} and its
#  `window` row shows {caption}, so one beat list serves every kind of start.
# =============================================================

const FILE := "res://data/PlayMakerStarts.csv"
const KINDS: Array[String] = ["throw_in", "corner", "goal_kick", "keeper_claim", "drop_ball", "storm_gust"]
const ZONES: Array[String] = ["wide", "middle", "any"]
const RESTARTS: Array[String] = ["chooses", "attacks", "race", "coin"]

static var _rows: Array[Dictionary] = []
static var _problems: Array[String] = []
static var _loaded := false
## For test tools only: always use this Start ("" = draw as normal).
static var force_start := ""


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
	for row in MenuSupport.read_csv(FILE):
		var kind := MenuSupport.field(row, "Start").strip_edges().to_lower()
		if kind == "":
			continue
		if not KINDS.has(kind):
			_problems.append("Start '%s' is not one of: %s" % [kind, ", ".join(KINDS)])
			continue
		var zone := MenuSupport.field(row, "Zone", "any").strip_edges().to_lower()
		if not ZONES.has(zone):
			_problems.append("%s: Zone '%s' is not one of: %s - reading it as any" % [kind, zone, ", ".join(ZONES)])
			zone = "any"
		var restart := MenuSupport.field(row, "Restart", "chooses").strip_edges().to_lower()
		if not RESTARTS.has(restart):
			_problems.append("%s: Restart '%s' is not one of: %s - reading it as chooses" % [kind, restart, ", ".join(RESTARTS)])
			restart = "chooses"
		_rows.append({
			"start": kind,
			"zone": zone,
			"chance": maxf(0.0, MenuSupport.field_float(row, "Chance", 0.0)),
			"restart": restart,
			"call": MenuSupport.field(row, "Call", kind.to_upper().replace("_", " ")).strip_edges(),
			"caption": MenuSupport.field(row, "Caption", "{loser} gives it away").strip_edges(),
		})
	for problem in _problems:
		print("[starts] %s" % problem)
	return _rows


static func problems() -> Array[String]:
	rows()
	return _problems


## The one used when the file is missing or nothing fits: today's throw-in.
static func fallback() -> Dictionary:
	return {"start": "throw_in", "zone": "any", "chance": 1.0, "restart": "chooses",
		"call": "THROW-IN", "caption": "{loser} puts it out"}


## Where the ball is: "wide" within `play_maker_wide_band` of a touchline,
## else "middle".
static func zone_of(point: Vector2, play: Rect2, db: CardDatabase) -> String:
	if play.size.y <= 1.0:
		return "middle"
	var band := 0.28
	if db != null:
		band = db.tune_float("play_maker_wide_band", 0.28)
	var from_edge := minf(point.y - play.position.y, play.end.y - point.y) / play.size.y
	return "wide" if from_edge <= band else "middle"


## Draw one row for a ball in `zone`. `roll` is 0..1 (randf()).
static func pick(zone: String, roll: float) -> Dictionary:
	if force_start != "":
		for row in rows():
			if String(row["start"]) == force_start:
				return row
	var fits: Array[Dictionary] = []
	var total := 0.0
	for row in rows():
		var z := String(row["zone"])
		if z != "any" and z != zone:
			continue
		if float(row["chance"]) <= 0.0:
			continue
		fits.append(row)
		total += float(row["chance"])
	if fits.is_empty() or total <= 0.0:
		return fallback()
	var at := clampf(roll, 0.0, 0.9999) * total
	for row in fits:
		at -= float(row["chance"])
		if at < 0.0:
			return row
	return fits[fits.size() - 1]
