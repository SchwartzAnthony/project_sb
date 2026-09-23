class_name RunPlan
extends RefCounted

# =============================================================
#  WHAT A RUN IS MADE OF — data/Pickups.csv
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "A fixed number of pickups before each wave and the boss, from a CSV,
#   instead of however many happen to spawn."
#
#  That is exactly what was wrong with it. Pickups arrived on a TIMER with a
#  random gap, so a run gave you somewhere between one and six of them and
#  nobody — not you, not me, not a tool — could say which. A run's reward was
#  therefore unwritable: you cannot balance a biome whose haul is a dice roll
#  you never see.
#
#  Now the number is written down. THREE on the way to each wave and FIVE on
#  the way to the boss, spaced evenly over whatever distance that turns out
#  to be, so a faster run does not mean a poorer one.
#
#  ============ THE COLUMNS ============
#
#      Biome         a Biomes.csv id, or `*` for every biome
#      Before Wave   how many pickups between here and the next wave
#      Before Boss   and on the last stretch
#      Drops         a Drops.csv table, or blank for the biome's own
#
#  ============ WHY IT IS A SEPARATE FILE ============
#
#  Because it is a question about PACING and Biomes.csv is a question about
#  PLACE. A biome's row already carries its colours, its music, its enemy
#  pool and its waves; adding two more numbers to it would have buried them.
#  And a `*` row here sets the pacing of every biome at once, which is the
#  edit you actually want to make while tuning.
# =============================================================

const FILE := "res://data/Pickups.csv"

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
		var biome := MenuSupport.field(row, "Biome").strip_edges()
		if biome == "":
			continue
		_rows[CardDatabase._normalise(biome)] = {
			"biome": biome,
			"before_wave": maxi(0, MenuSupport.field_int(row, "Before Wave", 3)),
			"before_boss": maxi(0, MenuSupport.field_int(row, "Before Boss", 5)),
			"drops": MenuSupport.field(row, "Drops").strip_edges(),
		}

	if not _rows.has(CardDatabase._normalise("*")):
		_problems.append("Pickups.csv has no `*` row. That is what every biome without one of its own uses, so a new biome would drop nothing.")

	# A BIOME NAMED HERE THAT DOES NOT EXIST is a row that will never fire,
	# and it looks exactly like a row that works.
	var adventure := AdventureDB.get_db()
	if adventure != null:
		for key in _rows:
			var biome := String(_rows[key]["biome"])
			if biome == "*":
				continue
			if adventure.biome(biome).is_empty():
				_problems.append("'%s' is not a row of Biomes.csv, so that pacing never applies to anything." % biome)

	print("[pickups] %d pacing row(s)." % _rows.size())
	for problem in _problems:
		print("[pickups] %s" % problem)


static func problems() -> Array[String]:
	_load()
	return _problems


static func for_biome(biome_id: String) -> Dictionary:
	_load()
	var mine: Dictionary = _rows.get(CardDatabase._normalise(biome_id), {})
	if not mine.is_empty():
		return mine
	var any: Dictionary = _rows.get(CardDatabase._normalise("*"), {})
	if not any.is_empty():
		return any
	return {"biome": biome_id, "before_wave": 3, "before_boss": 5, "drops": ""}


static func every() -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	for key in _rows:
		out.append(_rows[key])
	return out


## How many pickups belong on THIS stretch.
static func how_many(biome_id: String, boss_next: bool) -> int:
	var plan := for_biome(biome_id)
	return int(plan["before_boss"]) if boss_next else int(plan["before_wave"])


## What a whole run is worth, in pickups. The number a biome should be
## balanced against, and the reason this file exists.
static func over_a_run(biome_id: String, waves: int) -> int:
	var plan := for_biome(biome_id)
	# The last wave IS the boss, so a run of four waves is three ordinary
	# stretches and one boss stretch.
	var ordinary := maxi(0, waves - 1)
	return ordinary * int(plan["before_wave"]) + int(plan["before_boss"])
