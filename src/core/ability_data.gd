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

const TRIGGERS: Array[String] = [
	"onattack",     # this unit is the attacker in its duel
	"ondefend",     # this unit is the defender in its duel
	"onduelstart",  # either way, when its duel begins
	"onwinduel",    # after it wins its duel
	"onloseduel",   # after it loses its duel
	"passive",      # applied once at the start of every round
]

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
	if not TRIGGERS.has(trigger):
		return "Trigger '%s' is not one of: %s" % [trigger, ", ".join(TRIGGERS)]
	if not EFFECTS.has(effect):
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
