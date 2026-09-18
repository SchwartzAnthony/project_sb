class_name AbilityData
extends RefCounted

# =============================================================
#  ONE ROW OF Abilities.csv
#
#  An ability is five answers:
#     TRIGGER  when does it go off?
#     TARGET   who does it hit?
#     EFFECT   what does it do?
#     VALUE    how much?
#     SCOPE    how long does it last?
#
#  Every one of those is a word from a fixed list (below). Adding a card
#  that reuses existing words needs no code at all. Only inventing a
#  brand-new EFFECT needs a code change — see ability_engine.gd.
# =============================================================

# ============ THE TRIGGERS ARE A SPREADSHEET NOW ============
#
# `data/AbilityTriggers.csv` is the list, and it is also the place you keep
# track of the ones that are not built yet — every row has a Status of `live`
# or `planned`. Writing a new trigger is a row there plus, usually, one place
# in the game that calls fire_for() with its name.
#
# The list below is the FALLBACK, used when that file is missing or has not
# loaded yet. It is the six the engine has always had, so a project with no
# AbilityTriggers.csv behaves exactly as it did before.
const TRIGGERS: Array[String] = [
	"onattack",     # this unit is the attacker in its duel
	"ondefend",     # this unit is the defender in its duel
	"onduelstart",  # either way, when its duel begins
	"onwinduel",    # after it wins its duel
	"onloseduel",   # after it loses its duel
	"passive",      # applied once at the start of every round
	"flip",         # the two cards are turned face up
]

## Every trigger the game knows, live or planned, normalised. Read once from
## AbilityTriggers.csv and remembered.
static var _known: Array[String] = []
## id -> the row, for anything that wants to explain itself.
static var _rows: Dictionary = {}


## THE LIST, out of AbilityTriggers.csv. Falls back to TRIGGERS above.
static func known_triggers() -> Array[String]:
	if not _known.is_empty():
		return _known
	for row in MenuSupport.read_csv("res://data/AbilityTriggers.csv"):
		var id_text := CardDatabase._normalise(MenuSupport.field(row, "ID"))
		if id_text == "":
			continue
		_known.append(id_text)
		_rows[id_text] = row
	if _known.is_empty():
		_known = TRIGGERS.duplicate()
	return _known


## Is this trigger one somebody has actually wired up? A `planned` row is a
## legal thing to write in Abilities.csv — it simply never fires yet, and the
## loader says so once rather than calling the row an error.
static func trigger_is_live(trigger: String) -> bool:
	known_triggers()
	var row: Dictionary = _rows.get(CardDatabase._normalise(trigger), {})
	if row.is_empty():
		return TRIGGERS.has(CardDatabase._normalise(trigger))
	return MenuSupport.field(row, "Status").strip_edges().to_lower() == "live"


## Forget the list, so a reload picks the spreadsheet up again.
static func forget_triggers() -> void:
	_known = []
	_rows = {}
	_keywords = {}


# ============ KEYWORDS.CSV ============
#
# One row per word the game understands, in every family: effects, targets,
# scopes, condition words, Adventure effects, item tags. It is the reference
# you read and the place you write a NEW word down so it can be built.
#
# Nothing here decides what a live word does — the code does that. What this
# gives you is the difference between "not built yet" and "typo", which is
# the difference between a card that waits and a card that is wrong.
static var _keywords: Dictionary = {}


## family -> {normalised keyword -> Status}
static func _load_keywords() -> void:
	if not _keywords.is_empty():
		return
	for row in MenuSupport.read_csv("res://data/Keywords.csv"):
		var word := CardDatabase._normalise(MenuSupport.field(row, "Keyword"))
		var family := MenuSupport.field(row, "Family").strip_edges().to_lower()
		if word == "" or family == "":
			continue
		if not _keywords.has(family):
			_keywords[family] = {}
		(_keywords[family] as Dictionary)[word] = \
			MenuSupport.field(row, "Status").strip_edges().to_lower()
	if _keywords.is_empty():
		# No file: nothing is planned, so everything unknown stays an error.
		_keywords["_none"] = {}


static func _keyword_is_planned(word: String, family: String) -> bool:
	_load_keywords()
	var in_family: Dictionary = _keywords.get(family, {})
	return String(in_family.get(CardDatabase._normalise(word), "")) == "planned"

const TARGETS_SIMPLE: Array[String] = [
	"self",
	"opponent",       # the unit it is duelling
	"allallies",      # every unit on its own side
	"allenemies",     # every unit on the other side
	"enemygoalie",    # the keeper it would shoot at
	"owngoalie",      # its own keeper
]
# Also accepted, with a colon:
#   tag:<tag>    e.g. tag:brandteufel, tag:fire, tag:star  (see PlayerData.get_tags)
#   tier:<tier>  e.g. tier:III  — allies in that tier
#   enemytier:<tier>

const EFFECTS: Array[String] = [
	"addattack",      # +value to attack power
	"adddefense",     # +value to defense power
	"addpower",       # +value to both
	"addshotpower",   # +value to this round's shot if its side takes the shot
	"drainstamina",   # -value stamina from the targeted goalie
	"restorestamina", # +value stamina to the targeted goalie
]

const SCOPES: Array[String] = ["duel", "round", "cycle", "match"]

var id: String = ""
var display_name: String = ""
var trigger: String = ""
var target: String = ""
var effect: String = ""
var value: int = 0
var scope: String = "duel"
var notes: String = ""


## Returns "" when the row is usable, otherwise a plain-English complaint
## that CardDatabase prints for you.
func validate() -> String:
	var triggers := known_triggers()
	if not triggers.has(trigger):
		return "Trigger '%s' is not one of: %s" % [trigger, ", ".join(triggers)]
	if not trigger_is_live(trigger):
		# NOT AN ERROR. A trigger marked `planned` in AbilityTriggers.csv is
		# one you have designed and nobody has wired up yet — so the card is
		# legal, loads, and simply never goes off. Saying so once is more use
		# than refusing the row.
		print("[abilities] '%s' waits on the '%s' trigger, which is still marked planned in AbilityTriggers.csv."
			% [display_name if display_name != "" else id, trigger])
	if not EFFECTS.has(effect):
		# ============ A PLANNED EFFECT IS NOT AN ERROR ============
		#
		# Keywords.csv is the list of every word the game understands, and a
		# row marked `planned` there is one you have designed and nobody has
		# written yet. Same rule as a planned trigger: the card loads, the row
		# is legal, it simply never does anything until the effect is built.
		#
		# A word that is in NEITHER list is a typo, and that is still refused.
		if _keyword_is_planned(effect, "ability effect"):
			print("[abilities] '%s' waits on the '%s' effect, which is still marked planned in Keywords.csv."
				% [display_name if display_name != "" else id, effect])
		else:
			return "Effect '%s' is not one of: %s" % [effect, ", ".join(EFFECTS)]
	if not SCOPES.has(scope):
		if scope == "":
			scope = "duel"
		else:
			return "Scope '%s' is not one of: %s" % [scope, ", ".join(SCOPES)]
	if not _target_is_known():
		return "Target '%s' is not recognised" % target
	if value == 0:
		return "Value is 0, so this ability would do nothing"
	return ""


func _target_is_known() -> bool:
	var flat := CardDatabase._normalise(target)
	if TARGETS_SIMPLE.has(flat):
		return true
	return target.begins_with("tag:") or target.begins_with("tier:") or target.begins_with("enemytier:")


func hits_goalie() -> bool:
	var flat := CardDatabase._normalise(target)
	return flat == "enemygoalie" or flat == "owngoalie"


func describe() -> String:
	return "%s: %s %s %+d to %s (%s)" % [id, trigger, effect, value, target, scope]


## ============ THE SAME ROW, IN ENGLISH ============
##
## describe() is for the Output panel and reads like a database row.
## This is for a player looking at the enemy's squad, and it has to read like
## a sentence — "When it wins its duel: +1 attack to itself, for the round."
##
## Every word comes from the row, so an ability written tomorrow explains
## itself here with nothing to keep in step.
func plain() -> String:
	return "%s: %s%s." % [_when_words(), _what_words(), _how_long_words()]


func _when_words() -> String:
	match trigger:
		"onattack": return "When attacking"
		"ondefend": return "When defending"
		"onduelstart": return "When its duel begins"
		"onwinduel": return "When it wins its duel"
		"onloseduel": return "When it loses its duel"
		"flip": return "When the cards are turned over"
		"passive": return "Always"
	# A trigger from AbilityTriggers.csv that has no sentence written for it
	# yet reads as itself rather than as nothing.
	return "On %s" % trigger


func _what_words() -> String:
	var who := _who_words()
	match effect:
		"addattack": return "%+d attack to %s" % [value, who]
		"adddefense": return "%+d defence to %s" % [value, who]
		"addpower": return "%+d attack and defence to %s" % [value, who]
		"addshotpower": return "%+d on the shot at goal" % value
		"drainstamina": return "%d stamina off %s" % [value, who]
		"restorestamina": return "%d stamina back to %s" % [value, who]
	return "%s %+d to %s" % [effect, value, who]


func _who_words() -> String:
	# MATCHED ON THE FLATTENED WORD. The Target column is written the way it
	# reads in a spreadsheet — `enemy_goalie`, `all_allies` — and matching the
	# raw text let every underscored one fall through to the bottom of this
	# function and be printed as the id, which is the thing this whole function
	# exists to avoid.
	var flat := CardDatabase._normalise(target)
	match flat:
		"self": return "itself"
		"opponent": return "the player it is up against"
		"allallies": return "its whole side"
		"allenemies": return "the whole other side"
		"enemygoalie": return "the keeper it shoots at"
		"owngoalie": return "its own keeper"
	if target.begins_with("tag:"):
		return "every %s on its side" % target.substr(4)
	if target.begins_with("tier:"):
		return "its own Tier %s" % target.substr(5).to_upper()
	if target.begins_with("enemytier:") or target.begins_with("enemy_tier:"):
		return "their Tier %s" % target.split(":")[-1].to_upper()
	return target.replace("_", " ")


func _how_long_words() -> String:
	match scope:
		"duel": return ", for this duel"
		"round": return ", for the round"
		"cycle": return ", for the cycle"
		"match": return ", for the rest of the match"
	return ""
