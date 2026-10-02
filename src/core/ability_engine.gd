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

## A flat SHOT bonus for one whole side, set by the season's Difficulty
## column and by nothing else. Unlike _shot_bonus above it is NOT cleared at
## the start of a round: a fixture's difficulty lasts the whole match.
##
## ============ WHY THIS IS NOT A POWER BONUS ANY MORE ============
##
## It used to add to every card's attack and defence. That quietly broke the
## rule the whole game rests on — Tier I holds a 0, a 1 and a 2 — because a
## Difficulty of 2 turned the enemy's Tier I into a 2, a 3 and a 4. You could
## see it on the pitch: cards whose numbers did not match their tier.
##
## The card is now never touched. Difficulty instead makes the opposition
## FINISH better: it is added to their shot when they get one, which is the
## same "this team is harder" without a single card leaving its rung.
##
##   side_shot_bonus[true]  = the enemy's shots are this much stronger
##   side_shot_bonus[false] = yours are
##
## `difficulty_as_power` in Tuning.csv puts the old behaviour back if you
## ever want it. Leave it at false — the ladder depends on it.
var side_shot_bonus := {false: 0, true: 0}

## The old flat power bonus. Left at 0 unless `difficulty_as_power` is on.
## See side_shot_bonus above for why.
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

## HOW MUCH EACH SIDE MADE HAPPEN THIS ROUND. One per ability that actually
## did something — not one per ability a card owns, and not one per ability
## that was merely looked at. Cleared at the start of every round.
##
## This is what the foul system prices. "If a team has triggered a certain
## number of triggers during the combat, after the combat their % of creating
## a foul is established" — so the number has to mean the same thing every
## round, which is why it is counted in _apply_one() below, the one place
## that knows an effect really landed.
var triggers := {false: 0, true: 0}

## ============ LEANING ON THE REFEREE (round X) ============
##
## The percent added AGAINST that side: card_chance[true] is how much likelier
## the ENEMY is to be booked when he is caught, because one of YOUR cards
## fired add_card_chance. Lasts the match - it is not cleared by
## begin_round(), only by begin_match().
var card_chance := {false: 0.0, true: 0.0}

## How many times each card's ability has gone off this match, for the Max
## column. Keyed "<card instance>|<ability id>".
var _uses: Dictionary = {}


func _init(database: CardDatabase = null) -> void:
	db = database if database != null else CardDatabase.get_db()


# =============================================================
#  LIFECYCLE — call these from main_scene
# =============================================================

## Kick-off. Forgets everything that lasts a whole match.
func begin_match() -> void:
	card_chance = {false: 0.0, true: 0.0}
	_uses.clear()


func begin_round() -> void:
	_expire("duel")
	_expire("round")
	_shot_bonus = {false: 0, true: 0}
	_stamina_pending.clear()
	triggers = {false: 0, true: 0}
	log_lines.clear()


func begin_cycle() -> void:
	_expire("cycle")


func begin_duel() -> void:
	_expire("duel")


func end_match() -> void:
	_buffs.clear()
	# The next fixture sets its own difficulty; a stale one would follow the
	# player into a friendly.
	side_shot_bonus = {false: 0, true: 0}
	side_bonus = {false: 0, true: 0}


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


## What to add to a shot: what abilities granted this round, plus the
## season's difficulty for the whole match.
func shot_bonus(side_is_enemy: bool) -> int:
	return int(_shot_bonus.get(side_is_enemy, 0)) \
		+ int(side_shot_bonus.get(side_is_enemy, 0))


## How many triggers this side has set off so far this round.
func triggers_for(side_is_enemy: bool) -> int:
	return int(triggers.get(side_is_enemy, 0))


## Count one by hand.
##
## Abilities count themselves. This is here for everything else that will one
## day want to be priced by the foul system — combos, brew effects, an item
## that goes off — so that when you add one you add a single line here rather
## than a second way of counting.
func note_trigger(side_is_enemy: bool, how_many: int = 1) -> void:
	triggers[side_is_enemy] = int(triggers.get(side_is_enemy, 0)) + maxi(0, how_many)


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
##
## `shown` is the cards that were played FACE UP in the draft — see
## fire_reveal(). AbilityTriggers.csv promises that if both sides show, the
## LOWER POWER goes first, and this is where that promise is kept: a shown
## card is given a priority of its own power, so two shown cards sort
## weakest-first through the ordinary rule rather than through a special case.
func resolve_duel_abilities(attacker: PlayerData, attacker_is_enemy: bool,
		defender: PlayerData, trigger_extra: String = "",
		shown: Array = []) -> void:
	var defender_is_enemy := not attacker_is_enemy

	var queue: Array = []
	if attacker != null:
		queue.append({"card": attacker, "enemy": attacker_is_enemy, "role": "attack",
			"priority": _duel_priority(attacker, shown, true), "order": 0})
	if defender != null:
		queue.append({"card": defender, "enemy": defender_is_enemy, "role": "defend",
			"priority": _duel_priority(defender, shown, false), "order": 1})

	queue.sort_custom(func(a, b):
		if a["priority"] == b["priority"]:
			return a["order"] < b["order"]     # attacker first on a tie
		return a["priority"] < b["priority"])  # lower resolves first

	for entry in queue:
		var card: PlayerData = entry["card"]
		var is_enemy: bool = entry["enemy"]
		var opponent: PlayerData = defender if entry["role"] == "attack" else attacker

		# FLIP GOES FIRST. The cards turn face up and then the duel begins, so
		# anything hung on `flip` has already happened by the time
		# `on_duel_start` runs — which is what lets a flip ability change what
		# the duel starts with.
		_fire_for(card, is_enemy, "flip", opponent, not is_enemy)
		_fire_for(card, is_enemy, "onduelstart", opponent, not is_enemy)
		if entry["role"] == "attack":
			_fire_for(card, is_enemy, "onattack", opponent, not is_enemy)
		else:
			_fire_for(card, is_enemy, "ondefend", opponent, not is_enemy)
		if trigger_extra != "":
			_fire_for(card, is_enemy, trigger_extra, opponent, not is_enemy)


## Where a card sits in the resolving order. Its own Ability Priority
## ordinarily; its POWER if it was played face up, which is what makes two
## shown cards resolve weakest-first.
func _duel_priority(card: PlayerData, shown: Array, attacking: bool) -> int:
	if card == null:
		return 0
	if shown.has(card):
		return card.get_attack_power() if attacking else card.get_defense_power()
	return card.get_ability_priority()


## ============ A CARD PLAYED FACE UP ============
##
## Fired the moment SHOW is pressed during the draft — not in the duel, and
## that is the whole point of the trigger: a reveal ability happens EARLY,
## while there is still a choice left for it to affect, and the other side
## gets to answer a card they can see.
##
## It can do anything any other trigger can do, because it goes through the
## same _apply_one(): a buff with a scope, a knock on a keeper, a bonus on
## the shot. There is no opponent yet — nobody has answered — so an ability
## written against `reveal` should target its own side.
func fire_reveal(card: PlayerData, is_enemy: bool) -> void:
	if not AbilityData.trigger_is_live("reveal"):
		return
	_fire_for(card, is_enemy, "reveal", null, not is_enemy)


## Fire one trigger for one card by name - "on_attack", "on_win_duel". For
## tools that need to prove an ability does what its row says without
## playing a whole match. The match itself never calls this.
func fire(card: PlayerData, is_enemy: bool, trigger: String,
		opponent: PlayerData = null, opponent_is_enemy: bool = false) -> void:
	_fire_for(card, is_enemy, CardDatabase._normalise(trigger), opponent, opponent_is_enemy)


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

	# ============ THE MAX COLUMN ============
	#
	# "(Max 5)" on a card means it goes off five times in a match and then
	# stops. Checked before anything else, so a spent ability does not even
	# count as a trigger - it did not happen.
	if ability.max_uses > 0 and source != null:
		var use_key := "%d|%s" % [source.get_instance_id(), ability.id]
		var used := int(_uses.get(use_key, 0))
		if used >= ability.max_uses:
			return
		_uses[use_key] = used + 1

	# ============ ONE TRIGGER ============
	#
	# Counted HERE and nowhere else, because this is the only line the game
	# reaches when an ability has actually gone off — past the trigger match,
	# past the priority sort, about to change a number. The foul system reads
	# it after the combat. See foul_book.gd.
	note_trigger(source_is_enemy)

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

	# --- A word in the referee's ear. Against the OTHER side, always. ---
	if ability.effect == "addcardchance":
		var against := not source_is_enemy
		card_chance[against] = float(card_chance.get(against, 0.0)) + float(ability.value)
		log_lines.append("      %s: the %s side is %+d%% likelier to be booked (now %+.0f%%)"
			% [source.player_name, "away" if against else "home", ability.value,
				float(card_chance[against])])
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
