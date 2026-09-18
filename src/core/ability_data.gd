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
