class_name Rumble
extends RefCounted

# =============================================================
#  CONTROLLER RUMBLE  (round AN)
#
#  data/Rumble.csv, one row per moment the pad shakes. When and Match are
#  the same moments Audio.csv uses (goal_scored, foul_shown card=red card
#  ...), because every one of them already passes through
#  AudioDirector.fire(), which calls play() below. So a moment that makes a
#  sound can make the pad shake with one row and no code.
#
#      Weak     the small, fast motor, 0 to 1
#      Strong   the big, slow motor, 0 to 1
#      Seconds  how long
#
#  Two rows that both fit: the strongest one wins, so a star's goal does not
#  shake twice. Settings > Controller > Vibration (and Use a controller)
#  turns it all off.
# =============================================================

const SHEET := "res://data/Rumble.csv"

## Set by GameSettings whenever the controller settings are put into effect.
static var on: bool = true

static var _rows: Array[Dictionary] = []
static var _loaded: bool = false


static func rows() -> Array[Dictionary]:
	if _loaded:
		return _rows
	_loaded = true
	_rows.clear()
	for row in MenuSupport.read_csv(SHEET):
		var when := CardDatabase._normalise(MenuSupport.field(row, "When"))
		if when == "":
			continue
		_rows.append({
			"when": when,
			"match": MenuSupport.field(row, "Match"),
			"weak": clampf(MenuSupport.field_float(row, "Weak", 0.0), 0.0, 1.0),
			"strong": clampf(MenuSupport.field_float(row, "Strong", 0.0), 0.0, 1.0),
			"seconds": maxf(0.0, MenuSupport.field_float(row, "Seconds", 0.3)),
		})
	return _rows


## The row that fits this moment best, or {} for none.
static func pick(event: String, facts: Dictionary) -> Dictionary:
	var wanted := CardDatabase._normalise(event)
	var best: Dictionary = {}
	for row in rows():
		if String(row["when"]) != wanted:
			continue
		if not StatsRules._passes(String(row["match"]), facts):
			continue
		if best.is_empty() or float(row["weak"]) + float(row["strong"]) \
				> float(best["weak"]) + float(best["strong"]):
			best = row
	return best


static func play(event: String, facts: Dictionary = {}) -> void:
	if not on:
		return
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return
	var row := pick(event, facts)
	if row.is_empty() or float(row["seconds"]) <= 0.0:
		return
	for pad in pads:
		Input.start_joy_vibration(pad, float(row["weak"]), float(row["strong"]),
			float(row["seconds"]))
