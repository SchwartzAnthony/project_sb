class_name ComboDB
extends RefCounted

# =============================================================
#  COMBOS — what the passing move is worth on top of the players
#
#  A round in an Adventure fight is a move: Tier I passes to Tier II passes
#  to Tier III passes to Tier IV, and the last one shoots. The four powers
#  add up. THIS FILE IS THE BIT ON TOP — what the move itself was worth,
#  because of who was in it.
#
#  ============ res://data/Combos.csv ============
#
#      ID           yours
#      Name         what the build-up window calls it when it fires
#      When         the shape it looks for. The list is below
#      Needs        how many it takes, for the ones that count
#      Bonus        what it adds to the shot
#      Description  yours, shown in the window
#
#  THE SHAPES, and all of them are worked out from the chain you drafted:
#
#      same_element         Needs players sharing one element
#      same_class           Needs players of one class
#      all_different_class  no two share a class. Needs is ignored
#      rising_power         every player stronger than the one before
#      all_four             all four tiers had somebody
#      star_last            a Star Player takes the shot
#
#  Add a row, get a combo. Delete every row and combos simply do not exist
#  and the move is worth exactly the four powers — which is a perfectly
#  reasonable game and is what you had before this file.
#
#  ============ WHY IT IS NOT POWER ============
#
#  A combo adds to the SHOT, never to a card. A 2-power Tier I card is a 2
#  whatever move it is in. That is the same rule the season's Difficulty
#  obeys, and for the same reason: the tier ladder has to mean one thing
#  everywhere or it means nothing.
# =============================================================

const PATH := "res://data/Combos.csv"

static var _instance: ComboDB

## Each: {"id", "name", "when", "needs", "bonus", "description"}
var rules: Array[Dictionary] = []
var problems: Array[String] = []

## Words in an Element column that mean "this card has no element". Add to
## the list if your spreadsheets say it another way.
const NOT_AN_ELEMENT: Array[String] = ["none", "-", "n/a", "na", "neutral"]

const SHAPES: Array[String] = [
	"same_element", "same_class", "all_different_class",
	"rising_power", "all_four", "star_last",
]


static func get_db() -> ComboDB:
	if _instance == null:
		_instance = ComboDB.new()
		_instance.load_all()
	return _instance


static func reload() -> void:
	_instance = null
	get_db()


func load_all() -> void:
	rules.clear()
	problems.clear()

	for row in MenuSupport.read_csv(PATH):
		var id_text := MenuSupport.field(row, "ID")
		if id_text == "":
			continue
		var shape := MenuSupport.field(row, "When").strip_edges().to_lower()
		if not SHAPES.has(shape):
			problems.append("Combos.csv row '%s' says When = '%s', which is not one of: %s"
				% [id_text, shape, ", ".join(SHAPES)])
			continue
		rules.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text),
			"when": shape,
			"needs": int(MenuSupport.field_float(row, "Needs", 0.0)),
			"bonus": int(MenuSupport.field_float(row, "Bonus", 0.0)),
			"description": MenuSupport.field(row, "Description"),
		})

	for note in problems:
		push_warning("[combos] " + note)
	print("[combos] %d combo(s) loaded." % rules.size())


# =============================================================
#  WORKING THEM OUT
# =============================================================

## Which combos a chain sets off. `chain` is the cards you drafted, weakest
## tier first, with nulls for tiers that had nobody.
##
## Returns the rows that fired, best first, so a window can list them.
static func fired(chain: Array) -> Array[Dictionary]:
	var players: Array[PlayerData] = []
	for item in chain:
		var card := item as PlayerData
		if card != null:
			players.append(card)
	if players.is_empty():
		return []

	var out: Array[Dictionary] = []
	for rule in get_db().rules:
		if _matches(rule, players, chain.size()):
			out.append(rule)

	out.sort_custom(func(a, b) -> bool:
		return int(a["bonus"]) > int(b["bonus"]))
	return out


## What the combos add up to.
static func bonus_for(chain: Array) -> int:
	var total := 0
	for rule in fired(chain):
		total += int(rule["bonus"])
	return total


static func _matches(rule: Dictionary, players: Array, tiers: int) -> bool:
	var needs := maxi(1, int(rule["needs"]))

	match String(rule["when"]):
		"same_element":
			return _most_shared(players, "element") >= needs
		"same_class":
			return _most_shared(players, "class") >= needs
		"all_different_class":
			# NOBODY SHARES A CLUB. Written as its own shape rather than as
			# `same_class` with a small number, because "at least one" is
			# true of every move ever played and would fire constantly.
			# Your own side is one class, so this is the opposition's combo:
			# a scratch side is drawn from everywhere, and this is what it
			# gets for it.
			return players.size() >= 2 and _most_shared(players, "class") == 1
		"rising_power":
			if players.size() < 2:
				return false
			for i in range(1, players.size()):
				var before := (players[i - 1] as PlayerData).get_attack_power()
				var now := (players[i] as PlayerData).get_attack_power()
				if now <= before:
					return false
			return true
		"all_four":
			return players.size() >= tiers and tiers > 0
		"star_last":
			var last := players[players.size() - 1] as PlayerData
			return last != null and last.is_star()
	return false


## The biggest number of players sharing one element (or one class).
static func _most_shared(players: Array, what: String) -> int:
	var counts: Dictionary = {}
	for item in players:
		var card := item as PlayerData
		if card == null:
			continue
		var key := ""
		if what == "element":
			key = card.element.strip_edges().to_lower()
			# "None" IS NOT AN ELEMENT. A class that leaves the column blank,
			# or writes None in it, has no element — and without this line
			# every one of its players "shares" it and the element combos
			# fire on every move that class ever makes.
			if NOT_AN_ELEMENT.has(key):
				key = ""
		else:
			# The BREWED class, so a Lorelei who drank a Fire Brew combos
			# with the Brandteufel she is standing next to. Same rule the
			# rest of the game's targeting uses.
			key = card.active_unit_type().strip_edges().to_lower()
		if key == "":
			continue
		counts[key] = int(counts.get(key, 0)) + 1

	var most := 0
	for key in counts.keys():
		most = maxi(most, int(counts[key]))
	return most


## A line for the build-up window: "Linked  +1".
static func describe(rule: Dictionary) -> String:
	return "%s  +%d" % [rule.get("name", "Combo"), int(rule.get("bonus", 0))]
