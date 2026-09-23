class_name SeasonRules
extends RefCounted

# =============================================================
#  A COMPETITION'S OWN RULES — data/SeasonRules.csv
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "Seasons with their own rules: what is allowed, what is on the field,
#   what is different — per season, in a CSV."
#
#  Three questions, three groups of columns:
#
#      WHAT IS ALLOWED      Only Classes · No Brews · No Stars
#      WHAT IS ON THE FIELD Per Tier
#      WHAT IS DIFFERENT    Tuning — any row of Tuning.csv, for the season
#
#  ============ THE RULE ABOUT RULES ============
#
#  A competition's rules are LENT, not given. Everything in the Tuning column
#  is put back the moment you leave the competition, because a Winter Cup
#  that quietly leaves the keeper tired for the rest of the game is a bug
#  nobody will ever trace back to the Winter Cup.
#
#  That is why the numbers are not written into GameState. They are applied
#  to the CardDatabase when a fixture in that competition starts and cleared
#  when one outside it does — see apply_to() below, which is called from the
#  one place a match reads its mode.
#
#  ============ THE `*` ROW ============
#
#  A competition with no row of its own plays by the `*` row, so a season you
#  add tomorrow already works. Keep it.
# =============================================================

const FILE := "res://data/SeasonRules.csv"

static var _rows: Dictionary = {}
static var _problems: Array[String] = []
static var _loaded := false
## What the last competition borrowed, so it can be handed back.
static var _lent: Dictionary = {}


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

	var db := CardDatabase.get_db()
	for row in MenuSupport.read_csv(FILE):
		var season := MenuSupport.field(row, "Season").strip_edges()
		if season == "":
			continue
		var tuning := _pairs(MenuSupport.field(row, "Tuning"))

		# ============ THE THREE NAMED COLUMNS ARE TUNING ROWS TOO ============
		#
		# `No Brews`, `No Stars` and `Per Tier` are written as their own
		# columns because that is how a designer thinks about them — but they
		# are FOLDED INTO the same Tuning dictionary here, so there is exactly
		# one mechanism for lending a rule and exactly one for handing it back.
		#
		# Without this they would each have needed their own plumbing, their
		# own place to be read, and their own way of being forgotten at the
		# end of a competition. Three named columns, one machine.
		if _yes(MenuSupport.field(row, "No Brews")):
			tuning["brews_allowed"] = "false"
		if _yes(MenuSupport.field(row, "No Stars")):
			tuning["stars_allowed"] = "false"
		var per_tier := MenuSupport.field_int(row, "Per Tier", 0)
		if per_tier > 0:
			tuning["season_per_tier"] = str(per_tier)

		_rows[_key(season)] = {
			"season": season,
			"only": _list_of(MenuSupport.field(row, "Only Classes")),
			"no_brews": _yes(MenuSupport.field(row, "No Brews")),
			"no_stars": _yes(MenuSupport.field(row, "No Stars")),
			"per_tier": MenuSupport.field_int(row, "Per Tier", 0),
			"tuning": tuning,
			"story": MenuSupport.field(row, "Story Before").strip_edges(),
			"description": MenuSupport.field(row, "Description").strip_edges(),
		}
		# EVERY KEY IN THE TUNING COLUMN HAS TO BE A REAL TUNING ROW. A
		# misspelling here is a rule that silently does nothing, which is the
		# worst kind: the competition looks like it is bending the game and
		# it is not.
		if db != null:
			for key in tuning:
				if not db.tuning.has(CardDatabase._normalise(String(key))):
					_problems.append("'%s' bends `%s`, which is not a row of Tuning.csv — that rule does nothing."
						% [season, key])

	if not _rows.has(_key("*")):
		_problems.append("SeasonRules.csv has no `*` row. That is what every competition without one of its own plays by.")

	print("[season rules] %d competition(s) with rules of their own." % _rows.size())
	for problem in _problems:
		print("[season rules] %s" % problem)


static func problems() -> Array[String]:
	_load()
	return _problems


static func _key(text: String) -> String:
	return CardDatabase._normalise(text)


static func _yes(text: String) -> bool:
	return text.strip_edges().to_lower().begins_with("y")


static func _list_of(text: String) -> Array[String]:
	var out: Array[String] = []
	for part in text.split("|", false):
		var clean := String(part).strip_edges()
		if clean != "":
			out.append(clean)
	return out


## "a=1|b=2" -> {"a": "1", "b": "2"}
static func _pairs(text: String) -> Dictionary:
	var out: Dictionary = {}
	for part in text.split("|", false):
		var clean := String(part).strip_edges()
		var at := clean.find("=")
		if at <= 0:
			continue
		out[clean.substr(0, at).strip_edges()] = clean.substr(at + 1).strip_edges()
	return out


# =============================================================
#  ASKING IT THINGS
# =============================================================

## The rules for a competition, falling back to `*`. Never empty.
static func for_season(season_id: String) -> Dictionary:
	_load()
	var mine: Dictionary = _rows.get(_key(season_id), {})
	if not mine.is_empty():
		return mine
	var any: Dictionary = _rows.get(_key("*"), {})
	if not any.is_empty():
		return any
	return {"season": season_id, "only": [], "no_brews": false, "no_stars": false,
		"per_tier": 0, "tuning": {}, "story": "", "description": ""}


static func every() -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	for key in _rows:
		out.append(_rows[key])
	return out


## May this class play in this competition?
static func class_allowed(season_id: String, unit_type: String) -> bool:
	var rules := for_season(season_id)
	var only: Array = rules["only"]
	if only.is_empty():
		return true
	for name_text in only:
		if _key(String(name_text)) == _key(unit_type):
			return true
	return false


## In a sentence, for a screen. "" when nothing is different.
static func words(season_id: String) -> String:
	var rules := for_season(season_id)
	var said: Array[String] = []
	var only: Array = rules["only"]
	if not only.is_empty():
		said.append("only " + ", ".join(PackedStringArray(only)))
	if bool(rules["no_brews"]):
		said.append("no brews")
	if bool(rules["no_stars"]):
		said.append("no Star Players")
	if int(rules["per_tier"]) > 0:
		said.append("%d per tier" % int(rules["per_tier"]))
	# THE THREE FOLDED KEYS ARE ALREADY SAID ABOVE in their own words, so
	# they are skipped here — otherwise a Winter Cup reads "no brews, brews
	# allowed is false", which is the same rule twice and one of them in
	# machine language.
	var folded := ["brews_allowed", "stars_allowed", "season_per_tier"]
	for key in rules["tuning"]:
		if folded.has(String(key)):
			continue
		said.append("%s is %s" % [String(key).replace("_", " "), rules["tuning"][key]])
	return ", ".join(PackedStringArray(said))


# =============================================================
#  LENDING AND HANDING BACK
# =============================================================

## Put this competition's rules on the database, and take the last one's off.
##
## `season_id` is "" for a match outside any competition — a friendly, a
## quick match — which hands everything back and borrows nothing.
static func apply_to(season_id: String, db: CardDatabase) -> void:
	if db == null:
		return
	# ---- hand back whatever was borrowed ----
	for key in _lent:
		db.tuning[CardDatabase._normalise(String(key))] = String(_lent[key])
	_lent = {}

	if season_id.strip_edges() == "":
		return
	var rules := for_season(season_id)
	var tuning: Dictionary = rules["tuning"]
	if tuning.is_empty():
		return

	for key in tuning:
		var flat := CardDatabase._normalise(String(key))
		# REMEMBER THE OLD VALUE BEFORE WRITING THE NEW ONE, or there is
		# nothing to hand back.
		_lent[key] = String(db.tuning.get(flat, ""))
		db.tuning[flat] = String(tuning[key])
	print("[season rules] %s: %s" % [rules["season"], words(season_id)])
