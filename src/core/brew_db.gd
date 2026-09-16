class_name BrewDB
extends RefCounted

# =============================================================
#  BREWS.CSV — what the Pub pours
#
#  A brew is drunk by one CARD. For the next match that card counts as a
#  different class, wears different art, and gains abilities it never had.
#  Base cards have no abilities at all, so this is where a card's ability
#  comes from.
#
#  THE COLUMNS
#    ID              short and lower-case: fire, water, keeper. This is the
#                    word that lands in `goals_with_brew_{brew}`, so keep it
#                    tidy.
#    Name            what the player sees
#    Description     one line
#    Requires        when the Pub can pour it. Usually  unlocked:Fire Brew ,
#                    which the Brewing talents grant. Blank = always.
#    For Class       only cards of this class may drink it. Blank = anyone.
#    Becomes         the class the card COUNTS AS afterwards. Blank = no
#                    change, just abilities.
#    Artwork         spritesheet PNG for the brewed card, in
#                    assets/players/. Blank = keep the card's own art.
#    Attack Ability  an Ability ID from Abilities.csv
#    Defend Ability  an Ability ID from Abilities.csv
#    Permanent       true = this brew may be made permanent, if the player
#                    has unlocked Permanent Brews. Blank = one match only.
#    Notes           yours
#
#  PER-CARD ART
#    If a PNG named  "<Card Name> <brew id>.png"  exists in
#    assets/players/, it is used instead of the brew's Artwork column. So
#    "Cinderworks Brandteufel water.png" gives that one card its own
#    water-brewed look, and everyone else falls back to the shared one.
#
#  HOW LONG IT LASTS
#    A normal brew is cleared at the final whistle. A PERMANENT brew is
#    kept until the player removes it at the Pub. Both are stored in the
#    save, not on the card, so nothing leaks between runs.
# =============================================================

const DATA_DIR := "res://data/"
const ART_DIRS: Array[String] = ["res://assets/players/", "res://assets/brews/", "res://assets/"]

## How a poured brew is remembered. Both are per-card.
const TEMP_PREFIX := "brew_"
const PERM_PREFIX := "permbrew_"
## What a player must have unlocked before a brew can be made permanent.
const PERMANENT_UNLOCK := "Permanent Brews"

static var _instance: BrewDB
## Cards currently wearing an overlay, so it can be taken off again.
static var _applied: Array[PlayerData] = []

var brews: Array[Dictionary] = []
var problems: Array[String] = []


static func get_db() -> BrewDB:
	if _instance == null:
		_instance = BrewDB.new()
		_instance.load_all()
	return _instance


## RE-READ THE SPREADSHEETS FROM DISK.
##
## NOT CALLED `reload()`. Every class_name in Godot is also a Script object,
## and Script already has a built-in reload() — so `BaseDB.reload()` resolved
## to THAT and printed
##
##     Cannot reload script while instances exist.
##
## while quietly never calling this at all. Naming it reload_files() is the
## whole fix. If you add a loader of your own, avoid reload(), free(),
## duplicate() and get_name() for the same reason.
static func reload_files() -> void:
	_instance = null
	get_db()


# =============================================================
#  LOADING
# =============================================================

func load_all() -> void:
	brews.clear()
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

	# A brews file has an ID and a Becomes column. "Becomes" is what makes
	# it a brew rather than a building or a talent.
	if not (columns.has("id") and columns.has("becomes")):
		return

	var short_name := path.get_file()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id_text := _cell(row, columns, "id")
		if id_text == "":
			continue

		brews.append({
			"id": id_text,
			"name": _cell(row, columns, "name"),
			"description": _cell(row, columns, "description"),
			"requires": _cell(row, columns, "requires"),
			"for_class": _cell(row, columns, "forclass"),
			"becomes": _cell(row, columns, "becomes"),
			"artwork": _cell(row, columns, "artwork"),
			"attack": _cell(row, columns, "attackability"),
			"defend": _cell(row, columns, "defendability"),
			"permanent": _cell(row, columns, "permanent").to_lower() in ["true", "yes", "1", "on"],
			# ============ WHAT IT COSTS TO POUR ============
			#
			# `reed:5|water:3` — the same name:amount shape Teams.csv uses for
			# its Cards column, separated by a pipe.
			#
			# THIS IS THE MISSING HALF OF THE ECONOMY. Brews could be gated
			# behind having materials, but pouring one never SPENT anything,
			# so a single Adventure run bought infinite brews forever. Now the
			# Pub takes the materials out of your counters when it pours.
			#
			# Blank costs nothing, which is what every brew did before.
			"cost": parse_cost(_cell(row, columns, "cost")),
			"where": "%s row %d" % [short_name, i + 1],
		})


# =============================================================
#  QUERIES
# =============================================================

func find(brew_id: String) -> Dictionary:
	var key := CardDatabase._normalise(brew_id)
	for entry in brews:
		if CardDatabase._normalise(String(entry["id"])) == key:
			return entry
	return {}


## The brews the Pub can pour right now.
func available_for(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in brews:
		if DialogueGrammar.test(String(entry["requires"]), state):
			out.append(entry)
	return out


## May this card drink this brew? Only the For Class column decides.
static func suits(entry: Dictionary, card: PlayerData) -> bool:
	if entry.is_empty() or card == null:
		return false
	var wanted := String(entry["for_class"]).strip_edges()
	if wanted == "":
		return true
	return CardDatabase._normalise(wanted) == CardDatabase._normalise(card.unit_type)


static func card_key(card: PlayerData) -> String:
	return CardDatabase._normalise(card.player_name) if card != null else ""


## Which brew this card is on. A one-match brew beats a permanent one, so a
## player can try something different for a single game without losing the
## permanent one underneath.
static func brew_id_for(card: PlayerData, state: GameState) -> String:
	if card == null or state == null:
		return ""
	var key := card_key(card)
	var temporary := state.text(TEMP_PREFIX + key)
	return temporary if temporary != "" else state.text(PERM_PREFIX + key)


static func is_permanent(card: PlayerData, state: GameState) -> bool:
	if card == null or state == null:
		return false
	return state.text(PERM_PREFIX + card_key(card)) != ""


# =============================================================
#  POURING
# =============================================================

## Give a card a brew. `permanent` is ignored unless the brew allows it and
## the player has unlocked Permanent Brews.
## "reed:5|water:3" -> {"reed": 5, "water": 3}. A piece with no number
## costs one, so `reed` on its own is `reed:1`.
static func parse_cost(text: String) -> Dictionary:
	var out: Dictionary = {}
	for piece in text.split("|"):
		var part := String(piece).strip_edges()
		if part == "":
			continue
		var bits := part.split(":")
		var item := String(bits[0]).strip_edges()
		if item == "":
			continue
		var amount := 1
		if bits.size() > 1 and String(bits[1]).strip_edges().is_valid_int():
			amount = maxi(1, int(String(bits[1]).strip_edges()))
		out[item] = int(out.get(item, 0)) + amount
	return out


## Can this be paid for right now?
static func can_afford(entry: Dictionary, state: GameState) -> bool:
	if state == null:
		return false
	for item in (entry.get("cost", {}) as Dictionary).keys():
		if state.count(String(item)) < int((entry["cost"] as Dictionary)[item]):
			return false
	return true


## "5 Reed, 3 Water" — for the Pub to show, and for the refusal message.
static func cost_text(entry: Dictionary, state: GameState = null) -> String:
	var cost: Dictionary = entry.get("cost", {})
	if cost.is_empty():
		return ""
	var words: Array[String] = []
	for item in cost.keys():
		var need := int(cost[item])
		var readable := String(item).replace("_", " ").capitalize()
		if state != null and state.count(String(item)) < need:
			words.append("%d %s (you have %d)" % [need, readable, state.count(String(item))])
		else:
			words.append("%d %s" % [need, readable])
	return ", ".join(words)


static func pour(card: PlayerData, entry: Dictionary, permanent: bool,
		state: GameState) -> void:
	if card == null or state == null or entry.is_empty():
		return

	# PAY FOR IT. Refuses rather than pouring on credit — the Pub screen
	# greys the brew out first, so this is the second line of defence.
	if not can_afford(entry, state):
		print("[pub] Cannot pour %s — it costs %s."
			% [entry.get("name", entry["id"]), cost_text(entry, state)])
		return
	for item in (entry.get("cost", {}) as Dictionary).keys():
		state.add_count(String(item), -int((entry["cost"] as Dictionary)[item]))

	var key := card_key(card)
	var brew_id := String(entry["id"])

	if permanent and bool(entry["permanent"]) and state.is_unlocked(PERMANENT_UNLOCK):
		state.set_text(PERM_PREFIX + key, brew_id)
		state.set_text(TEMP_PREFIX + key, "")
	else:
		state.set_text(TEMP_PREFIX + key, brew_id)

	# Counted here, because this is the moment it is drunk. Stats.csv turns
	# it into brews_drunk and brews_drunk_<id> with no code.
	StatsRules.get_rules().record("brew_drunk", {
		"brew": brew_id,
		"card": card.player_name,
		"class": card.unit_type,
		"tier": card.get_tier_clean(),
	}, state)


## Take everything off one card, permanent included.
static func clear_for(card: PlayerData, state: GameState) -> void:
	if card == null or state == null:
		return
	var key := card_key(card)
	state.set_text(TEMP_PREFIX + key, "")
	state.set_text(PERM_PREFIX + key, "")


## Called at the final whistle. One-match brews wear off; permanent ones stay.
## Returns how many wore off, so the "what you gained" panel can say so.
static func clear_temporary(state: GameState) -> int:
	if state == null:
		return 0
	var doomed: Array[String] = []
	for key in state.texts.keys():
		var name_key := String(key)
		# Keys are stripped to letters and digits, so a temporary brew starts
		# "brew" and a permanent one starts "perm" — no overlap.
		if name_key.begins_with("brew"):
			doomed.append(name_key)
	for key in doomed:
		state.texts.erase(key)
	if not doomed.is_empty():
		print("[brews] %d one-match brew(s) wore off." % doomed.size())
	return doomed.size()


# =============================================================
#  APPLYING TO THE CARDS
# =============================================================

## Lay the overlays on. Always takes the previous ones off first, so calling
## this at the start of every match is enough to keep everything honest.
## Returns how many cards ended up brewed.
func apply_all(cards: CardDatabase, state: GameState) -> int:
	restore_all()
	if cards == null or state == null:
		return 0

	var count := 0
	for card in cards.players:
		var brew_id := brew_id_for(card, state)
		if brew_id == "":
			continue
		var entry := find(brew_id)
		if entry.is_empty():
			push_warning("[brews] '%s' is on %s but no row in Brews.csv defines it."
				% [brew_id, card.player_name])
			continue

		card.brew_id = brew_id
		card.brew_unit_type = String(entry["becomes"])
		card.brew_attack_ability = String(entry["attack"])
		card.brew_defend_ability = String(entry["defend"])
		card.brew_artwork = _artwork_for(card, entry)
		_applied.append(card)
		count += 1

	if count > 0:
		print("[brews] %d card(s) brewed for this match." % count)
	return count


static func restore_all() -> void:
	for card in _applied:
		if card != null:
			card.clear_brew()
	_applied.clear()


## A card's own brewed art if you drew one, otherwise the brew's shared art.
func _artwork_for(card: PlayerData, entry: Dictionary) -> Texture2D:
	var personal := "%s %s" % [card.player_name, entry["id"]]
	var found := _find_texture(personal)
	if found != null:
		return found
	return _find_texture(String(entry["artwork"]))


func _find_texture(file_name: String) -> Texture2D:
	var clean := file_name.strip_edges()
	if clean == "":
		return null
	for folder in ART_DIRS:
		for candidate in [folder + clean, folder + clean + ".png"]:
			if ResourceLoader.exists(candidate):
				var res := load(candidate)
				if res is Texture2D:
					return res as Texture2D
	return null


# =============================================================
#  VALIDATION
# =============================================================

func _validate() -> void:
	var cards := CardDatabase.get_db()
	var seen: Dictionary = {}

	for entry in brews:
		var key := CardDatabase._normalise(String(entry["id"]))
		if seen.has(key):
			problems.append("%s: brew ID '%s' is already used by %s"
				% [entry["where"], entry["id"], seen[key]])
		else:
			seen[key] = entry["where"]

		if String(entry["name"]).strip_edges() == "":
			problems.append("%s: brew '%s' has no Name" % [entry["where"], entry["id"]])

		for complaint in DialogueGrammar.complaints(String(entry["requires"]), false):
			problems.append("%s: Requires %s" % [entry["where"], complaint])

		# An ability that does not exist would silently do nothing.
		for column in ["attack", "defend"]:
			var ability_id := String(entry[column]).strip_edges()
			if ability_id != "" and cards.get_ability(ability_id) == null:
				problems.append("%s: %s Ability '%s' is not in Abilities.csv"
					% [entry["where"], column.capitalize(), ability_id])

		# A class nobody plays is almost always a typo.
		for column2 in ["for_class", "becomes"]:
			var class_name_text := String(entry[column2]).strip_edges()
			if class_name_text == "":
				continue
			var known := false
			for card in cards.players:
				if CardDatabase._normalise(card.unit_type) == CardDatabase._normalise(class_name_text):
					known = true
					break
			if not known:
				problems.append("%s: '%s' is not a class any card belongs to — check the spelling"
					% [entry["where"], class_name_text])

		if String(entry["becomes"]).strip_edges() == "" \
				and String(entry["attack"]).strip_edges() == "" \
				and String(entry["defend"]).strip_edges() == "":
			problems.append("%s: brew '%s' changes nothing — it has no Becomes and no abilities"
				% [entry["where"], entry["id"]])


func all_conditions() -> Array[String]:
	var out: Array[String] = []
	for entry in brews:
		var condition := String(entry["requires"])
		if condition.strip_edges() != "":
			out.append(condition)
	return out


func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()
