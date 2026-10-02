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

# =============================================================
#  ROUND Y — PHASE C1: ZONES, MOMENTS, CONDITIONS AND "THE NEXT ONE"
#
#  The plan is guides/COMBAT_PHASES.md. In short:
#
#  THE ZONES. Every card in the match is in exactly one:
#      field    took the pitch, still to play this cycle
#      combat   drafted this round, until the round ends
#      exhaust  played this cycle; back to the field when the cycle ends
#  (Exile comes in phase C5.) Entering the exhaust fires `contemplation`,
#  leaving it fires `rejuvenation` - your two triggers from AbilityTriggers.csv.
#
#  THE MOMENTS. match_start, round_end, end_of_cycle, while_in_exhaust,
#  after_duel, on_shot, goalie_save, on_goal, on_concede - each one called
#  from exactly one place in main_scene.gd.
#
#  ONE SIDE PER DUEL (ruling F1). A card attacking uses its ATTACK ability, a
#  card defending its DEFEND ability. Outside a duel, the side it played last
#  (F2). `ability_uses_role_side` FALSE in Tuning.csv fires both, as before.
#
#  THE If COLUMN. Conditions that must be true - see AbilityData.CONDITIONS.
#
#  "THE NEXT ONE". A target of next_ally / next_enemy / next_self does not
#  land now: it WAITS, and lands on that card when it next duels.
# =============================================================

const FIELD := "field"
const COMBAT := "combat"
const EXHAUST := "exhaust"

## card -> {"zone": String, "enemy": bool}
var _zone: Dictionary = {}
## card -> "attack" / "defend": its role in its current, or last, duel
var _role: Dictionary = {}
## card -> "won" / "lost": how its last duel went
var _outcome: Dictionary = {}
## side -> "won" / "lost": how that side's most recent duel went
var _last_result := {false: "", true: ""}
## This round's four cards a side, for `ally:` targets.
var _lineup := {false: [], true: []}
## "Next" effects waiting for their card: {kind, count, filter, ability, source, source_enemy, side}
var _pending: Array = []
## Each keeper's stamina, set by the match before every duel, for own_goalie_lower.
var keeper_stamina := {false: 0, true: 0}
## Which cycle this is, so a "1/cycle" Max can tell the cycles apart.
var cycle_number := 1
var role_side := true
var _match_started := false
## Planned words already mentioned, so the Output panel says each once.
var _said: Dictionary = {}


func _init(database: CardDatabase = null) -> void:
	db = database if database != null else CardDatabase.get_db()
	role_side = db == null or db.tune_bool("ability_uses_role_side", true)


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


## A NEW CYCLE. Closes the old one first: `end_of_cycle` for every card in
## the match, then everyone in the exhaust walks back onto the field
## (`rejuvenation`). The match calls this at the STAR PLAYER SWITCH, and
## finish_match() does the same for the last cycle at full time.
func begin_cycle() -> void:
	close_cycle()
	_expire("cycle")


func close_cycle() -> void:
	for card in _zone.keys():
		_fire_for(card, bool(_zone[card]["enemy"]), "endofcycle", null, not bool(_zone[card]["enemy"]))
	for card in _zone.keys():
		if String(_zone[card]["zone"]) == EXHAUST:
			_move(card, bool(_zone[card]["enemy"]), FIELD)
	cycle_number += 1


## Full time. The last cycle has no STAR PLAYER SWITCH to close it.
func finish_match() -> void:
	close_cycle()


## A duel is about to start between these two. Any "next" effect waiting for
## either of them lands now, and every card sitting in the exhaust gets its
## `while_in_exhaust` moment.
func begin_duel(player_card: PlayerData = null, enemy_card: PlayerData = null) -> void:
	_expire("duel")
	if player_card != null:
		_consume_pending(player_card, false)
	if enemy_card != null:
		_consume_pending(enemy_card, true)
	for card in _zone.keys():
		if String(_zone[card]["zone"]) == EXHAUST:
			var side := bool(_zone[card]["enemy"])
			var facing: PlayerData = enemy_card if not side else player_card
			_fire_for(card, side, "whileinexhaust", facing, not side)


# =============================================================
#  ZONES (round Y, C1)
# =============================================================

## Everyone on the pitch, both sides. Cards the book has not seen yet go onto
## the FIELD; the first time it is called is the match's `match_start`.
func sync_field(player_cards: Array, enemy_cards: Array) -> void:
	var fresh: Array = []
	for pair in [[player_cards, false], [enemy_cards, true]]:
		for thing in pair[0]:
			var card := thing as PlayerData
			if card != null and not _zone.has(card):
				_zone[card] = {"zone": FIELD, "enemy": pair[1]}
				fresh.append(card)
	if not _match_started:
		_match_started = true
		for card in fresh:
			_fire_for(card, bool(_zone[card]["enemy"]), "matchstart", null, not bool(_zone[card]["enemy"]))


## This round's line-ups: drafted cards leave the field for COMBAT.
func round_lineups(player_lineup: Array, enemy_lineup: Array) -> void:
	_lineup = {false: player_lineup.duplicate(), true: enemy_lineup.duplicate()}
	for pair in [[player_lineup, false], [enemy_lineup, true]]:
		for thing in pair[0]:
			var card := thing as PlayerData
			if card != null:
				_move(card, pair[1], COMBAT)


## The round is over. `round_end` for the cards that played it, then they go
## to the EXHAUST - which fires `contemplation` for each.
func round_finished() -> void:
	var played: Array = []
	for card in _zone.keys():
		if String(_zone[card]["zone"]) == COMBAT:
			played.append(card)
	for card in played:
		_fire_for(card, bool(_zone[card]["enemy"]), "roundend", null, not bool(_zone[card]["enemy"]))
	for card in played:
		_move(card, bool(_zone[card]["enemy"]), EXHAUST)


func zone_of(card: PlayerData) -> String:
	return String((_zone.get(card, {}) as Dictionary).get("zone", ""))


## Every card of one side in one zone ("" = every zone).
func cards_in(side_is_enemy: bool, zone: String = "") -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for card in _zone.keys():
		if bool(_zone[card]["enemy"]) == side_is_enemy and (zone == "" or String(_zone[card]["zone"]) == zone):
			out.append(card)
	return out


func _move(card: PlayerData, side_is_enemy: bool, to: String) -> void:
	var was := zone_of(card)
	_zone[card] = {"zone": to, "enemy": side_is_enemy}
	if was == to:
		return
	if to == EXHAUST:
		_fire_for(card, side_is_enemy, "contemplation", null, not side_is_enemy)
	elif was == EXHAUST:
		_fire_for(card, side_is_enemy, "rejuvenation", null, not side_is_enemy)


# =============================================================
#  THE SHOT AND THE KEEPERS (round Y, C1)
# =============================================================

## The shooter is about to shoot. Returns the extra shot power its
## `on_shot` abilities added.
func fire_on_shot(shooter: PlayerData, shooter_is_enemy: bool) -> int:
	var before := int(_shot_bonus.get(shooter_is_enemy, 0))
	_fire_for(shooter, shooter_is_enemy, "onshot", null, not shooter_is_enemy)
	return int(_shot_bonus.get(shooter_is_enemy, 0)) - before


## The shot is in, or it is not. A goal is `on_goal` for every card of the
## scoring side and `on_concede` for the other; a save is `goalie_save` for
## every card of the side whose keeper saved it - conditions like in_exhaust
## narrow it down to the cards that care.
func after_shot(shooter_is_enemy: bool, scored: bool) -> void:
	if scored:
		for card in cards_in(shooter_is_enemy):
			_fire_for(card, shooter_is_enemy, "ongoal", null, not shooter_is_enemy)
		for card in cards_in(not shooter_is_enemy):
			_fire_for(card, not shooter_is_enemy, "onconcede", null, shooter_is_enemy)
	else:
		for card in cards_in(not shooter_is_enemy):
			_fire_for(card, not shooter_is_enemy, "goaliesave", null, shooter_is_enemy)


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

	# WHO IS DOING WHAT, before anything fires - a condition like `defending`
	# and ONE SIDE PER DUEL both read it.
	if attacker != null:
		_role[attacker] = "attack"
		_outcome.erase(attacker)
	if defender != null:
		_role[defender] = "defend"
		_outcome.erase(defender)

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
	if winner != null:
		_outcome[winner] = "won"
	if loser != null:
		_outcome[loser] = "lost"
	_fire_for(winner, winner_is_enemy, "onwinduel", loser, loser_is_enemy)
	_fire_for(loser, loser_is_enemy, "onloseduel", winner, winner_is_enemy)
	_fire_for(winner, winner_is_enemy, "afterduel", loser, loser_is_enemy)
	_fire_for(loser, loser_is_enemy, "afterduel", winner, winner_is_enemy)
	# "Your last unit won combat" - remembered AFTER this duel's own abilities,
	# so it means the PREVIOUS duel to whoever asks next.
	_last_result[winner_is_enemy] = "won"
	_last_result[loser_is_enemy] = "lost"


## Moments where BOTH of a card's abilities are looked at: nothing about
## them belongs to one role.
const BOTH_SIDES: Array[String] = ["passive", "matchstart"]


func _fire_for(card: PlayerData, is_enemy: bool, trigger: String,
		opponent: PlayerData, opponent_is_enemy: bool) -> void:
	if card == null:
		return
	# ============ ONE SIDE PER DUEL (ruling F1 / F2) ============
	# Its role in its duel, or - outside a duel - the role it played last.
	# A card that has not duelled yet counts as attacking, which is also the
	# Reveal rule until ruling F3 is answered.
	var slots: Array[String] = ["attack", "defend"]
	if role_side and not BOTH_SIDES.has(trigger):
		var played: Array[String] = [String(_role.get(card, "attack"))]
		slots = played
		# REVEAL comes before anyone knows who attacks (ruling F3). Until you
		# rule, the side that HAS a reveal ability fires - the Attack side if
		# both do - so a card whose only Reveal is on its Defend side still
		# works, and a card with two never fires twice.
		# (Two typed lists, not `[a] if c else [b]` - that makes an untyped
		# Array and fails silently at runtime. The typed-array rule.)
		if trigger == "reveal" and not _role.has(card):
			var only_defend: Array[String] = ["defend"]
			var only_attack: Array[String] = ["attack"]
			if not _slot_has(card.active_attack_ability(), "reveal") \
					and _slot_has(card.active_defend_ability(), "reveal"):
				slots = only_defend
			else:
				slots = only_attack
	for slot in slots:
		var cell := card.active_attack_ability() if slot == "attack" else card.active_defend_ability()
		# A CELL MAY NAME SEVERAL ROWS, separated by semicolons, so one
		# sentence with two halves ("+1 now. If this wins: ...") is two rows.
		for piece in String(cell).split(";"):
			var ability := db.get_ability(String(piece).strip_edges())
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
	# ============ THE If COLUMN (round Y) ============
	# Before anything else: a condition that is not met means it did not
	# happen - not counted, not spent against its Max.
	if not _condition_ok(ability, source, source_is_enemy, opponent, opponent_is_enemy):
		return

	if ability.max_uses > 0 and source != null:
		var use_key := "%d|%s" % [source.get_instance_id(), ability.id]
		if ability.max_per == "cycle":
			use_key += "|cycle%d" % cycle_number
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

	# --- "THE NEXT ONE" waits for its card (round Y) ---
	var next := AbilityData.parse_next(ability.target)
	if not next.is_empty():
		if String(next["kind"]) == "ally":
			# Not "next": your card in that tier/kind THIS round, now.
			for thing in (_lineup.get(source_is_enemy, []) as Array):
				var mate := thing as PlayerData
				if mate != null and AbilityData.card_matches(mate, String(next["filter"])):
					_land_buff(ability, mate, source_is_enemy, source)
			return
		var side := not source_is_enemy if String(next["kind"]) == "next_enemy" else source_is_enemy
		_pending.append({"kind": next["kind"], "count": int(next["count"]), "filter": next["filter"],
			"ability": ability, "source": source, "source_enemy": source_is_enemy, "side": side})
		log_lines.append("      %s: %s %+d waits for %s" % [source.player_name, ability.effect,
			ability.value, ability.target])
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


# =============================================================
#  CONDITIONS AND "NEXT" (round Y, C1)
# =============================================================

func _condition_ok(ability: AbilityData, source: PlayerData, source_is_enemy: bool,
		opponent: PlayerData, opponent_is_enemy: bool) -> bool:
	if ability.condition.strip_edges() == "":
		return true
	for term in AbilityData.condition_terms(ability.condition):
		var word := String(term["word"])
		var arg := String(term["arg"])
		var ok := false
		match word:
			"defending":
				ok = String(_role.get(source, "")) == "defend"
			"attacking":
				ok = String(_role.get(source, "")) == "attack"
			"won":
				ok = String(_outcome.get(source, "")) == "won"
			"lost":
				ok = String(_outcome.get(source, "")) == "lost"
			"lastallywon":
				ok = String(_last_result.get(source_is_enemy, "")) == "won"
			"lastallylost":
				ok = String(_last_result.get(source_is_enemy, "")) == "lost"
			"enemyelement":
				ok = opponent != null and CardDatabase._normalise(opponent.active_element()) == CardDatabase._normalise(arg)
			"enemynotelement":
				ok = opponent != null and CardDatabase._normalise(opponent.active_element()) != CardDatabase._normalise(arg)
			"owngoalielower":
				ok = int(keeper_stamina.get(source_is_enemy, 0)) < int(keeper_stamina.get(not source_is_enemy, 0))
			"enemybelowbase":
				if opponent != null:
					var now := attack_power(opponent, opponent_is_enemy) \
						if String(_role.get(opponent, "attack")) == "attack" \
						else defense_power(opponent, opponent_is_enemy)
					ok = now < opponent.base_power_left
			"inexhaust":
				ok = zone_of(source) == EXHAUST
			"infield":
				ok = zone_of(source) == FIELD
			"incombat":
				ok = zone_of(source) == COMBAT
			"hastag":
				ok = source.has_tag(arg)
			_:
				# A planned word: never true yet. Said once.
				if not _said.has(word):
					_said[word] = true
					print("[abilities] the '%s' condition is not built yet, so it is never true." % term["raw"])
				ok = false
		if bool(term["not"]):
			ok = not ok
		if not ok:
			return false
	return true


## A card is about to duel: land every "next" effect that was waiting for it.
func _consume_pending(card: PlayerData, card_is_enemy: bool) -> void:
	var kept: Array = []
	for p in _pending:
		var take := bool(p["side"]) == card_is_enemy
		if take:
			match String(p["kind"]):
				"next_self":
					take = p["source"] == card
				"next_ally":
					take = p["source"] != card and AbilityData.card_matches(card, String(p["filter"]))
				_:
					take = AbilityData.card_matches(card, String(p["filter"]))
		if not take:
			kept.append(p)
			continue
		var ability: AbilityData = p["ability"]
		var source: PlayerData = p["source"]
		if ability.effect in ["drainstamina", "restorestamina", "addshotpower", "addcardchance"]:
			_land_side_effect(ability, source, bool(p["source_enemy"]))
		else:
			_land_buff(ability, card, card_is_enemy, source)
		p["count"] = int(p["count"]) - 1
		if int(p["count"]) > 0:
			kept.append(p)
	_pending = kept


## A buff from `ability` on exactly this card, for this duel.
func _land_buff(ability: AbilityData, card: PlayerData, card_is_enemy: bool, source: PlayerData) -> void:
	var buff := Buff.new()
	buff.scope = "duel" if ability.scope in ["", "duel"] else ability.scope
	buff.card = card
	buff.side_is_enemy = card_is_enemy
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
	_buffs.append(buff)
	log_lines.append("      %s: %s %+d lands on %s" % [
		source.player_name if source != null else "?", ability.effect, ability.value, card.player_name])


## A keeper or a shot effect that was waiting - it belongs to the SOURCE's side.
func _land_side_effect(ability: AbilityData, source: PlayerData, source_is_enemy: bool) -> void:
	if ability.effect == "addshotpower":
		_shot_bonus[source_is_enemy] = int(_shot_bonus.get(source_is_enemy, 0)) + ability.value
		return
	if ability.effect == "addcardchance":
		card_chance[not source_is_enemy] = float(card_chance.get(not source_is_enemy, 0.0)) + float(ability.value)
		return
	var flat := CardDatabase._normalise(ability.target)
	var keeper_is_enemy := not source_is_enemy if flat != "owngoalie" else source_is_enemy
	var delta := -ability.value if ability.effect == "drainstamina" else ability.value
	_stamina_pending.append({"enemy_side": keeper_is_enemy, "delta": delta})


func _slot_has(cell: String, trigger: String) -> bool:
	for piece in cell.split(";"):
		var ability := db.get_ability(String(piece).strip_edges())
		if ability != null and ability.trigger == trigger:
			return true
	return false


## The IDs of every ability still waiting for its card, for a tool.
func pending_ids() -> Array[String]:
	var out: Array[String] = []
	for p in _pending:
		out.append((p["ability"] as AbilityData).id)
	return out


## What is still waiting, for a tool or a screen.
func pending_count(side_is_enemy: bool) -> int:
	var n := 0
	for p in _pending:
		if bool(p["side"]) == side_is_enemy:
			n += int(p["count"])
	return n
