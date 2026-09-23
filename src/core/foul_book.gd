class_name FoulBook
extends RefCounted

# =============================================================
#  FOULS AND CARDS — data/Fouls.csv
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "If a team has triggered a certain number of triggers (such as combos)
#   during the combat, after the combat their % of increase of creating a
#   foul is established. Then the normal soccer foul system is in place, and
#   if the player gets a red card, they are removed and the team only has 9
#   players left."
#
#  So the more a side MADE HAPPEN in a round, the more likely it is to have
#  given away a foul doing it. That is a lovely rule, because it prices the
#  thing the game otherwise rewards without limit: firing everything you have
#  every round now carries a cost, and the cost is a man.
#
#  ============ THE CURVE ============
#
#      Triggers      how many abilities and combos that side set off
#      Foul Chance   the % chance it conceded a foul, at that many
#      Yellow        if a foul was given, the % that it is a booking
#      Red           and the % that it is a straight red
#
#  Whatever is left of 100 after Yellow and Red is a free kick and nothing
#  else — which is most fouls, as it should be.
#
#  Rows are interpolated, exactly like ShotOdds.csv, so five rows draw a
#  smooth curve rather than five steps.
#
#  ============ TWO YELLOWS ARE A RED ============
#
#  The ordinary rule, and it is `foul_two_yellows_is_red` in Tuning.csv
#  rather than a line of code, because it is a rule about football and not a
#  rule about this program.
#
#  ============ AND THEN THE LADDER HAS A HOLE IN IT ============
#
#  This is the part worth reading. Sending a man off breaks THE ONE RULE the
#  game has: a tier holds one card of each power. Tier III is a 2, a 3 and a
#  4; send the 3 off and the tier can only offer two cards.
#
#  Your answer, and it is a good one:
#
#      "Tier III P:3 has gotten a red card. So now there are Tier III P:2 and
#       P:4 left. Either P:2 or P:4 at random will be chosen a replacement,
#       keeping their Tier III and P:x name but getting the P:3 and having
#       all abilities removed."
#
#  So the hole is filled by a COPY of a survivor: the same name, the missing
#  power, and no abilities at all. The ladder is never broken, the tier still
#  offers three cards, and the replacement is visibly the weaker option —
#  a man playing out of position, which is exactly what it is.
#
#  See `stand_in_for()` below and `_fill_the_gap()` in main_scene.gd.
# =============================================================

const FILE := "res://data/Fouls.csv"

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
		var text := MenuSupport.field(row, "Triggers").strip_edges()
		if text == "":
			continue
		_rows.append({
			"triggers": maxf(0.0, MenuSupport.field_float(row, "Triggers", 0.0)),
			"chance": clampf(MenuSupport.field_float(row, "Foul Chance", 0.0), 0.0, 100.0),
			"yellow": clampf(MenuSupport.field_float(row, "Yellow", 0.0), 0.0, 100.0),
			"red": clampf(MenuSupport.field_float(row, "Red", 0.0), 0.0, 100.0),
		})
	if _rows.is_empty():
		print("[fouls] No Fouls.csv — nobody ever gives a foul away.")
		return _rows
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["triggers"]) < float(b["triggers"]))

	for row in _rows:
		if float(row["yellow"]) + float(row["red"]) > 100.0:
			_problems.append("At %d triggers, Yellow + Red is more than 100. What is left over is an ordinary free kick, so they have to add up to less."
				% int(row["triggers"]))
	for i in range(1, _rows.size()):
		if float(_rows[i]["chance"]) < float(_rows[i - 1]["chance"]):
			_problems.append("At %d triggers the foul chance is LOWER than at %d. Doing more should not make a side safer."
				% [int(_rows[i]["triggers"]), int(_rows[i - 1]["triggers"])])

	print("[fouls] %d row(s) from Fouls.csv." % _rows.size())
	for problem in _problems:
		print("[fouls] %s" % problem)
	return _rows


static func problems() -> Array[String]:
	rows()
	return _problems


## The three numbers at this many triggers, interpolated between rows.
static func odds_at(triggers: int) -> Dictionary:
	var table := rows()
	if table.is_empty():
		return {"chance": 0.0, "yellow": 0.0, "red": 0.0}
	var many := float(maxi(0, triggers))
	if many <= float(table[0]["triggers"]):
		return table[0]
	if many >= float(table[-1]["triggers"]):
		return table[-1]
	for i in range(1, table.size()):
		var high: Dictionary = table[i]
		if many > float(high["triggers"]):
			continue
		var low: Dictionary = table[i - 1]
		var span := float(high["triggers"]) - float(low["triggers"])
		var how_far := 0.0 if is_zero_approx(span) else (many - float(low["triggers"])) / span
		return {
			"chance": lerpf(float(low["chance"]), float(high["chance"]), how_far),
			"yellow": lerpf(float(low["yellow"]), float(high["yellow"]), how_far),
			"red": lerpf(float(low["red"]), float(high["red"]), how_far),
		}
	return table[-1]


## Roll it. Returns "" for no foul, or "free kick", "yellow" or "red".
static func roll(triggers: int) -> String:
	var odds := odds_at(triggers)
	if randf() * 100.0 >= float(odds["chance"]):
		return ""
	var card := randf() * 100.0
	if card < float(odds["red"]):
		return "red"
	if card < float(odds["red"]) + float(odds["yellow"]):
		return "yellow"
	return "free kick"


# =============================================================
#  THE STAND-IN
# =============================================================

## A copy of `donor` playing at `power`, with no abilities.
##
## It keeps the donor's NAME on purpose — this is a man playing out of
## position, not a stranger who appeared on the bench. What he loses is
## everything that made him special: both abilities, and any brew overlay,
## because a trick he knows at his own power is not a trick he knows at
## somebody else's.
static func stand_in_for(donor: PlayerData, power: int) -> PlayerData:
	if donor == null:
		return null
	var copy: PlayerData = donor.duplicate(true)
	copy.base_power_left = power
	copy.base_power_right = power
	copy.attack_ability_id = ""
	copy.defend_ability_id = ""
	copy.clear_brew()
	# NOT A STAR, whoever he is copied from. A Star's whole identity is the
	# abilities this strips, and leaving the badge on would promise something
	# the card cannot do.
	copy.player_type = ""
	return copy
