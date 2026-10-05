class_name FreeKicks
extends RefCounted

# =============================================================
#  FREE KICKS AS A SET PIECE  (round AG, phase P2 - your Q033 / Q075)
#
#  ============ WHAT CHANGED ============
#
#  Before: every foul the referee saw was +3 on the fouled side's shot,
#  wherever it happened - and wasted if that side was not the one shooting.
#
#  Now: the foul happens WHERE THE CULPRIT IS STANDING. How far that spot is
#  from the goal the fouled side attacks picks a row of data/FreeKicks.csv,
#  and that row says what the free kick is worth.
#
#  ============ data/FreeKicks.csv ============
#
#    Range       a name for the row (close, edge, far - any word you like)
#    Up To       how far from the goal, as a share of the pitch's length:
#                0.30 = within the 30% of the pitch nearest that goal.
#                Rows are read from the smallest Up To; the first one the
#                spot fits is used. The last row should say 1.00.
#    Shot Power  added to the fouled side's shot this round
#    Takes Ball  yes = the fouled side takes the ball and SHOOTS this round
#                (the set piece); no = they only get the Shot Power if they
#                were shooting anyway
#    Call        the big word in the window ("DIRECT FREE KICK")
#    Caption     the line under it. {metres} = metres from goal (the pitch
#                counts as 105 m), {taker} = who takes it
#
#  ============ WHO TAKES IT ============
#
#  When it is YOUR free kick and the ball is yours, a window asks which of
#  this round's four takes it - the taker is the shooter, so his on-shot
#  abilities fire. AUTO (or "auto ask freekick") and the enemy pick the
#  strongest attacker. Cards still work as before: a yellow or red always
#  gives the fouled side the ball (`foul_card_gives_possession`).
#
#  `free_kicks` in Tuning.csv: 0 = the old flat bonus
#  (`foul_free_kick_power`), everywhere.
# =============================================================

const FILE := "res://data/FreeKicks.csv"
const PITCH_METRES := 105.0

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
	for row in MenuSupport.read_csv(FILE):
		var range_name := MenuSupport.field(row, "Range").strip_edges()
		if range_name == "":
			continue
		var up_to := MenuSupport.field_float(row, "Up To", -1.0)
		if up_to <= 0.0 or up_to > 1.0:
			_problems.append("%s: Up To must be a share of the pitch, above 0 and at most 1.00 - skipping the row" % range_name)
			continue
		var takes := MenuSupport.field(row, "Takes Ball", "no").strip_edges().to_lower()
		if not ["yes", "no"].has(takes):
			_problems.append("%s: Takes Ball '%s' is not yes or no - reading it as no" % [range_name, takes])
			takes = "no"
		_rows.append({
			"range": range_name,
			"up_to": up_to,
			"power": int(MenuSupport.field_float(row, "Shot Power", 0.0)),
			"takes_ball": takes == "yes",
			"call": MenuSupport.field(row, "Call", "FREE KICK").strip_edges(),
			"caption": MenuSupport.field(row, "Caption", "{metres} m out - {taker} takes it").strip_edges(),
		})
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["up_to"]) < float(b["up_to"]))
	if not _rows.is_empty() and float(_rows[_rows.size() - 1]["up_to"]) < 1.0:
		_problems.append("the last row's Up To is %.2f - a foul further out than that uses the last row" % float(_rows[_rows.size() - 1]["up_to"]))
	for problem in _problems:
		print("[free kicks] %s" % problem)
	return _rows


static func problems() -> Array[String]:
	rows()
	return _problems


## The row for a foul `share` of the pitch's length away from the goal
## (0 = on the goal line, 1 = the other end). Empty when the file is empty.
static func pick(share: float) -> Dictionary:
	var all := rows()
	if all.is_empty():
		return {}
	for row in all:
		if share <= float(row["up_to"]):
			return row
	return all[all.size() - 1]


## How far `spot` is from the goal line at `goal_x`, as a share of the pitch.
static func share_of(spot: Vector2, goal_x: float, play: Rect2) -> float:
	if play.size.x <= 1.0:
		return 0.5
	return clampf(absf(spot.x - goal_x) / play.size.x, 0.0, 1.0)


static func caption(row: Dictionary, share: float, taker: String) -> String:
	return String(row.get("caption", "")) \
		.replace("{metres}", str(int(round(share * PITCH_METRES)))) \
		.replace("{taker}", taker)
