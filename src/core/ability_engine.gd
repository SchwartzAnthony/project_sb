class_name AbilityEngine
extends RefCounted

# =============================================================
#  ABILITY ENGINE
#
#  Reads the rows CardDatabase loaded out of Abilities.csv and applies
#  them during a round. Buffs are held here rather than on the cards, so
#  a PlayerData resource is never mutated and scopes can be expired
#  cleanly (DUEL / ROUND / CYCLE / MATCH).
#
#  ADDING A NEW KIND OF EFFECT
#  This is the ONE place code has to change. Add the word to
#  AbilityData.EFFECTS, then handle it in _apply_one() below. Everything
#  else — new cards, new classes, new numbers — is CSV only.
# =============================================================

class Buff:
	var attack: int = 0
	var defense: int = 0
	var shot: int = 0
	var scope: String = "duel"
	var side_is_enemy: bool = false
	var card: PlayerData = null       # null means "matched by tag/tier"
	var tag: String = ""
	var tier: String = ""

	func matches(other: PlayerData, other_is_enemy: bool) -> bool:
		if other == null or other_is_enemy != side_is_enemy:
			return false
		if card != null:
			return other == card
		if tier != "":
			return other.get_tier_clean() == tier
		if tag != "":
			return other.has_tag(tag)
		return true


var db: CardDatabase
var log_lines: Array[String] = []

var _buffs: Array[Buff] = []
var _shot_bonus := {false: 0, true: 0}   # side_is_enemy -> extra shot power

## A flat power bonus for one whole side, set by the season's Difficulty
## column and by nothing else. It sits here rather than on the cards because
## the cards are shared: writing it onto PlayerData would follow those cards
## into your own team next match.
##   side_bonus[true]  = every enemy card is this much stronger
##   side_bonus[false] = every one of yours is
var side_bonus := {false: 0, true: 0}

## THE CEILING. No card's power may ever go past this, whatever is added to
## it. Read from `max_card_power` in Tuning.csv; 5 by default, because your
## tiers are 0-2, 1-3, 2-4 and 3-5.
##
## This is the fix for "the enemy had a 6-power unit". A fixture's Difficulty
## column adds a flat bonus to every enemy card, and a Difficulty of 1 on a
## 5-power Tier IV Star produced a 6. Difficulty is still useful — it lifts
## the weak cards in a squad — but it can no longer break the top of the
## scale, so a card you see is always a number you recognise.
var max_power: int = 5
var _stamina_pending: Array = []         # [{"enemy_side": bool, "delta": int}]


func _init(database: CardDatabase = null) -> void:
	db = database if database != null else CardDatabase.get_db()


# =============================================================
#  LIFECYCLE — call these from main_scene
# =============================================================

func begin_round() -> void:
	_expire("duel")
	_expire("round")
	_shot_bonus = {false: 0, true: 0}
	_stamina_pending.clear()
	log_lines.clear()


func begin_cycle() -> void:
	_expire("cycle")


func begin_duel() -> void:
	_expire("duel")


func end_match() -> void:
	_buffs.clear()


func _expire(scope: String) -> void:
	var kept: Array[Buff] = []
	for b in _buffs:
		if b.scope != scope:
			kept.append(b)
	_buffs = kept


# =============================================================
#  QUERIES USED BY COMBAT
# =============================================================

func attack_power(card: PlayerData, is_enemy: bool) -> int:
	if card == null:
		return 0
	var total := card.get_attack_power() + int(side_bonus.get(is_enemy, 0))
	for b in _buffs:
		if b.matches(card, is_enemy):
			total += b.attack
	return clampi(total, 0, max_power)


func defense_power(card: PlayerData, is_enemy: bool) -> int:
	if card == null:
		return 0
	var total := card.get_defense_power() + int(side_bonus.get(is_enemy, 0))
	for b in _buffs:
		if b.matches(card, is_enemy):
			total += b.defense
	return clampi(total, 0, max_power)


func shot_bonus(side_is_enemy: bool) -> int:
	return int(_shot_bonus.get(side_is_enemy, 0))


## Goalie stamina changes queued this round: [{enemy_side, delta}, ...]
func take_pending_stamina() -> Array:
	var out := _stamina_pending.duplicate()
	_stamina_pending.clear()
	return out


# =============================================================
#  FIRING ABILITIES
# =============================================================

## Every card on the pitch with a `passive` ability applies it once per round.
func apply_passives(player_lineup: Array, enemy_lineup: Array) -> void:
	for card in player_lineup:
		_fire_for(card, false, "passive", null, false)
	for card in enemy_lineup:
		_fire_for(card, true, "passive", null, true)


## Resolve one tier duel's abilities, lowest ability priority first.
## On a tie the ATTACKER resolves first (design rule).
func resolve_duel_abilities(attacker: PlayerData, attacker_is_enemy: bool,
		defender: PlayerData, trigger_extra: String = "") -> void:
	var defender_is_enemy := not attacker_is_enemy

	var queue: Array = []
	if attacker != null:
		queue.append({"card": attacker, "enemy": attacker_is_enemy, "role": "attack",
			"priority": attacker.get_ability_priority(), "order": 0})
	if defender != null:
		queue.append({"card": defender, "enemy": defender_is_enemy, "role": "defend",
			"priority": defender.get_ability_priority(), "order": 1})

	queue.sort_custom(func(a, b):
		if a["priority"] == b["priority"]:
			return a["order"] < b["order"]     # attacker first on a tie
		return a["priority"] < b["priority"])  # lower resolves first

	for entry in queue:
		var card: PlayerData = entry["card"]
		var is_enemy: bool = entry["enemy"]
		var opponent: PlayerData = defender if entry["role"] == "attack" else attacker

		_fire_for(card, is_enemy, "onduelstart", opponent, not is_enemy)
		if entry["role"] == "attack":
			_fire_for(card, is_enemy, "onattack", opponent, not is_enemy)
		else:
			_fire_for(card, is_enemy, "ondefend", opponent, not is_enemy)
		if trigger_extra != "":
			_fire_for(card, is_enemy, trigger_extra, opponent, not is_enemy)


## After a duel is decided.
func resolve_duel_outcome(winner: PlayerData, winner_is_enemy: bool,
		loser: PlayerData, loser_is_enemy: bool) -> void:
	_fire_for(winner, winner_is_enemy, "onwinduel", loser, loser_is_enemy)
	_fire_for(loser, loser_is_enemy, "onloseduel", winner, winner_is_enemy)


func _fire_for(card: PlayerData, is_enemy: bool, trigger: String,
		opponent: PlayerData, opponent_is_enemy: bool) -> void:
	if card == null:
		return
	for ability_id in [card.active_attack_ability(), card.active_defend_ability()]:
		var ability := db.get_ability(String(ability_id))
		if ability == null or ability.trigger != trigger:
			continue
		_apply_one(ability, card, is_enemy, opponent, opponent_is_enemy)


# =============================================================
#  THE ONE PLACE THAT KNOWS WHAT AN EFFECT DOES
# =============================================================

func _apply_one(ability: AbilityData, source: PlayerData, source_is_enemy: bool,
		opponent: PlayerData, opponent_is_enemy: bool) -> void:

	# --- Goalie effects resolve immediately, they are not buffs ---
	if ability.hits_goalie():
		var flat := CardDatabase._normalise(ability.target)
		# "enemy goalie" means the keeper on the OTHER side from the source.
		var keeper_is_enemy := not source_is_enemy if flat == "enemygoalie" else source_is_enemy
		var delta := -ability.value if ability.effect == "drainstamina" else ability.value
		if ability.effect in ["drainstamina", "restorestamina"]:
			_stamina_pending.append({"enemy_side": keeper_is_enemy, "delta": delta})
			log_lines.append("      %s: %s %d on the %s keeper"
				% [source.player_name, ability.effect, absi(delta),
				   "away" if keeper_is_enemy else "home"])
		return

	# --- Shot power is a per-side running total, also not a buff ---
	if ability.effect == "addshotpower":
		_shot_bonus[source_is_enemy] = int(_shot_bonus.get(source_is_enemy, 0)) + ability.value
		log_lines.append("      %s: %+d shot power" % [source.player_name, ability.value])
		return

	# --- Everything else becomes a scoped buff ---
	var buff := Buff.new()
	buff.scope = ability.scope
	match ability.effect:
		"addattack":
			buff.attack = ability.value
		"adddefense":
			buff.defense = ability.value
		"addpower":
			buff.attack = ability.value
			buff.defense = ability.value
		_:
			return

	if not _aim(buff, ability.target, source, source_is_enemy, opponent, opponent_is_enemy):
		return

	_buffs.append(buff)
	log_lines.append("      %s: %s %+d (%s, %s)"
		% [source.player_name, ability.effect, ability.value, ability.target, ability.scope])


## Point a buff at whoever the CSV said. Returns false if it hits nothing.
func _aim(buff: Buff, target: String, source: PlayerData, source_is_enemy: bool,
		opponent: PlayerData, opponent_is_enemy: bool) -> bool:
	var flat := CardDatabase._normalise(target)

	match flat:
		"self":
			buff.card = source
			buff.side_is_enemy = source_is_enemy
			return true
		"opponent":
			if opponent == null:
				return false
			buff.card = opponent
			buff.side_is_enemy = opponent_is_enemy
			return true
		"allallies":
			buff.side_is_enemy = source_is_enemy
			return true
		"allenemies":
			buff.side_is_enemy = not source_is_enemy
			return true

	var lower := target.strip_edges().to_lower()
	if lower.begins_with("tag:"):
		buff.tag = lower.substr(4).strip_edges()
		buff.side_is_enemy = source_is_enemy
		return buff.tag != ""
	if lower.begins_with("enemytier:"):
		buff.tier = lower.substr(10).strip_edges().to_upper()
		buff.side_is_enemy = not source_is_enemy
		return buff.tier != ""
	if lower.begins_with("tier:"):
		buff.tier = lower.substr(5).strip_edges().to_upper()
		buff.side_is_enemy = source_is_enemy
		return buff.tier != ""

	return false
