class_name PlayerData
extends Resource

# =============================================================
#  PLAYER CARD DATA
#  One .tres per card, generated from CSV by csv_importer.gd
# =============================================================

@export var formation_scene: PackedScene
@export var player_type: String = "Normal" # "Normal" or "Star"
@export var unit_type: String              # class / race, e.g. "Brandteufel"
@export var player_name: String
@export_multiline var attack_text: String
@export_multiline var defend_text: String
@export var element: String                # targeting tag, e.g. "Fire"
@export var base_power_left: int           # ATTACK power  (the 0-5 number)
@export var base_power_right: int          # DEFENSE power (mirror of left for now)
@export var tier: String                   # "I" / "II" / "III" / "IV"
@export var stufe: String
@export var tool: String
@export var card_number: int
@export var card_date: int
@export var card_set: String   # the "Set Name" CSV column, e.g. "F01"
@export var created_by: String

@export var artwork: Texture2D


# --- Backwards compatibility --------------------------------
# The 24 existing .tres files write `set_name = "F01"`. We CANNOT declare a
# member called `set_name`, because Resource already has a set_name() method
# (the setter for `resource_name`) and shadowing it breaks the engine's own
# calls. So the field is `card_set`, and we intercept the old key on load.
# Re-saving a card through the importer writes `card_set` and this goes quiet.

func _set(property: StringName, value: Variant) -> bool:
	if property == &"set_name":
		card_set = str(value)
		return true
	return false


# --- Power ---------------------------------------------------
# Right now attack and defense are the same number. Everything in the
# combat code goes through these two functions, so the day you want a
# class with 4 attack / 2 defense you only change the CSV.

func get_attack_power() -> int:
	return base_power_left


func get_defense_power() -> int:
	# No "> 0 else left" fallback here: 0 is a LEGAL power (Tier I is 0/1/2),
	# and Godot omits a property from a .tres when it equals the default, so
	# a real 0 and an unset value look identical. Trust the column.
	return base_power_right


# --- Ability priority ---------------------------------------
# The same number is the ability priority. LOWER resolves FIRST.
func get_ability_priority() -> int:
	return base_power_left


# --- Tier helpers -------------------------------------------
const TIER_ORDER: Array[String] = ["I", "II", "III", "IV"]

func get_tier_clean() -> String:
	return tier.strip_edges().to_upper()


func get_tier_index() -> int:
	# "I" -> 0, "II" -> 1, "III" -> 2, "IV" -> 3, unknown -> -1
	return TIER_ORDER.find(get_tier_clean())


func is_star() -> bool:
	return player_type.to_lower().contains("star")


# --- Ability targeting tags ---------------------------------
# Card text like "give all Fire players +1 power" matches against these.
func get_tags() -> PackedStringArray:
	var tags := PackedStringArray()
	if element.strip_edges() != "":
		tags.append(element.strip_edges().to_lower())
	if unit_type.strip_edges() != "":
		tags.append(unit_type.strip_edges().to_lower())
	if get_tier_clean() != "":
		tags.append("tier" + get_tier_clean().to_lower())
	if is_star():
		tags.append("star")
	else:
		tags.append("normal")
	return tags


func has_tag(tag: String) -> bool:
	return get_tags().has(tag.strip_edges().to_lower())
