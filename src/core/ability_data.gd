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
		# The word BEFORE any colon: "has_counter:<kind>" is the word
		# has_counter, whatever kind a card later writes after it.
		var word := CardDatabase._normalise(MenuSupport.field(row, "Keyword").split(":")[0])
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
	"addcardchance",  # +value % that a foul the OTHER side commits, once the
	                  # referee has seen it, is a yellow and not a free kick
	                  # (round X - your Bergmännlein ore card)
	# ---- ROUND Z, PHASE C2: counters, the Ore pool, tokens, swans ----
	"addcounter",     # add_counter:burn  - value counters of that kind on the
	                  # target card (add_counter:power -1 = a -1 POWER COUNTER,
	                  # which changes its power for the rest of the match).
	                  # Target `side` puts them on your SIDE instead (victory).
	"removecounter",  # remove_counter[:kind] - takes value counters off
	"gainore",        # +value Ore into your side's pool (ruling R12)
	"createtoken",    # create_token:rose - a Rose (or Swan) Unit token takes a
	                  # card's place; the card goes to the exhaust and stays
	"makeswan",       # the target becomes a Swan creature type for the match
	# ---- ROUND AA, PHASE C3: the keeper and the referee ----
	"goaliechance",   # +value PERCENTAGE POINTS on the chance that keeper is
	                  # beaten (ruling R02: the %, never the stamina). -100 =
	                  # he cannot be beaten. Scope round or match.
	"goalieshield",   # +value shield on that keeper: a second bar that empties
	                  # BEFORE his stamina (ruling R11)
	"removeshields",  # every shield off that keeper
	"foulheat",       # +value SEGMENTS of the referee's bar against that side
	                  # (ruling R09)
	"foulchance",     # +value % that side commits a foul (ruling R10, R16).
	                  # Scope round or match
	"foulcoinflip",   # the next foul YOUR side commits: a coin decides
	                  # whether it is yours or theirs (Manfred)
	# ---- ROUND AB, PHASE C4: bending the duel ----
	"switchtodefender",   # after the abilities, this card DEFENDS instead (F1, Q047)
	"alwaysdefending",    # counts as defending for every If, all match (Sallos)
	"swappower",          # this card and its target swap PRINTED power (Q052);
	                      # target `token` = this card takes a token's power
	"setpowerfromtoken",  # the target fights with the power of a token you own (Sven, Q002)
	"useenemypower",      # this card fights with the enemy's power (Nicole)
	"forceability",       # force_ability:attack / :defend / :other - the side it must use
	"negateability",      # the side the target is using does nothing more this duel
	"negatebuff",         # the target loses its power buffs this duel
	"changepriority",     # +/- value on its place in the order abilities resolve
	"givepriority",       # it resolves FIRST this duel
	"uncounterable",      # cannot be negated or forced this duel (Herbert)
	"powerfromcount",     # power_from_count:victory - its power IS that number
	"removecondition",    # its If is ignored this duel (Leon)
	# ---- ROUND AC, PHASE C5: the zones in action ----
	"swapintier",         # the marker on an `exhaust_swap` row: this card can be
	                      # swapped in from the exhaust for your card of its tier,
	                      # just before that duel (ruling R17). The swap itself is
	                      # offered by the match; the other rows on the card are
	                      # what it does once it is in.
	"sendtoexhaust",      # the target goes to the exhaust zone now
	"swapfromexhaust",    # after its next duel the target goes to the exhaust and a
	                      # card of the same tier comes back from it (Lothar)
	"exhaustotherreturn", # another of your cards of its tier goes to the exhaust and
	                      # this one comes back to be played again (Jan, Silke)
	"revealanother",      # your next card picked this round is revealed too (Ingrid)
	"revealfromexhaust",  # reveal a card from your exhaust; `revealed_was:fire` in an
	                      # If then asks what it was (Flauros)
	"doubleattack",       # its PRINTED power doubled (capped) for that duel, buffs
	                      # after (Lothar, Q051)
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
## THE "(Max 5)" ON YOUR CARDS. How many times this ability may go off for
## one card in one match. 0 or blank = no limit, which is every row written
## before round X.
var max_uses: int = 0
## Round Y: what the Max counts over - "match" (a plain number, as before),
## "cycle" (`1/cycle`, "once per cycle") or "game" (`1/game`, the same as a
## match). Read from the same Max cell.
var max_per: String = "match"
## ROUND Y - THE `If` COLUMN. Words that must ALL be true (semicolons
## between them) for the ability to go off. Blank = always. See CONDITIONS.
var condition: String = ""

## ROUND Z - THE WORD AFTER THE COLON in the Effect cell: `add_counter:burn`
## is effect addcounter with effect_arg "burn". Blank for most effects.
var effect_arg: String = ""
## ROUND Z - THE Cost COLUMN. `ore:3` = spend three Ore from your side's pool
## BEFORE it goes off. Not enough Ore and it simply does not happen - it is
## not counted, not spent against its Max. Blank = free.
var cost_kind: String = ""
var cost_amount: int = 0
## ROUND Z - a Max that counts for the whole SIDE rather than for one card:
## `2/cycle/side` (Belphegor's "only two per cycle").
var max_shared: bool = false
## ROUND AA - THE Ask COLUMN. `yes` = the player is asked before it goes off
## ("you CAN transform" - Zepar). A row with a Cost is asked anyway, while
## `ask_before_spending_ore` is on in Tuning.csv. The other side, and AUTO,
## always say yes.
var ask: bool = false

# ============ THE CONDITION WORDS (round Y, phase C1) ============
#
# What may go in the If column today. A word written in Keywords.csv as an
# `ability condition` with Status `planned` is legal too - the card loads and
# the condition is simply FALSE until the word is built, and the Output
# panel says so once. Anything else is a typo and the row is refused.
#
#     defending / attacking      this card's role in its duel
#     won / lost                 how its duel went (after the outcome)
#     last_ally_won              your previous card to duel won / lost
#     last_ally_lost
#     enemy_element:air          the card it is facing is / is not that
#     enemy_not_element:air      element
#     own_goalie_lower           your keeper has less stamina than theirs
#     enemy_below_base           the enemy's power now is below its printed power
#     in_exhaust / in_field      which zone this card is in
#     in_combat
#     has_tag:swan               the card carries that tag (see PlayerData)
#
#   ROUND Z - PHASE C2:
#     has_counter / has_counter:burn        this card carries a counter (of that kind)
#     enemy_has_counter[:kind]              the card it is facing does
#     has_token / tokens_at_least:4         your side controls a token / at least n
#     is_swan / is_token                    this card is a Swan / a token
#     ore_this_round                        your side gained Ore this round
#     ore_at_least:3                        your pool holds at least n Ore
#     element:water                         THIS card is that element
#     exhausted_this_round:2:water          at least n of your cards (of that
#                                           kind) went to the exhaust this round
const CONDITIONS: Array[String] = [
	"defending", "attacking", "won", "lost", "lastallywon", "lastallylost",
	"enemyelement", "enemynotelement", "owngoalielower", "enemybelowbase",
	"inexhaust", "infield", "incombat", "hastag",
	"hascounter", "enemyhascounter", "hastoken", "tokensatleast", "isswan", "istoken",
	"orethisround", "oreatleast", "element", "exhaustedthisround",
	# ROUND AC (C5)
	"swappedwas", "revealedwas",
]


## The condition words of one If cell, split and flattened: "has_tag:swan"
## -> ["hastag", "swan"] pairs.
static func condition_terms(text: String) -> Array:
	var out: Array = []
	for piece in text.split(";"):
		var clean := String(piece).strip_edges()
		if clean == "":
			continue
		var bits := clean.split(":", true, 1)
		var negate := clean.begins_with("!")
		var word := CardDatabase._normalise(String(bits[0]).trim_prefix("!"))
		out.append({"word": word, "arg": String(bits[1]).strip_edges().to_lower() if bits.size() > 1 else "",
			"not": negate, "raw": clean})
	return out


static func condition_is_live(word: String) -> bool:
	return CONDITIONS.has(word)


static func condition_is_planned(word: String) -> bool:
	return _keyword_is_planned(word, "ability condition")


# ============ THE NEW TARGETS (round Y, phase C1) ============
#
#     next_self                this card, in its NEXT duel
#     next_ally                your next card to duel
#     next_ally:fire           ...that is fire (an element, a class, a tier
#     next_ally:water+II       like II, or a tag - joined with +)
#     next_ally*2:unkengeister the next TWO
#     next_enemy               their next card to duel
#     ally:water+I             your card in that tier THIS round
#     next_tier_ally:fire      ROUND Z, ruling R03: the VERY NEXT card of yours
#                              to duel. If it is not fire, the effect is lost -
#                              it does not wait for a fire card further on.
#
# "Next" waits until that card duels - later this round, or in a later round
# (ruling R03). It never runs out on its own.
static func parse_next(target_text: String) -> Dictionary:
	var flat := target_text.strip_edges().to_lower()
	var head := flat.split(":", true, 1)[0]
	var filter := flat.split(":", true, 1)[1] if flat.contains(":") else ""
	var count := 1
	if head.contains("*"):
		var parts := head.split("*")
		head = parts[0]
		if String(parts[1]).is_valid_int():
			count = maxi(1, int(String(parts[1])))
	if not (head in ["next_self", "next_ally", "next_tier_ally", "next_enemy", "ally"]):
		return {}
	return {"kind": head, "count": count, "filter": filter}


## Does this card match a filter like "water+II" or "fire" or "swan"?
## Each piece must match: an element, a class, a tier, or a tag.
static func card_matches(card: PlayerData, filter: String) -> bool:
	if card == null:
		return false
	for piece in filter.split("+"):
		var want := String(piece).strip_edges().to_lower()
		if want == "":
			continue
		if want in ["i", "ii", "iii", "iv"]:
			if card.get_tier_clean() != want.to_upper():
				return false
			continue
		if CardDatabase._normalise(card.active_element()) == CardDatabase._normalise(want):
			continue
		if CardDatabase._normalise(card.active_unit_type()) == CardDatabase._normalise(want):
			continue
		if card.has_tag(want):
			continue
		return false
	return true


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
	if cost_kind != "" and cost_kind != "ore":
		return "Cost '%s' is not one the game knows (today: ore:N)" % cost_kind
	if not _target_is_known():
		return "Target '%s' is not recognised" % target
	if value == 0:
		return "Value is 0, so this ability would do nothing"
	for term in condition_terms(condition):
		var word := String(term["word"])
		if condition_is_live(word):
			continue
		if condition_is_planned(word):
			print("[abilities] '%s' waits on the '%s' condition, which is still marked planned in Keywords.csv - until then it is never true."
				% [display_name if display_name != "" else id, term["raw"]])
			continue
		return "If '%s' is not a condition the game knows (see Keywords.csv, family 'ability condition')" % term["raw"]
	return ""


func _target_is_known() -> bool:
	var flat := CardDatabase._normalise(target)
	if TARGETS_SIMPLE.has(flat) or flat == "side" or flat == "token":
		return true
	if target.begins_with("replace:") or target.begins_with("enemy_tier:"):
		return true
	if not parse_next(target).is_empty():
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
	var pay := ("pay %d Ore, then " % cost_amount) if cost_kind == "ore" else ""
	var only := ""
	if condition.strip_edges() != "":
		only = " if %s" % condition_words()
	return "%s%s: %s%s%s." % [_when_words(), only, pay, _what_words(), _how_long_words()]


## ROUND AA: the If column in words - "it has a burn counter and you control
## a token". So the duel window can say what an ability is waiting for.
func condition_words() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for term in condition_terms(condition):
		var arg := String(term["arg"])
		var w := String(term["word"])
		var said := ""
		match w:
			"defending": said = "it is defending"
			"attacking": said = "it is attacking"
			"won": said = "it won"
			"lost": said = "it lost"
			"lastallywon": said = "your last unit won"
			"lastallylost": said = "your last unit lost"
			"enemyelement": said = "the enemy is %s" % arg
			"enemynotelement": said = "the enemy is not %s" % arg
			"owngoalielower": said = "your keeper has less stamina"
			"enemybelowbase": said = "the enemy is below its printed power"
			"inexhaust": said = "it is in the exhaust"
			"infield": said = "it is on the field"
			"incombat": said = "it is in combat"
			"hastag": said = "it is %s" % arg
			"hascounter": said = ("it has a %s counter" % arg) if arg != "" else "it has a counter"
			"enemyhascounter": said = ("the enemy has a %s counter" % arg) if arg != "" else "the enemy has a counter"
			"hastoken": said = "you control a token"
			"tokensatleast": said = "you control %s tokens" % arg
			"isswan": said = "it is a Swan"
			"istoken": said = "it is a token"
			"orethisround": said = "you gained Ore this round"
			"oreatleast": said = "you have %s Ore" % arg
			"element": said = "it is %s" % arg
			"exhaustedthisround": said = "%s units went to the exhaust this round" % arg.replace(":", " ")
			"swappedwas": said = "the unit it swapped with was %s" % arg
			"revealedwas": said = "the card it revealed was %s" % arg
			_: said = String(term["raw"])
		if bool(term["not"]):
			said = "NOT " + said
		parts.append(said)
	return " and ".join(parts)


func _when_words() -> String:
	match trigger:
		"onattack": return "When attacking"
		"ondefend": return "When defending"
		"onduelstart": return "When its duel begins"
		"onwinduel": return "When it wins its duel"
		"oncounter": return "When it receives a counter"
		"whileinexhaust": return "While in the exhaust, each duel"
		"endofcycle": return "At the end of the cycle"
		"aftercombat": return "After the combat"
		"goaliesave": return "When your keeper saves"
		"onshot": return "When shooting"
		"contemplation": return "When it goes to the exhaust"
		"rejuvenation": return "When it leaves the exhaust"
		"reveal": return "When it is revealed"
		"onloseduel": return "When it loses its duel"
		"flip": return "When the cards are turned over"
		"passive": return "Always"
		"exhaustswap": return "From the exhaust, before a duel of its tier: it can swap in, and then"
	# A trigger from AbilityTriggers.csv that has no sentence written for it
	# yet reads as itself rather than as nothing.
	return "On %s" % trigger


func _what_words() -> String:
	var who := _who_words()
	# A keeper effect WAITING for a card: it lands when that card duels.
	if effect in ["drainstamina", "restorestamina"] and not parse_next(target).is_empty():
		var keeper := "their keeper" if effect == "drainstamina" else "your keeper"
		var verb := "duel" if int(parse_next(target)["count"]) > 1 else "duels"
		return "when %s %s, %d stamina %s %s" % [who, verb, value,
			"off" if effect == "drainstamina" else "back to", keeper]
	match effect:
		"addattack": return "%+d attack to %s" % [value, who]
		"adddefense": return "%+d defence to %s" % [value, who]
		"addpower": return "%+d attack and defence to %s" % [value, who]
		"addshotpower": return "%+d on the shot at goal" % value
		"drainstamina": return "%d stamina off %s" % [value, who]
		"restorestamina": return "%d stamina back to %s" % [value, who]
		"addcounter": return "%+d %s counter on %s" % [value, effect_arg, who]
		"removecounter": return "remove %d counter(s) from %s" % [value, who]
		"gainore": return "+%d Ore for your side" % value
		"createtoken": return "a %s Unit token takes the place of %s" % [effect_arg.capitalize(), who]
		"makeswan": return "%s becomes a Swan" % who
		"goaliechance": return "%+d%% to beat %s" % [value, who]
		"goalieshield": return "+%d shield on %s" % [value, who]
		"removeshields": return "every shield off %s" % who
		"foulheat": return "+%d on the referee's bar against them" % value
		"foulchance": return "+%d%% that they commit a foul" % value
		"foulcoinflip": return "your next foul is a coin toss"
		"switchtodefender": return "%s switches to being the defender" % who
		"alwaysdefending": return "%s always counts as defending" % who
		"swappower": return "%s swaps power with it" % who
		"setpowerfromtoken": return "%s fights with the power of a token you own" % who
		"useenemypower": return "%s fights with the enemy's power" % who
		"forceability": return "%s must use its %s side" % [who, effect_arg if effect_arg != "" else "other"]
		"negateability": return "%s's ability is negated" % who
		"negatebuff": return "%s loses its power buffs" % who
		"changepriority": return "%+d priority to %s" % [value, who]
		"givepriority": return "%s resolves first" % who
		"uncounterable": return "%s cannot be countered" % who
		"powerfromcount": return "%s's power = its %s count" % [who, effect_arg.replace("_", " ")]
		"removecondition": return "%s ignores its If" % who
		"swapintier": return "it swaps places with your unit about to duel"
		"sendtoexhaust": return "%s goes to the exhaust" % who
		"swapfromexhaust": return "after %s's next duel it goes to the exhaust and a unit of its tier comes back" % who
		"exhaustotherreturn": return "another of your units of its tier goes to the exhaust and this one comes back to be played"
		"revealanother": return "the next card you pick this round is revealed too"
		"revealfromexhaust": return "a card from your exhaust is revealed"
		"doubleattack": return "%s's printed power is doubled (max 5) for that duel" % who
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
		"token": return "a token you own"
		"opponent": return "the player it is up against"
		"allallies": return "its whole side"
		"allenemies": return "the whole other side"
		"enemygoalie": return "the keeper it shoots at"
		"owngoalie": return "its own keeper"
	# Round AA: "the next one" targets in words, for the duel window.
	var next := parse_next(target)
	if not next.is_empty():
		var kind_words := String(next["filter"]).replace("+", " ").replace(" i", " Tier I").replace(" ii", " Tier II") \
			.replace(" iii", " Tier III").replace(" iv", " Tier IV")
		if kind_words in ["i", "ii", "iii", "iv"]:
			kind_words = "Tier " + kind_words.to_upper()
		var unit := ("%s unit" % kind_words) if kind_words != "" else "unit"
		var many := int(next["count"])
		match String(next["kind"]):
			"next_self": return "itself, in its next duel"
			"next_enemy": return "the next enemy %s" % unit
			"next_tier_ally": return "your next unit played (if %s)" % kind_words if kind_words != "" else "your next unit played"
			"ally": return "your %s this round" % unit
		return ("your next %d %ss" % [many, unit]) if many > 1 else "your next %s" % unit
	if target.begins_with("replace:"):
		var f := target.substr(8).replace("+", " ")
		for t in ["iv", "iii", "ii", "i"]:
			if f.ends_with(" " + t):
				f = f.substr(0, f.length() - t.length()) + "Tier " + t.to_upper()
				break
		return "one of your %s units" % f
	if CardDatabase._normalise(target) == "side":
		return "your side"
	if target.begins_with("tag:"):
		return "every %s on its side" % target.substr(4)
	if target.begins_with("tier:"):
		return "its own Tier %s" % target.substr(5).to_upper()
	if target.begins_with("enemytier:") or target.begins_with("enemy_tier:"):
		return "their Tier %s" % target.split(":")[-1].to_upper()
	return target.replace("_", " ")


func _how_long_words() -> String:
	# A keeper's stamina has no "for this duel" - it is simply taken.
	if effect in ["drainstamina", "restorestamina"]:
		return ""
	# C5: these say their own timing.
	if effect in ["swapintier", "sendtoexhaust", "swapfromexhaust", "exhaustotherreturn",
			"revealanother", "revealfromexhaust", "doubleattack"]:
		return ""
	# Round AB (Q027): what "for the round" really means for these two.
	if scope == "round" and effect == "goaliechance":
		return ", until the next shot"
	if scope == "round" and effect == "foulchance":
		return ", for the next fouls"
	# "itself, in its next duel" already says when.
	if scope in ["", "duel"] and not parse_next(target).is_empty():
		return ""
	match scope:
		"duel": return ", for this duel"
		"round": return ", for the round"
		"cycle": return ", for the cycle"
		"match": return ", for the rest of the match"
	return ""
