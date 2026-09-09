class_name AdventureDB
extends RefCounted

# =============================================================
#  ADVENTURE MODE — the five spreadsheets that make a run
#
#  Biomes.csv            the areas you explore
#  Bounties.csv          the jobs on the board. A BOUNTY IS A BOSS.
#  AdventureEnemies.csv  who you meet, and what they are made of
#  Items.csv             what you can pick up
#  Drops.csv             what things leave behind
#
#  Nothing in code names a biome, an enemy or an item. Write a row, it is
#  in the game.
#
#  ============ THE ONE IDEA WORTH READING ============
#
#  AN ENEMY IS MADE OF LAYERS. A Bog Lurker is `Hide:4:1|Body:9`, which
#  means:
#
#      Hide   4 points thick, and it SOAKS 1 off every hit
#      Body   9 points thick, no soak
#
#  Damage always goes into the OUTERMOST layer that is still there. Chew
#  through the Hide and the Body is exposed; empty the last layer and the
#  enemy is finished. The Marsh King is three layers deep and each one soaks
#  more than the last, which is what makes a boss a boss rather than just a
#  big number.
#
#  The shape is  Name:Amount:Soak , separated by | (a pipe). Soak is
#  optional — `Body:5` is a perfectly good one-layer enemy.
#
#  ============ ITEMS ARE COUNTERS ============
#
#  Every item in Items.csv is a counter in your save, exactly like coins and
#  goals. That is deliberate and it is what makes the economy free: a
#  building's cost (`count:reed>=20`), a talent's requirement, a bounty's
#  reward and a dialogue choice all already understand counters. Nothing had
#  to be built for items to work with any of them.
# =============================================================

const DATA_DIR := "res://data/"

static var _instance: AdventureDB = null

## id -> row. Keyed by the normalised ID so lookups are typo-tolerant.
var biomes: Dictionary = {}
var bounties: Dictionary = {}
var enemies: Dictionary = {}
var items: Dictionary = {}

## table name -> Array of drop rows.
var drops: Dictionary = {}

var problems: Array[String] = []


static func get_db() -> AdventureDB:
	if _instance == null:
		_instance = AdventureDB.new()
		_instance.load_all()
	return _instance


static func reload() -> void:
	_instance = null
	get_db()


# =============================================================
#  LOADING
# =============================================================

func load_all() -> void:
	biomes.clear()
	bounties.clear()
	enemies.clear()
	items.clear()
	drops.clear()
	problems.clear()

	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		problems.append("Could not open %s" % DATA_DIR)
		return

	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if file_name.to_lower().ends_with(".csv"):
			_load_csv(DATA_DIR + file_name)

	_validate()


## Files are recognised BY THEIR COLUMNS, not their names — the same rule
## the rest of the project uses — so you can rename or split any of these.
func _load_csv(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var rows := CardDatabase.parse_csv(file.get_as_text())
	file.close()
	if rows.size() < 2:
		return

	var columns: Dictionary = {}
	var header: PackedStringArray = rows[0]
	for i in header.size():
		var key := CardDatabase._normalise(header[i])
		if key != "":
			columns[key] = i

	var where := path.get_file()

	if columns.has("enemypool") and columns.has("waves"):
		_read_biomes(rows, columns, where)
	elif columns.has("boss") and columns.has("reward"):
		_read_bounties(rows, columns, where)
	elif columns.has("layers") and columns.has("targeting"):
		_read_enemies(rows, columns, where)
	elif columns.has("kind") and columns.has("stack"):
		_read_items(rows, columns, where)
	elif columns.has("table") and columns.has("chance"):
		_read_drops(rows, columns, where)


func _read_biomes(rows: Array, columns: Dictionary, where: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		if id_text == "":
			continue
		biomes[CardDatabase._normalise(id_text)] = {
			"id": id_text,
			"name": _or(_cell(row, columns, "name"), id_text),
			"order": _int(_cell(row, columns, "order"), 999),
			"requires": _cell(row, columns, "requires"),
			"waves": maxi(1, _int(_cell(row, columns, "waves"), 4)),
			"pool": _cell(row, columns, "enemypool"),
			"art": _cell(row, columns, "scrollart"),
			"ground": _cell(row, columns, "ground"),
			"music": _cell(row, columns, "music"),
			"drops": _cell(row, columns, "drops"),
			"difficulty": maxi(1, _int(_cell(row, columns, "difficulty"), 1)),
			"description": _cell(row, columns, "description"),
			"where": "%s row %d" % [where, i + 1],
		}


func _read_bounties(rows: Array, columns: Dictionary, where: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		if id_text == "":
			continue
		bounties[CardDatabase._normalise(id_text)] = {
			"id": id_text,
			"name": _or(_cell(row, columns, "name"), id_text),
			"biome": _cell(row, columns, "biome"),
			"boss": _cell(row, columns, "boss"),
			"reward": _cell(row, columns, "reward"),
			"requires": _cell(row, columns, "requires"),
			"repeatable": _yes(_cell(row, columns, "repeatable"), false),
			"power": _int(_cell(row, columns, "recommendedpower"), 0),
			"art": _cell(row, columns, "art"),
			"description": _cell(row, columns, "description"),
			"where": "%s row %d" % [where, i + 1],
		}


func _read_enemies(rows: Array, columns: Dictionary, where: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		if id_text == "":
			continue
		var layer_text := _cell(row, columns, "layers")
		enemies[CardDatabase._normalise(id_text)] = {
			"id": id_text,
			"name": _or(_cell(row, columns, "name"), id_text),
			"pool": _cell(row, columns, "pool"),
			"tier": _cell(row, columns, "tier").to_upper(),
			"power": _int(_cell(row, columns, "power"), 1),
			"layers": parse_layers(layer_text),
			"layer_text": layer_text,
			"damage": _int(_cell(row, columns, "damage"), 1),
			"targeting": _or(_cell(row, columns, "targeting").to_lower(), "weakest"),
			"element": _cell(row, columns, "element"),
			"ability": _cell(row, columns, "ability"),
			"art": _cell(row, columns, "art"),
			"drops": _cell(row, columns, "drops"),
			"weight": _int(_cell(row, columns, "weight"), 1),
			"boss": _yes(_cell(row, columns, "boss"), false),
			"description": _cell(row, columns, "description"),
			"where": "%s row %d" % [where, i + 1],
		}


func _read_items(rows: Array, columns: Dictionary, where: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		if id_text == "":
			continue
		items[CardDatabase._normalise(id_text)] = {
			"id": id_text,
			"name": _or(_cell(row, columns, "name"), id_text),
			"kind": _or(_cell(row, columns, "kind").to_lower(), "material"),
			"stack": maxi(1, _int(_cell(row, columns, "stack"), 99)),
			"art": _cell(row, columns, "art"),
			"requires": _cell(row, columns, "requires"),
			"description": _cell(row, columns, "description"),
			"where": "%s row %d" % [where, i + 1],
		}


## A drop TABLE is every row sharing a Table name. That is why this one is
## keyed differently from the others.
func _read_drops(rows: Array, columns: Dictionary, where: String) -> void:
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var table := _cell(row, columns, "table")
		var item := _cell(row, columns, "item")
		if table == "" or item == "":
			continue
		var key := CardDatabase._normalise(table)
		if not drops.has(key):
			drops[key] = [] as Array[Dictionary]
		(drops[key] as Array).append({
			"table": table,
			"item": item,
			"amount": maxi(0, _int(_cell(row, columns, "amount"), 1)),
			"chance": clampf(_float(_cell(row, columns, "chance"), 1.0), 0.0, 1.0),
			"requires": _cell(row, columns, "requires"),
			"where": "%s row %d" % [where, i + 1],
		})


# =============================================================
#  LAYERS
# =============================================================

## "Hide:4:1|Body:9"  ->  [{name, amount, soak}, {name, amount, soak}]
##
## Outermost first, which is the order they are written and the order they
## are chewed through. A blank column gives one layer of 1, so a half-filled
## row still produces an enemy you can hit.
static func parse_layers(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for piece in text.split("|"):
		var part := String(piece).strip_edges()
		if part == "":
			continue
		var bits := part.split(":")
		var layer_name := String(bits[0]).strip_edges()
		var amount := 1
		var soak := 0
		if bits.size() > 1 and String(bits[1]).strip_edges().is_valid_int():
			amount = maxi(1, int(String(bits[1]).strip_edges()))
		if bits.size() > 2 and String(bits[2]).strip_edges().is_valid_int():
			soak = maxi(0, int(String(bits[2]).strip_edges()))
		out.append({
			"name": layer_name if layer_name != "" else "Body",
			"amount": amount,
			"soak": soak,
		})

	if out.is_empty():
		out.append({"name": "Body", "amount": 1, "soak": 0})
	return out


## Everything an enemy is made of, added up. Used to sanity-check a bounty's
## recommended power and to size the health bar.
static func total_layers(entry: Dictionary) -> int:
	var total := 0
	for layer in (entry.get("layers", []) as Array):
		total += int((layer as Dictionary)["amount"])
	return total


# =============================================================
#  ASKING IT THINGS
# =============================================================

func biome(biome_id: String) -> Dictionary:
	return biomes.get(CardDatabase._normalise(biome_id), {})


func bounty(bounty_id: String) -> Dictionary:
	return bounties.get(CardDatabase._normalise(bounty_id), {})


func enemy(enemy_id: String) -> Dictionary:
	return enemies.get(CardDatabase._normalise(enemy_id), {})


func item(item_id: String) -> Dictionary:
	return items.get(CardDatabase._normalise(item_id), {})


## The biomes you can walk into right now, in their Order.
func open_biomes(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in biomes.keys():
		var entry: Dictionary = biomes[key]
		if DialogueGrammar.test(String(entry["requires"]), state):
			out.append(entry)
	out.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	return out


## Every biome, open or not — the board shows locked ones greyed out so you
## can see what you are working towards.
func all_biomes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in biomes.keys():
		out.append(biomes[key])
	out.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	return out


## The jobs pinned to the board for one biome. `open` says whether each is
## takeable; a locked one is still listed, because seeing it is the point.
func bounties_in(biome_id: String, state: GameState) -> Array[Dictionary]:
	var wanted := CardDatabase._normalise(biome_id)
	var out: Array[Dictionary] = []
	for key in bounties.keys():
		var entry: Dictionary = bounties[key]
		if CardDatabase._normalise(String(entry["biome"])) != wanted:
			continue
		var copy := entry.duplicate()
		copy["open"] = DialogueGrammar.test(String(entry["requires"]), state)
		copy["done"] = not bool(entry["repeatable"]) \
			and state != null and state.is_unlocked(_reward_name(entry))
		out.append(copy)

	# Easiest first, so the board reads as a difficulty ramp.
	out.sort_custom(func(a, b): return int(a["power"]) < int(b["power"]))
	return out


## The thing a bounty unlocks, if it unlocks anything — used to grey out a
## one-off job you have already done.
static func _reward_name(entry: Dictionary) -> String:
	for term in String(entry.get("reward", "")).split(";"):
		var part := String(term).strip_edges()
		if part.to_lower().begins_with("unlock:"):
			return part.substr(7).strip_edges()
	return ""


## The ordinary enemies of a pool, weighted. Bosses (Weight 0) never appear
## here — they are placed by the bounty.
func pool_enemies(pool: String, tier: String = "") -> Array[Dictionary]:
	var wanted := CardDatabase._normalise(pool)
	var wanted_tier := tier.strip_edges().to_upper()
	var out: Array[Dictionary] = []
	for key in enemies.keys():
		var entry: Dictionary = enemies[key]
		if CardDatabase._normalise(String(entry["pool"])) != wanted:
			continue
		if int(entry["weight"]) <= 0:
			continue
		if wanted_tier != "" and String(entry["tier"]) != wanted_tier:
			continue
		out.append(entry)
	return out


## Roll a drop table. Returns item id -> amount, so it can be handed
## straight to GameState as counters.
func roll(table: String, state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for row in (drops.get(CardDatabase._normalise(table), []) as Array):
		var entry: Dictionary = row
		if not DialogueGrammar.test(String(entry["requires"]), state):
			continue
		if randf() > float(entry["chance"]):
			continue
		var key := String(entry["item"])
		out[key] = int(out.get(key, 0)) + int(entry["amount"])
	return out


# =============================================================
#  CHECKING IT HANGS TOGETHER
#
#  Every one of these is a mistake that would otherwise show up as an empty
#  screen or a boss that never arrives, with nothing to tell you why.
# =============================================================

func _validate() -> void:
	for key in biomes.keys():
		var entry: Dictionary = biomes[key]
		if String(entry["pool"]).strip_edges() == "":
			problems.append("%s: biome '%s' names no Enemy Pool, so nothing can spawn in it."
				% [entry["where"], entry["name"]])
		elif pool_enemies(String(entry["pool"])).is_empty():
			problems.append("%s: biome '%s' uses enemy pool '%s', but no AdventureEnemies.csv row has that Pool with a Weight above 0."
				% [entry["where"], entry["name"], entry["pool"]])
		if String(entry["drops"]).strip_edges() != "" \
				and not drops.has(CardDatabase._normalise(String(entry["drops"]))):
			problems.append("%s: biome '%s' uses ground drop table '%s', which is not a Table in Drops.csv."
				% [entry["where"], entry["name"], entry["drops"]])

		# EVERY TIER NEEDS SOMEBODY. A pool with no Tier II enemy means every
		# encounter in that biome hands the player a free Tier II win — the
		# walkover rule cuts both ways, and this is the half that is a
		# mistake rather than a reward.
		for tier in TierLadder.TIERS:
			if pool_enemies(String(entry["pool"]), tier).is_empty():
				problems.append("%s: biome '%s' has no Tier %s enemy in pool '%s'. Every encounter there would be a free Tier %s win for the player — add a row to AdventureEnemies.csv."
					% [entry["where"], entry["name"], tier, entry["pool"], tier])

	for key in bounties.keys():
		var entry: Dictionary = bounties[key]
		if biome(String(entry["biome"])).is_empty():
			problems.append("%s: bounty '%s' is in biome '%s', which is not in Biomes.csv."
				% [entry["where"], entry["name"], entry["biome"]])
		var boss := enemy(String(entry["boss"]))
		if boss.is_empty():
			problems.append("%s: bounty '%s' names boss '%s', which is not in AdventureEnemies.csv."
				% [entry["where"], entry["name"], entry["boss"]])
		elif not bool(boss["boss"]):
			problems.append("%s: bounty '%s' names '%s' as its boss, but that row's Boss column is not yes."
				% [entry["where"], entry["name"], boss["name"]])
		for complaint in DialogueGrammar.complaints(String(entry["reward"]), true):
			problems.append("%s: bounty '%s' reward — %s"
				% [entry["where"], entry["name"], complaint])

	for key in enemies.keys():
		var entry: Dictionary = enemies[key]
		if not TierLadder.TIERS.has(String(entry["tier"])):
			problems.append("%s: enemy '%s' has tier '%s' — expected I, II, III or IV."
				% [entry["where"], entry["name"], entry["tier"]])
		# The ladder governs enemies too: a Tier I enemy with 5 power would
		# face your Tier I, whose best card is a 2.
		elif not TierLadder.rungs(String(entry["tier"])).has(int(entry["power"])):
			problems.append("%s: enemy '%s' is Tier %s with %d power. %s"
				% [entry["where"], entry["name"], entry["tier"], entry["power"],
					TierLadder.describe(String(entry["tier"]))])
		if String(entry["drops"]).strip_edges() != "" \
				and not drops.has(CardDatabase._normalise(String(entry["drops"]))):
			problems.append("%s: enemy '%s' drops table '%s', which is not a Table in Drops.csv."
				% [entry["where"], entry["name"], entry["drops"]])

		# A LAYER THAT SOAKS TOO MUCH IS A WALL. Damage is the power gap
		# minus the soak, and the biggest gap you can ever have is 5 (a 5
		# against a 0). A soak of 5 or more means only the damage minimum
		# ever gets through, which is technically killable and practically
		# a stalemate.
		for layer in (entry["layers"] as Array):
			var soak := int((layer as Dictionary)["soak"])
			if soak >= 5:
				problems.append("%s: enemy '%s' layer '%s' soaks %d. The largest power gap possible is 5, so almost nothing would get through — 0 to 3 is the useful range."
					% [entry["where"], entry["name"],
						(layer as Dictionary)["name"], soak])

	for key in drops.keys():
		for row in (drops[key] as Array):
			var entry: Dictionary = row
			if item(String(entry["item"])).is_empty():
				problems.append("%s: drop table '%s' gives '%s', which is not in Items.csv. It would still be counted, but nothing can show its name or picture."
					% [entry["where"], entry["table"], entry["item"]])


# =============================================================
#  HELPERS
# =============================================================

func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()


static func _or(text: String, fallback: String) -> String:
	return text if text.strip_edges() != "" else fallback


static func _int(text: String, fallback: int) -> int:
	var clean := text.strip_edges()
	return int(clean) if clean.is_valid_int() else fallback


static func _float(text: String, fallback: float) -> float:
	var clean := text.strip_edges()
	return float(clean) if clean.is_valid_float() else fallback


static func _yes(text: String, fallback: bool) -> bool:
	var clean := text.strip_edges().to_lower()
	if clean == "":
		return fallback
	return clean in ["yes", "true", "y", "1", "on"]
