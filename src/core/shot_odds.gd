class_name ShotOdds
extends RefCounted

# =============================================================
#  WILL IT GO IN? — data/ShotOdds.csv
#
#  ============ WHAT WAS WRONG ============
#
#  "When the goalie is at 0 stamina, it IS a goal when shot at. The % chance
#   of scoring should be shown while the goalie has stamina; if they have 0
#   stamina it should show 100%. Each lower amount of stamina increases the %
#   of scoring a goal."
#
#  None of that was true. The old keeper had two numbers and no curve between
#  them:
#
#      stamina left    a flat 5% chance the shot sneaks in
#      stamina at 0    a 90% chance
#
#  So a keeper on 1 stamina was exactly as hard to beat as a keeper on 30 —
#  the wall did not get weaker as you knocked it down, it simply fell over at
#  the end. And an empty net still saved one shot in ten, which is the kind of
#  thing that reads as the game cheating.
#
#  Worse, none of it was ever shown. You watched a bar go down with no idea
#  what it was buying you.
#
#  ============ WHAT IT IS NOW ============
#
#  A CURVE YOU DRAW, in a spreadsheet, and the number it produces is PRINTED
#  ON THE SCREEN before the shot is taken.
#
#      Stamina Left    how much of the keeper's stamina is left, 0 to 100
#      Chance          the % chance of scoring at that stamina, before power
#      Per Power       how many points each point of shot power adds, there
#
#  Between two rows both numbers are interpolated, so six rows describe a
#  smooth curve rather than six steps. Out of the box:
#
#      keeper on 100%   a power-5 shot is  18%
#      keeper on  50%   a power-5 shot is  50%
#      keeper on  25%   a power-5 shot is  77%
#      keeper on   0%   ANY shot is       100%
#
#  ============ THE NUMBER YOU ARE SHOWN IS THE NUMBER THAT IS ROLLED ============
#
#  This is the part that matters and it is worth being explicit about. The
#  shot is rolled against the stamina the keeper had WHEN YOU WERE SHOWN THE
#  NUMBER, and the stamina is taken off afterwards. A shot that empties a
#  keeper does not get the empty keeper's odds — the NEXT one does.
#
#  Doing it the other way round is a lie: the cut-away would say 52% and the
#  game would roll something else, and no player would ever be able to tell.
# =============================================================

const FILE := "res://data/ShotOdds.csv"

## Used when the spreadsheet is missing entirely, so a deleted file cannot
## leave every shot at a 0% chance and the match unwinnable.
const FALLBACK: Array[Dictionary] = [
	{"left": 0.0, "chance": 100.0, "per_power": 0.0},
	{"left": 100.0, "chance": 8.0, "per_power": 2.0},
]

static var _rows: Array[Dictionary] = []
static var _loaded := false
static var _problems: Array[String] = []


static func forget() -> void:
	_rows = []
	_problems = []
	_loaded = false


## Every row, sorted by Stamina Left, lowest first. Sorted here rather than
## trusted from the file, so the order you type them in does not matter.
static func rows() -> Array[Dictionary]:
	if _loaded:
		return _rows
	_loaded = true
	_rows = []
	_problems = []

	for row in MenuSupport.read_csv(FILE):
		var text := MenuSupport.field(row, "Stamina Left").strip_edges()
		if text == "":
			continue
		_rows.append({
			"left": clampf(MenuSupport.field_float(row, "Stamina Left", 0.0), 0.0, 100.0),
			"chance": clampf(MenuSupport.field_float(row, "Chance", 0.0), 0.0, 100.0),
			"per_power": maxf(0.0, MenuSupport.field_float(row, "Per Power", 0.0)),
			"notes": MenuSupport.field(row, "Notes"),
		})

	if _rows.is_empty():
		_problems.append("No ShotOdds.csv rows — falling back to 8%% on a fresh keeper and 100%% on an empty one.")
		_rows = FALLBACK.duplicate(true)
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["left"]) < float(b["left"]))

	# ============ THE ONE RULE THE FILE HAS ============
	#
	# It has to say something about an empty keeper, because that is the row
	# the whole file exists for. A file that starts at 25% leaves the game
	# guessing about the case the player will meet most often.
	if not is_zero_approx(float(_rows[0]["left"])):
		_problems.append("The lowest row is %d%% stamina, not 0. Add a row for 0 — an empty keeper is the case this file exists for."
			% int(_rows[0]["left"]))

	# And it should get EASIER as the keeper empties, or the bar means the
	# opposite of what a player will assume it means.
	for i in range(1, _rows.size()):
		if float(_rows[i]["chance"]) > float(_rows[i - 1]["chance"]):
			_problems.append("At %d%% stamina the chance (%d%%) is HIGHER than at %d%% (%d%%). A fuller keeper should be harder to beat, not easier."
				% [int(_rows[i]["left"]), int(_rows[i]["chance"]),
					int(_rows[i - 1]["left"]), int(_rows[i - 1]["chance"])])
	return _rows


static func problems() -> Array[String]:
	rows()
	return _problems


## THE ANSWER, as a percentage from 0 to 100.
##
## `stamina` and `max_stamina` are the keeper's; `power` is the shot's.
static func chance(stamina: int, max_stamina: int, power: int) -> float:
	var table := rows()
	var left := 0.0
	if max_stamina > 0:
		left = clampf(100.0 * float(stamina) / float(max_stamina), 0.0, 100.0)

	var base := 0.0
	var per := 0.0

	if left <= float(table[0]["left"]):
		base = float(table[0]["chance"])
		per = float(table[0]["per_power"])
	elif left >= float(table[-1]["left"]):
		base = float(table[-1]["chance"])
		per = float(table[-1]["per_power"])
	else:
		# BETWEEN TWO ROWS, so six rows draw a curve rather than six steps.
		for i in range(1, table.size()):
			var high: Dictionary = table[i]
			if left > float(high["left"]):
				continue
			var low: Dictionary = table[i - 1]
			var span := float(high["left"]) - float(low["left"])
			var how_far := 0.0 if is_zero_approx(span) else (left - float(low["left"])) / span
			base = lerpf(float(low["chance"]), float(high["chance"]), how_far)
			per = lerpf(float(low["per_power"]), float(high["per_power"]), how_far)
			break

	return clampf(base + per * float(maxi(0, power)), 0.0, 100.0)


## The same thing as a 0-to-1 roll threshold, which is what take_shot() wants.
static func odds(stamina: int, max_stamina: int, power: int) -> float:
	return chance(stamina, max_stamina, power) / 100.0


## "18%" — one place that decides how the number is written, so the cut-away,
## the pitch and the tools all say it the same way.
static func as_text(stamina: int, max_stamina: int, power: int) -> String:
	return "%d%%" % int(round(chance(stamina, max_stamina, power)))


## "8 – 18%", the band shown beside a keeper on the pitch, where the shot
## power is not known yet. The low end is a shot of no power at all and the
## high end is `shot_power_shown` from Tuning.csv.
##
## It collapses to one number when the two ends agree, which is exactly what
## happens at 0 stamina — so an empty keeper reads a flat, unambiguous 100%.
static func band_text(stamina: int, max_stamina: int, top_power: int) -> String:
	var low := int(round(chance(stamina, max_stamina, 0)))
	var high := int(round(chance(stamina, max_stamina, top_power)))
	if low >= high:
		return "%d%%" % low
	return "%d – %d%%" % [low, high]


## Cool when the keeper is winning, hot when he is losing. The same two
## colours the rest of the game uses for defend and attack, because that is
## exactly what a low and a high number mean here.
static func colour_for(percent: float) -> Color:
	return MenuSupport.COLOUR_DEFEND.lerp(
		MenuSupport.COLOUR_ATTACK, clampf(percent / 100.0, 0.0, 1.0))
