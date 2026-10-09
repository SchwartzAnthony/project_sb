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
	var facts: Array[Dictionary] = []
	for item in chain:
		var card := item as PlayerData
		if card != null:
			facts.append(facts_of(card))
	return fired_from(facts, chain.size())


## What the combos add up to.
static func bonus_for(chain: Array) -> int:
	var total := 0
	for rule in fired(chain):
		total += int(rule["bonus"])
	return total


# =============================================================
#  THE SAME QUESTION, ASKED ABOUT ANYTHING
#
#  ============ WHY THERE ARE TWO WAYS IN ============
#
#  The enemies get a build-up window of their own now, and it shows THEIR
#  combos — three Water enemies in a wave is the same idea as three Water
#  players in your move, and the same row of Combos.csv ought to notice it.
#
#  An enemy is not a PlayerData, though. It is a row of AdventureEnemies.csv.
#  So the rules were moved off PlayerData and onto a FACT: the four things a
#  combo actually needs to know about one participant, and nothing else.
#
#      element   its element, or "" for none at all
#      class     its class or club. An enemy's Pool stands in for this
#      power     what it brings to the total
#      star      true only for a Star Player
#
#  Your cards become facts in fired(). The enemies become facts in
#  adventure_buildup.gd. ONE COMBOS.CSV THEN DECIDES BOTH SIDES, which is the
#  point of doing it this way — the enemy build-up is not a second system
#  with second rules, and a combo you write applies to whoever satisfies it.
# =============================================================

## One of your cards, as a fact.
static func facts_of(card: PlayerData) -> Dictionary:
	if card == null:
		return {"element": "", "class": "", "power": 0, "star": false}
	return {
		"element": card.element,
		# The BREWED class, so a card that drank a Water Brew combos with the
		# Lorelei she is standing next to. Same rule the rest of the
		# game's targeting uses.
		"class": card.active_unit_type(),
		"power": card.get_attack_power(),
		"star": card.is_star(),
	}


## Which combos a list of facts sets off, best first.
##
## `slots` is how many places there were to fill — four tiers on your side,
## however many enemies are in the wave on theirs. It is what `all_four`
## measures itself against.
static func fired_from(facts: Array, slots: int) -> Array[Dictionary]:
	var clean: Array[Dictionary] = []
	for item in facts:
		if item is Dictionary:
			clean.append(item)
	if clean.is_empty():
		return []

	var out: Array[Dictionary] = []
	for rule in get_db().rules:
		if _matches(rule, clean, slots):
			out.append(rule)

	out.sort_custom(func(a, b) -> bool:
		return int(a["bonus"]) > int(b["bonus"]))
	return out


## What those combos add up to.
static func bonus_from(facts: Array, slots: int) -> int:
	var total := 0
	for rule in fired_from(facts, slots):
		total += int(rule["bonus"])
	return total


static func _matches(rule: Dictionary, facts: Array, tiers: int) -> bool:
	var needs := maxi(1, int(rule["needs"]))

	match String(rule["when"]):
		"same_element":
			return _most_shared(facts, "element") >= needs
		"same_class":
			return _most_shared(facts, "class") >= needs
		"all_different_class":
			# NOBODY SHARES A CLUB. Written as its own shape rather than as
			# `same_class` with a small number, because "at least one" is
			# true of every move ever played and would fire constantly.
			# Your own side is one class, so this is the opposition's combo:
			# a scratch side is drawn from everywhere, and this is what it
			# gets for it.
			return facts.size() >= 2 and _most_shared(facts, "class") == 1
		"rising_power":
			if facts.size() < 2:
				return false
			for i in range(1, facts.size()):
				var before := int((facts[i - 1] as Dictionary).get("power", 0))
				var now := int((facts[i] as Dictionary).get("power", 0))
				if now <= before:
					return false
			return true
		"all_four":
			return facts.size() >= tiers and tiers > 0
		"star_last":
			var last: Dictionary = facts[facts.size() - 1]
			return bool(last.get("star", false))
	return false


## The biggest number of them sharing one element (or one class).
static func _most_shared(facts: Array, what: String) -> int:
	var counts: Dictionary = {}
	for item in facts:
		var fact := item as Dictionary
		if fact == null:
			continue
		var key := String(fact.get(what, "")).strip_edges().to_lower()
		# "None" IS NOT AN ELEMENT. A class that leaves the column blank, or
		# writes None in it, has no element — and without this line every one
		# of its players "shares" it and the element combos fire on every
		# move that class ever makes.
		if what == "element" and NOT_AN_ELEMENT.has(key):
			key = ""
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
