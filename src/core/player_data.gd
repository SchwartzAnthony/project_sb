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

## Optional. The "Attack Ability" / "Defend Ability" columns in your unit CSV,
## each naming a row in Abilities.csv. Blank means the card has no mechanical
## ability — attack_text / defend_text stay as the printed card text.
@export var attack_ability_id: String
@export var defend_ability_id: String

## Optional "Stamina" column in your unit CSV. ADVENTURE MODE ONLY — it has
## no effect in a league match, where the only thing with stamina is the
## keeper.
##
## Leave it blank (0) and the card's stamina is worked out from its power:
##   adventure_stamina_base + power * adventure_stamina_per_power
## both from Tuning.csv. Fill it in only to make one particular card tougher
## or more fragile than its power would suggest.
@export var adventure_stamina: int = 0

## Optional "Level" column in your unit CSV. THIS IS WHAT DECIDES WHO YOU
## PLAY AGAINST in a friendly — see team_level.gd.
##
## Think of it as "how far into the game is this card". A starter is a 1, a
## card you earn late is a 12. It is NOT the same thing as power: a Tier I
## 2-power card can be a level 10 card if it is rare and does something
## clever, and the tier ladder means its power is still a 2.
##
## Leave it blank (0) and the card's level is worked out from its tier and
## its power instead, which is a sensible guess and means you can ignore the
## column entirely until you want to use it. See PlayerData.get_level().
@export var level: int = 0

@export var artwork: Texture2D
## ROUND AC: true when `artwork` is a borrowed stand-in (placeholder_art in
## Tuning.csv) because this card has no drawing yet.
var art_is_stand_in := false


# =============================================================
#  THE OTHER SIDE OF A STAR
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "Star Players have their normal ability. The Ultimate form is their other
#   side when their Emblem condition is met. When hovered over them, show
#   their ultimate card side."
#
#  So a Star is a TWO-SIDED CARD and a normal unit is not. The columns live in
#  data/Star Players.csv:
#
#      Front Side        THE ONE ABILITY A STAR HAS. It fills both
#                        attack_text and defend_text, because a Star now has
#                        one ability rather than two — that is the change
#      Ultimate Side     what it becomes. Readable on hover at any time, and
#                        live once this Star's Emblem turns over
#      Ultimate Artwork  the other face of the card
#
#  ============ WHY THESE ARE ON EVERY CARD AND NOT ONLY ON STARS ============
#
#  Because PlayerData is one resource, and giving Stars a subclass of their
#  own would mean every screen asking "which kind is this?" before it could
#  draw anything. A normal unit leaves them empty, and `has_ultimate()` below
#  is the question anything actually asks.
# =============================================================

## The Star's other ability. Empty on a normal unit.
@export_multiline var ultimate_text: String
## The other face. Empty falls back to `artwork`, so a Star with one drawing
## still works — it just does not change when it turns over.
@export var ultimate_artwork: Texture2D
## Which row of `<Class> Emblems.csv` this Star carries onto the pitch.
## Blank means "the one with my name", which is the normal case.
@export var emblem_name: String = ""
## Which of the class's three sets of nine belongs to this Star — the units
## whose play can complete this Star's Emblem. Blank means "the set named
## after me".
@export var star_set: String = ""


## Has this card another side to turn over to?
func has_ultimate() -> bool:
	return ultimate_text.strip_edges() != ""


## The Emblem this Star brings onto the pitch. Falls back to its own name,
## which is how both Emblems files are written today.
func emblem_id() -> String:
	return emblem_name if emblem_name.strip_edges() != "" else player_name


## The set of nine this Star answers for. Falls back to its own name.
##
## THIS IS THE COLUMN THAT CLOSED THE OLD MISMATCH. The game used to assume a
## Star's name and its set's name were the same word, so Gremory — whose nine
## are the Sitri set — was reported as a problem on every run. They are two
## different questions and they now have two different answers.
func set_id() -> String:
	return star_set if star_set.strip_edges() != "" else player_name


# =============================================================
#  THE BREW OVERLAY
#
#  A brew from the Pub does NOT overwrite the card. It lays a thin overlay
#  on top of it, and the accessors below prefer the overlay when it is set.
#
#  Why an overlay and not a copy: the rest of the game recognises a card by
#  being the same object ("is this the unit holding the ball?"). Handing out
#  duplicates would break every one of those checks. And why not overwrite
#  unit_type directly: roster building asks "which cards are Lorelei?", and
#  a Lorelei who drank a Fire Brew must still be picked for a Lorelei team.
#
#  So `unit_type` stays what the card IS, and `active_unit_type()` is what
#  it currently COUNTS AS. Roster code uses the first; combat and targeting
#  use the second.
#
#  All of it is cleared and re-applied at the start of every match, so a
#  one-match brew genuinely lasts one match.
# =============================================================

## Which brew is on this card right now, or "" for none.
@export var brew_id: String = ""
@export var brew_unit_type: String = ""
@export var brew_attack_ability: String = ""
@export var brew_defend_ability: String = ""
@export var brew_artwork: Texture2D

## WHAT THEY COUNT AS AFTER DRINKING IT, out of the Element column of
## Brews.csv. Blank means the brew does not change their element.
##
## This is what makes Adventure's stack answer to the pub: a Lorelei who
## drinks a Fire Brew genuinely brings a Fire icon to the move, rather than
## only changing colour. See trait_db.gd.
@export var brew_element: String = ""


func is_brewed() -> bool:
	return brew_id.strip_edges() != ""


## What this card counts as for combat and ability targeting.
func active_unit_type() -> String:
	return brew_unit_type if brew_unit_type.strip_edges() != "" else unit_type


## What element this card counts as right now. Their own, unless they drank
## something with an Element column — the same shape as active_unit_type().
func active_element() -> String:
	return brew_element if brew_element.strip_edges() != "" else element


func active_attack_ability() -> String:
	return brew_attack_ability if brew_attack_ability.strip_edges() != "" else attack_ability_id


func active_defend_ability() -> String:
	return brew_defend_ability if brew_defend_ability.strip_edges() != "" else defend_ability_id


func active_artwork() -> Texture2D:
	return brew_artwork if brew_artwork != null else artwork


## Take the overlay off. Called before every match, then the current brews
## are laid on again from the save.
func clear_brew() -> void:
	brew_id = ""
	brew_unit_type = ""
	brew_attack_ability = ""
	brew_defend_ability = ""
	brew_element = ""
	brew_artwork = null


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


## HOW FAR INTO THE GAME THIS CARD IS. Used to decide who a friendly puts
## you against, and nothing else — it never touches a card's power, so the
## tier ladder is untouched by it.
##
## The Level column of your unit CSV if it has one. If it does not, a guess
## from the tier and the power:
##
##     Tier I   -> 1..3      Tier III -> 7..9
##     Tier II  -> 4..6      Tier IV  -> 10..12
##
## which is deliberately the ordinary shape of a roster, so a project that
## never fills the column still sorts into believable opponents. A Star is
## worth a little more than a regular of the same tier, because it is.
func get_level() -> int:
	if level > 0:
		return level
	var tier_index := get_tier_index()
	if tier_index < 0:
		tier_index = 0
	var guess := tier_index * 3 + 1 + mini(get_attack_power(), 2)
	if is_star():
		guess += 1
	return guess


# --- Ability targeting tags ---------------------------------
# Card text like "give all Fire players +1 power" matches against these.
func get_tags() -> PackedStringArray:
	var tags := PackedStringArray()
	if element.strip_edges() != "":
		tags.append(element.strip_edges().to_lower())
	# The BREWED class, so "give all Brandteufel +1" reaches a Lorelei who
	# drank a Fire Brew. That is the whole point of the brew.
	var current := active_unit_type()
	if current.strip_edges() != "":
		tags.append(current.strip_edges().to_lower())
	if get_tier_clean() != "":
		tags.append("tier" + get_tier_clean().to_lower())
	if is_star():
		tags.append("star")
	else:
		tags.append("normal")
	tags.append_array(extra_tags)
	return tags


## ROUND Z - WHAT A TOKEN IS. A Rose or Swan Unit token is a fresh copy of
## the card it replaced, made by the ability engine during a match, and these
## are the words that say so: ["rose", "token"]. Never saved, never on a card
## you own - an ordinary card always has none.
var extra_tags: PackedStringArray = PackedStringArray()


func is_token() -> bool:
	return extra_tags.has("token")


func has_tag(tag: String) -> bool:
	return get_tags().has(tag.strip_edges().to_lower())
