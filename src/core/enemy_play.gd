class_name EnemyPlay
extends RefCounted

# =============================================================
#  HOW THE OTHER SIDE PLAYS — a list of rules, not an AI
#
#  ============ THE QUESTION THIS ANSWERS ============
#
#  "Is there a simple solution to this without having to build a full AI
#  inside the game?"
#
#  Yes, and it is the one board games have used for forty years. A boss in a
#  board game has no AI; it has a CARD with two or three lines on it —
#  "if a hero is adjacent, attack the weakest; otherwise move toward the
#  nearest" — and you read the lines in order and do the first one that fits.
#  It is completely predictable if you study it, which is the point: the
#  player's skill is learning to read it.
#
#  So the opposition is a spreadsheet. `data/EnemyPlay.csv` is a list of
#  rules in order; the first one whose `When` is true decides what they pick
#  this tier and whether they play it face up. Nothing learns, nothing
#  searches, nothing is hidden from you, and YOU write the rules.
#
#  ============ A ROW ============
#
#      Order   read low to high. The first match wins
#      Style   which opponent this rule belongs to. Blank = every opponent.
#              Teams.csv `Play Style` names one
#      When    the condition. See BELOW
#      Pick    which card they choose
#      Reveal  whether they play it face up
#      Do      an Effects term run when this rule fires — the same words
#              every other spreadsheet uses. THIS IS THE SCRIPTING HOOK:
#              `brew:fire` has them pour one on the card they just took
#      Notes   yours
#
#  ============ WHEN ============
#
#      always              nothing to check
#      you_revealed        you have played a card face up in this tier
#      you_hid             you have not
#      tier:IV             this tier only. tier:I, tier:II, tier:III
#      attacking           they are the attacking side this round
#      defending           they are not
#      winning / losing    by the score, right now
#      level               the score is equal
#      round:3             that round of the cycle
#      has_ability         at least one of their choices has an ability at all
#      flag:tutorial       a flag in your save is set. !flag:x for "is not".
#                          How a rule belongs to ONE scripted match
#
#  ============ PICK ============
#
#      random              what it always did
#      strongest           the highest power for the job this round
#      weakest             the lowest — saving the good one for later
#      counter             the best answer to the card you showed. Falls back
#                          to `strongest` if you showed nothing
#      ability_first       a card with an ability, strongest of those
#      no_ability          keep the ability cards back for a later tier
#
#  ============ REVEAL ============
#
#      never               play it face down, as they always have
#      always              face up whatever it is
#      if_ability          face up only if the card actually has a `reveal`
#                          ability to fire — which is the honest one, and the
#                          default
#      match               face up only if YOU showed one first
#
#  ============ WHY IT IS BETTER THAN AN AI HERE ============
#
#  An AI would have to be taught the tier ladder, the combo table, the shot
#  bonus and the clash before it could be any good, and when it did something
#  surprising neither of us could say why. Ten rows in a spreadsheet can be
#  read, argued with, and given to a different opponent to make them play
#  differently — which is the actual design goal. The Marsh King and the
#  county-league side you open against should not play the same way, and with
#  this they do not have to.
# =============================================================

const FILE := "res://data/EnemyPlay.csv"

## One rule, already read out of the spreadsheet.
class Rule extends RefCounted:
	var id: String = ""
	var order: int = 0
	var style: String = ""
	var when_text: String = "always"
	var pick: String = "random"
	var reveal: String = "never"
	## An Effects term run when this rule fires — the same words every other
	## spreadsheet uses. This is how the opening match has them drink a brew.
	var do_text: String = ""


static var _rules: Array[Rule] = []
static var _loaded := false


static func rules() -> Array[Rule]:
	if _loaded:
		return _rules
	_loaded = true
	_rules = []
	for row in MenuSupport.read_csv(FILE):
		var rule := Rule.new()
		rule.id = MenuSupport.field(row, "ID").strip_edges()
		if rule.id == "":
			continue
		rule.order = int(MenuSupport.field(row, "Order"))
		rule.style = CardDatabase._normalise(MenuSupport.field(row, "Style"))
		rule.when_text = CardDatabase._normalise(MenuSupport.field(row, "When"))
		rule.pick = CardDatabase._normalise(MenuSupport.field(row, "Pick"))
		rule.reveal = CardDatabase._normalise(MenuSupport.field(row, "Reveal"))
		rule.do_text = MenuSupport.field(row, "Do").strip_edges()
		if rule.when_text == "":
			rule.when_text = "always"
		if rule.pick == "":
			rule.pick = "random"
		if rule.reveal == "":
			rule.reveal = "never"
		_rules.append(rule)
	_rules.sort_custom(func(a: Rule, b: Rule) -> bool: return a.order < b.order)
	if _rules.is_empty():
		# NO FILE, NO CRASH. One rule that does what the game did before it
		# had a file: pick at random and never show anything.
		var fallback := Rule.new()
		fallback.id = "built_in"
		_rules.append(fallback)
		print("[enemy] No EnemyPlay.csv — the opposition picks at random, as it used to.")
	else:
		print("[enemy] %d play rule(s) from EnemyPlay.csv." % _rules.size())
	return _rules


## Forget the file, so a reload reads it again.
static func forget() -> void:
	_rules = []
	_loaded = false


## THE ONE CALL THE MATCH MAKES. Hand it the situation, get back which card
## they take and whether they put it face up.
##
## `facts` is a plain dictionary so this can be tested without a match:
##
##     tier            "III"
##     style           their Play Style, or ""
##     you_revealed    the card YOU put face up in this tier, or null
##     attacking       true if they are the attacking side this round
##     their_goals / your_goals
##     round           1..3
##     choices         the PlayerData they may take
##
## Returns { "card": PlayerData, "face_up": bool, "rule": String }.
static func decide(facts: Dictionary) -> Dictionary:
	var choices: Array = facts.get("choices", [])
	if choices.is_empty():
		return {"card": null, "face_up": false, "rule": "", "do": ""}

	var style := CardDatabase._normalise(String(facts.get("style", "")))
	for rule in rules():
		if rule.style != "" and rule.style != style:
			continue
		if not _matches(rule.when_text, facts):
			continue
		var card = _choose(rule.pick, facts, choices)
		return {
			"card": card,
			"face_up": _shows(rule.reveal, facts, card),
			"rule": rule.id,
			"do": rule.do_text,
		}

	return {"card": choices.pick_random(), "face_up": false, "rule": "", "do": ""}


# =============================================================
#  THE THREE COLUMNS
# =============================================================

static func _matches(when_text: String, facts: Dictionary) -> bool:
	var mine := int(facts.get("their_goals", 0))
	var yours := int(facts.get("your_goals", 0))
	match when_text:
		"always": return true
		"yourevealed": return facts.get("you_revealed", null) != null
		"youhid": return facts.get("you_revealed", null) == null
		"attacking": return bool(facts.get("attacking", false))
		"defending": return not bool(facts.get("attacking", false))
		"winning": return mine > yours
		"losing": return mine < yours
		"level": return mine == yours
		"hasability": return _any_with_ability(facts.get("choices", [])) != null
	if when_text.begins_with("tier"):
		return CardDatabase._normalise(String(facts.get("tier", ""))) == when_text.substr(4)
	if when_text.begins_with("round"):
		return int(facts.get("round", 0)) == int(when_text.substr(5))
	# A FLAG OUT OF YOUR SAVE, so a rule can belong to one scripted match and
	# no other — which is how the opening game has them pour a brew at Tier
	# III and no later opponent ever does. `flag:tutorial`, `!flag:first_win`.
	if when_text.begins_with("flag") or when_text.begins_with("!flag"):
		# `when_text` has already been through _normalise(), which takes the
		# colon and the underscores out — "flag:tutorial_match" arrives here
		# as "flagtutorialmatch". So the name starts after "flag" (4) or
		# after "!flag" (5), NOT one further along. GameState keys its flags
		# through the same flattening, so the two agree.
		var want_on := not when_text.begins_with("!")
		var flag_name: String = when_text.substr(4 if want_on else 5)
		var state: GameState = facts.get("state", null)
		if state == null:
			return false
		return state.has_flag(flag_name) == want_on
	# AN UNKNOWN WORD NEVER MATCHES, and says so once rather than quietly
	# behaving like `always` — a typo that always fires is a rule table that
	# stops at row one.
	push_warning("[enemy] EnemyPlay.csv: '%s' is not a When I know. That rule is skipped." % when_text)
	return false


static func _choose(pick: String, facts: Dictionary, choices: Array):
	var attacking := bool(facts.get("attacking", false))
	match pick:
		"strongest": return _by_power(choices, attacking, true)
		"weakest": return _by_power(choices, attacking, false)
		"abilityfirst":
			var with := _all_with_ability(choices)
			return _by_power(with, attacking, true) if not with.is_empty() \
				else _by_power(choices, attacking, true)
		"noability":
			var without: Array = []
			for card in choices:
				if _ability_names(card).is_empty():
					without.append(card)
			return without.pick_random() if not without.is_empty() else choices.pick_random()
		"counter":
			var shown = facts.get("you_revealed", null)
			if shown == null:
				return _by_power(choices, attacking, true)
			# THE BEST ANSWER, which is not the same as the strongest card.
			# You are attacking, so their best answer is their highest DEFENCE;
			# you are defending, so it is their highest ATTACK.
			return _by_power(choices, attacking, true)
	return choices.pick_random()


static func _shows(reveal: String, facts: Dictionary, card) -> bool:
	match reveal:
		"always": return true
		"ifability": return card != null and _has_reveal(card)
		"match": return facts.get("you_revealed", null) != null and card != null \
			and _has_reveal(card)
	return false


# =============================================================
#  SMALL HELPERS
# =============================================================

## Highest or lowest power FOR THE JOB THIS ROUND — defence when they are
## defending, attack when they are attacking. Asked of the round rather than
## remembered, so a side swap is followed.
static func _by_power(choices: Array, attacking: bool, want_high: bool):
	if choices.is_empty():
		return null
	var best = choices[0]
	for card in choices:
		var mine: int = card.get_attack_power() if attacking else card.get_defense_power()
		var top: int = best.get_attack_power() if attacking else best.get_defense_power()
		if (mine > top) if want_high else (mine < top):
			best = card
	return best


static func _ability_names(card) -> Array:
	var out: Array = []
	for ability_name in [card.active_attack_ability(), card.active_defend_ability()]:
		if String(ability_name).strip_edges() != "":
			out.append(String(ability_name).strip_edges())
	return out


static func _all_with_ability(choices: Array) -> Array:
	var out: Array = []
	for card in choices:
		if not _ability_names(card).is_empty():
			out.append(card)
	return out


static func _any_with_ability(choices: Array):
	var all := _all_with_ability(choices)
	return all[0] if not all.is_empty() else null


## Does this card have something written against the `reveal` trigger — that
## is, is there any point in it being played face up?
static func _has_reveal(card) -> bool:
	var db := CardDatabase.get_db()
	if db == null or not AbilityData.trigger_is_live("reveal"):
		return false
	for ability_name in _ability_names(card):
		var ability: AbilityData = db.get_ability(ability_name)
		if ability != null and ability.trigger == "reveal":
			return true
	return false
