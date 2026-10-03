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
#  Entering the exhaust fires `contemplation`, leaving it fires
#  `rejuvenation` - your two triggers from AbilityTriggers.csv. (Ruling R14:
#  "Exile" was the old name of the exhaust zone. There is no fourth zone.)
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
#
#  ============ ROUND Z — PHASE C2: COUNTERS, ORE, TOKENS, SWANS ============
#
#  COUNTERS sit on a CARD for the rest of the match, whatever zone it is in:
#  burn, song, and the POWER counter ("-1 power counter"), which changes the
#  card's power in every duel after. `add_counter:<kind>` / `remove_counter`.
#  A card receiving one fires `on_counter` (Buer's Emblem listens for it).
#
#  SIDE POOLS sit on a SIDE: Ore (ruling R12 - one pool per side, shown on
#  the match tracker) and Belphegor's victory counters. `gain_ore` fills the
#  Ore pool; a Cost of `ore:3` spends from it before an ability goes off.
#
#  TOKENS. A Rose (or Swan) Unit token is a copy of the card it replaces: same
#  tier, same power, no ability text. The replaced card goes to the exhaust
#  and STAYS there while its token plays - which is exactly what makes the
#  Sitri set's "While in exhaust" side work. The match swaps the body's card
#  when it reads take_swaps(), and puts every original back at full time.
#
#  SWANS are a creature type, not a card: a card turned into a Swan stays the
#  same card and gains the word "swan" for the rest of the match. Kept here,
#  by side, so a card both teams own is never a swan for the wrong one.
#
#  EMBLEMS. An Emblem's `Basic Ability` column names Abilities rows, and every
#  card of that side that feeds the Emblem carries those rows too.
#
#  EVERY KEY BELOW IS (card, side). Two teams can field the very same card
#  resource (a friendly against a scratch side, a mirror match), so a card
#  alone is not enough to say whose it is.
# =============================================================

const FIELD := "field"
const COMBAT := "combat"
const EXHAUST := "exhaust"

## key -> {"card": PlayerData, "zone": String, "enemy": bool}
var _zone: Dictionary = {}
## key -> "attack" / "defend": its role in its current, or last, duel
var _role: Dictionary = {}
## key -> "won" / "lost": how its last duel went
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
## Which round of the match this is, for a "1/round" Max.
var round_number := 0
var role_side := true
var _match_started := false
## Planned words already mentioned, so the Output panel says each once.
var _said: Dictionary = {}

# ---- round Z, C2 ----
## key -> {kind: int}. Counters on cards. "power" is signed: -1 = a -1 power counter.
var _counters: Dictionary = {}
## side -> {kind: int}. Ore, victory - things a SIDE holds.
var _pool := {false: {}, true: {}}
## side -> {kind: int}. What came INTO the pool this round (ore_this_round).
var _pool_round := {false: {}, true: {}}
## key -> {kind: true}. Creature types gained in the match - "swan".
var _kinds: Dictionary = {}
## key -> true. A card a token replaced: it stays in the exhaust.
var _held: Dictionary = {}
## side -> [cards that went to the exhaust this round], for exhausted_this_round.
var _exhausted_round := {false: [], true: []}
## Bodies to re-card: {side, old, new}. The match reads take_swaps().
var _swaps: Array = []
## Every swap of the match, so full time can put the originals back.
var _all_swaps: Array = []
## Cards that asked to be replaced by a token once their round is over (Manfred).
var _replace_after_round: Array = []
## Things that happened, for Stats.csv: {event, facts, enemy}. take_events().
var _events: Array = []
## side -> the Emblems that side has on the field (ClassBook.Emblem).
var _emblems := {false: [], true: []}
## Stops an on_counter ability that adds a counter from going round forever.
var _depth := 0
## Tuning: does a Swan count as a token for "if you control a token"?
var swans_are_tokens := true

# ---- round AA: C3, the keeper and the referee ----
## keeper side -> percentage points on the chance he is BEATEN. Round / match.
var _keeper_shift_round := {false: 0.0, true: 0.0}
var _keeper_shift_match := {false: 0.0, true: 0.0}
## side -> referee's-bar segments to add against that side, at the fouls.
var _heat_add := {false: 0.0, true: 0.0}
## side -> + % that side commits a foul. Round / match.
var _foul_shift_round := {false: 0.0, true: 0.0}
var _foul_shift_match := {false: 0.0, true: 0.0}
## side -> coin flips banked (Manfred). Never more than one.
var _coin_flips := {false: 0, true: 0}

# ---- round AA: THE PLAYER IS ASKED ----
#
# Your rulings: the player CHOOSES which unit a Rose token replaces, whether
# to spend Ore, whether to accept a Swan, and which side of a card stays up in
# the exhaust. The engine cannot stop in the middle of a duel to wait for a
# click, so there are two ways a question reaches you:
#
#   BEFORE A DUEL  the match asks duel_questions() what could cost Ore or
#                  needs a yes in the coming duel, asks you, and tells the
#                  engine with consent(). A "no" means it does not happen.
#   AFTER A MOMENT a reveal, the end of a round, the end of a cycle: the
#                  engine puts the question in take_asks() and waits. The
#                  match shows it and calls answer().
#
# `interactive[side]` is true only for YOUR side with AUTO off. The other
# side and AUTO always take the default (yes / the engine's own pick), so a
# soak, a tool and the AI never wait for anyone.
var interactive := {false: false, true: false}
var ask_before_ore := true
## "cardkey|ability id" -> true / false, for this duel.
var _consent: Dictionary = {}
## Questions waiting for the match: {id, kind, side, card, ...}.
var _asks: Array = []
var _ask_serial := 0
## key -> {"slot": "attack"/"defend", "cycle": n}. Ruling F2: the side of a
## card that stays up OUTSIDE a duel, chosen once per cycle.
var _side_up: Dictionary = {}
## key -> ability ids that went off for that card in this duel (for the duel
## window: "did it fire?").
var _fired: Dictionary = {}
## key -> true once that card has played a duel this match (card_played).
var _played_once: Dictionary = {}
## Tuning: does a goal send every Rose token home (ruling, round AA)?
var rose_ends_on_goal := true


func _init(database: CardDatabase = null) -> void:
	db = database if database != null else CardDatabase.get_db()
	role_side = db == null or db.tune_bool("ability_uses_role_side", true)
	swans_are_tokens = db == null or db.tune_bool("swans_count_as_tokens", true)
	ask_before_ore = db == null or db.tune_bool("ask_before_spending_ore", true)
	rose_ends_on_goal = db == null or db.tune_bool("rose_tokens_end_on_goal", true)


## The key for one card on one side. See "EVERY KEY BELOW" above.
static func _k(card: PlayerData, side_is_enemy: bool) -> String:
	return "%d|%d" % [card.get_instance_id() if card != null else 0, 1 if side_is_enemy else 0]


# =============================================================
#  LIFECYCLE — call these from main_scene
# =============================================================

## Kick-off. Forgets everything that lasts a whole match.
func begin_match() -> void:
	card_chance = {false: 0.0, true: 0.0}
	_uses.clear()
	_counters.clear()
	_pool = {false: {}, true: {}}
	_kinds.clear()
	_held.clear()
	_keeper_shift_match = {false: 0.0, true: 0.0}
	_foul_shift_match = {false: 0.0, true: 0.0}
	_coin_flips = {false: 0, true: 0}
	_side_up.clear()


func begin_round() -> void:
	_expire("duel")
	_expire("round")
	_shot_bonus = {false: 0, true: 0}
	_stamina_pending.clear()
	triggers = {false: 0, true: 0}
	log_lines.clear()
	round_number += 1
	_pool_round = {false: {}, true: {}}
	_exhausted_round = {false: [], true: []}
	# NOT the keeper and foul shifts: a "round" shift lasts until the next
	# shot / the next fouls, so one made after them (a save, the exhaust)
	# still counts. See after_shot() and fouls_settled().


## A NEW CYCLE. Closes the old one first: `end_of_cycle` for every card in
## the match, then everyone in the exhaust walks back onto the field
## (`rejuvenation`). The match calls this at the STAR PLAYER SWITCH, and
## finish_match() does the same for the last cycle at full time.
func begin_cycle() -> void:
	close_cycle()
	_expire("cycle")


func close_cycle() -> void:
	for key in _zone.keys():
		var e: Dictionary = _zone[key]
		_fire_for(e["card"], bool(e["enemy"]), "endofcycle", null, not bool(e["enemy"]))
	for key in _zone.keys():
		var e: Dictionary = _zone[key]
		# A CARD A TOKEN REPLACED STAYS WHERE IT IS: its body is the token's now.
		if String(e["zone"]) == EXHAUST and not _held.has(key):
			_move(e["card"], bool(e["enemy"]), FIELD)
	cycle_number += 1


## Full time. The last cycle has no STAR PLAYER SWITCH to close it.
func finish_match() -> void:
	close_cycle()


## A duel is about to start between these two. Any "next" effect waiting for
## either of them lands now, and every card sitting in the exhaust gets its
## `while_in_exhaust` moment.
func begin_duel(player_card: PlayerData = null, enemy_card: PlayerData = null) -> void:
	_expire("duel")
	_fired.clear()
	if player_card != null:
		_consume_pending(player_card, false)
	if enemy_card != null:
		_consume_pending(enemy_card, true)
	for key in _zone.keys():
		var e: Dictionary = _zone[key]
		if String(e["zone"]) == EXHAUST:
			var side := bool(e["enemy"])
			var facing: PlayerData = enemy_card if not side else player_card
			_fire_for(e["card"], side, "whileinexhaust", facing, not side)


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
			if card != null and not _zone.has(_k(card, pair[1])):
				_zone[_k(card, pair[1])] = {"card": card, "zone": FIELD, "enemy": pair[1]}
				fresh.append([card, pair[1]])
	if not _match_started:
		_match_started = true
		for pair in fresh:
			_fire_for(pair[0], pair[1], "matchstart", null, not pair[1])


## This round's line-ups: drafted cards leave the field for COMBAT.
func round_lineups(player_lineup: Array, enemy_lineup: Array) -> void:
	_lineup = {false: player_lineup.duplicate(), true: enemy_lineup.duplicate()}
	for pair in [[player_lineup, false], [enemy_lineup, true]]:
		for thing in pair[0]:
			var card := thing as PlayerData
			if card != null:
				# Round AA: "card_played" for Stats.csv (Buer's "eight have been
				# active at some point" counts first plays).
				var first := not _played_once.has(_k(card, pair[1]))
				_played_once[_k(card, pair[1])] = true
				_event("card_played", card, pair[1], {"first": "yes" if first else "no"})
				_move(card, pair[1], COMBAT)


## The round is over. `round_end` for the cards that played it, then they go
## to the EXHAUST - which fires `contemplation` for each.
func round_finished() -> void:
	var played: Array = []
	for key in _zone.keys():
		if String(_zone[key]["zone"]) == COMBAT:
			played.append([_zone[key]["card"], bool(_zone[key]["enemy"])])
	# AFTER THE COMBAT (round Z): every card in the match, any zone - Carl's
	# "while in exhaust ... after Tier IV combat".
	for key in _zone.keys():
		var e: Dictionary = _zone[key]
		_fire_for(e["card"], bool(e["enemy"]), "aftercombat", null, not bool(e["enemy"]))
	for pair in played:
		_fire_for(pair[0], pair[1], "roundend", null, not pair[1])
	for pair in played:
		_exhausted_round[pair[1]].append(pair[0])
		_move(pair[0], pair[1], EXHAUST)
	# MANFRED: "send this unit to the exhaust and replace it with a Rose Unit
	# Token". He plays his duel first; the token takes his place now, in the
	# exhaust like him, and comes back with everyone at the end of the cycle.
	var asks := _replace_after_round.duplicate()
	_replace_after_round.clear()
	for ask in asks:
		_make_token(String(ask["kind"]), ask["card"], bool(ask["side"]), ask["source"])


func zone_of(card: PlayerData, side_is_enemy: int = -1) -> String:
	if side_is_enemy >= 0:
		return String((_zone.get(_k(card, side_is_enemy == 1), {}) as Dictionary).get("zone", ""))
	for side in [false, true]:
		if _zone.has(_k(card, side)):
			return String(_zone[_k(card, side)]["zone"])
	return ""


func _zone_for(card: PlayerData, side_is_enemy: bool) -> String:
	return String((_zone.get(_k(card, side_is_enemy), {}) as Dictionary).get("zone", ""))


## Every card of one side in one zone ("" = every zone).
func cards_in(side_is_enemy: bool, zone: String = "") -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for key in _zone.keys():
		var e: Dictionary = _zone[key]
		if bool(e["enemy"]) == side_is_enemy and (zone == "" or String(e["zone"]) == zone):
			out.append(e["card"])
	return out


func _move(card: PlayerData, side_is_enemy: bool, to: String) -> void:
	var key := _k(card, side_is_enemy)
	var was := _zone_for(card, side_is_enemy)
	_zone[key] = {"card": card, "zone": to, "enemy": side_is_enemy}
	if was == to:
		return
	if to == EXHAUST:
		_maybe_ask_side(card, side_is_enemy)
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
	# The shot used up this round's keeper shifts (round AA, C3).
	_keeper_shift_round = {false: 0.0, true: 0.0}
	if scored:
		# RULING (round AA): Rose tokens last until a goal. Then every
		# original walks back on in its token's place.
		if rose_ends_on_goal:
			end_tokens("rose")
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
	var total := card.get_attack_power() + int(side_bonus.get(is_enemy, 0)) + counter(card, is_enemy, "power")
	for b in _buffs:
		if b.matches(card, is_enemy):
			total += b.attack
	return clampi(total, 0, max_power)


func defense_power(card: PlayerData, is_enemy: bool) -> int:
	if card == null:
		return 0
	var total := card.get_defense_power() + int(side_bonus.get(is_enemy, 0)) + counter(card, is_enemy, "power")
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
#  WHAT THE SCREENS AND THE MATCH READ (round Z, C2)
# =============================================================

## How many counters of that kind are on this card ("" = all kinds, added up
## by size, so a -1 power counter counts as one counter).
func counter(card: PlayerData, side_is_enemy: bool, kind: String = "") -> int:
	var on: Dictionary = _counters.get(_k(card, side_is_enemy), {})
	if kind != "":
		return int(on.get(kind, 0))
	var n := 0
	for k in on.keys():
		n += absi(int(on[k]))
	return n


## Every counter on this card, {kind: n}. A copy.
func counters_on(card: PlayerData, side_is_enemy: bool) -> Dictionary:
	return (_counters.get(_k(card, side_is_enemy), {}) as Dictionary).duplicate()


## What a side holds: pool(false, "ore").
func pool(side_is_enemy: bool, kind: String = "ore") -> int:
	return int((_pool[side_is_enemy] as Dictionary).get(kind, 0))


## Does this card carry that creature type this match ("swan")?
func is_kind(card: PlayerData, side_is_enemy: bool, kind: String) -> bool:
	if card == null:
		return false
	if card.extra_tags.has(kind):
		return true
	return bool((_kinds.get(_k(card, side_is_enemy), {}) as Dictionary).get(kind, false))


## How many tokens a side controls: Rose and Swan Unit tokens, and - while
## `swans_count_as_tokens` is on in Tuning.csv - every Swan.
func token_count(side_is_enemy: bool) -> int:
	var n := 0
	for card in cards_in(side_is_enemy):
		if _held.has(_k(card, side_is_enemy)):
			continue
		if card.is_token() or (swans_are_tokens and is_kind(card, side_is_enemy, "swan")):
			n += 1
	return n


## THE PENDING-BUFF WINDOW (ruling F3). One line per "next" effect still
## waiting, in words: "2 x next swan: 1 off their keeper".
func pending_lines(side_is_enemy: bool) -> Array[String]:
	var out: Array[String] = []
	for p in _pending:
		if bool(p["side"]) != side_is_enemy:
			continue
		var ability: AbilityData = p["ability"]
		var who := "card"
		match String(p["kind"]):
			"next_self": who = (p["source"] as PlayerData).player_name
			"next_enemy": who = "enemy"
			"next_tier_ally": who = "ally in the next tier"
			_: who = "ally"
		var filter := String(p["filter"])
		if filter != "":
			who = "%s %s" % [filter.replace("+", " "), who]
		out.append("%d x next %s: %s" % [int(p["count"]), who, _effect_words(ability)])
	return out


func _effect_words(ability: AbilityData) -> String:
	match ability.effect:
		"addpower": return "%+d power in combat" % ability.value
		"addattack": return "%+d power in combat" % ability.value
		"adddefense": return "%+d defence in combat" % ability.value
		"drainstamina": return "%d off their keeper" % ability.value
		"restorestamina": return "+%d to your keeper" % ability.value
		"addcounter": return "%+d %s counter" % [ability.value, ability.effect_arg]
		"makeswan": return "becomes a Swan"
	return ability.effect


## What a card carries this match, in a few words for the draft card:
## "burn 1  power -1  SWAN". Blank when nothing.
func marks_for(card: PlayerData, side_is_enemy: bool) -> String:
	var bits: PackedStringArray = PackedStringArray()
	var on := counters_on(card, side_is_enemy)
	for kind in on.keys():
		var n := int(on[kind])
		if n != 0:
			bits.append("%s %s" % [kind, ("%+d" % n) if kind == "power" else str(n)])
	# RULING F4 / Q7: priority is its own number. Shown when the power moved.
	if int(on.get("power", 0)) != 0 and card != null:
		bits.append("priority %d" % card.get_ability_priority())
	if card != null and card.is_token():
		bits.append("TOKEN")
	elif is_kind(card, side_is_enemy, "swan"):
		bits.append("SWAN")
	return "  ".join(bits)


## Does an Emblem on this side give this card something to do when it is
## revealed (Zepar's Swan)? Then the draft card gets a SHOW button even if
## its own text has no Reveal.
func emblem_reveal_for(card: PlayerData, side_is_enemy: bool) -> bool:
	for thing in (_emblems.get(side_is_enemy, []) as Array):
		var badge := thing as ClassBook.Emblem
		if badge == null or badge.basic_ability == "" or not EmblemBook.feeds_basic(card, badge):
			continue
		for piece in badge.basic_ability.split(";"):
			var ability := db.get_ability(String(piece).strip_edges())
			if ability == null or ability.trigger != "reveal":
				continue
			if ability.effect == "makeswan" and is_kind(card, side_is_enemy, "swan"):
				continue
			if _condition_ok(ability, card, side_is_enemy, null, not side_is_enemy):
				return true
	return false


# =============================================================
#  THE KEEPER AND THE REFEREE (round AA, phase C3)
# =============================================================

## How much likelier that keeper is to be BEATEN, in percentage points, now.
func keeper_shift(keeper_is_enemy: bool) -> float:
	return float(_keeper_shift_round.get(keeper_is_enemy, 0.0)) \
		+ float(_keeper_shift_match.get(keeper_is_enemy, 0.0))


## The fouls have been rolled: this round's foul shifts are used up.
func fouls_settled() -> void:
	_foul_shift_round = {false: 0.0, true: 0.0}


## + % that side commits a foul, now.
func foul_shift(side_is_enemy: bool) -> float:
	return float(_foul_shift_round.get(side_is_enemy, 0.0)) \
		+ float(_foul_shift_match.get(side_is_enemy, 0.0))


## The referee's-bar segments abilities added against that side since the
## last call. The match hands them to Referee.add_heat() at the fouls.
func take_heat(side_is_enemy: bool) -> float:
	var n := float(_heat_add.get(side_is_enemy, 0.0))
	_heat_add[side_is_enemy] = 0.0
	return n


## Spend that side's coin flip, if it has one (Manfred).
func use_coin_flip(side_is_enemy: bool) -> bool:
	if int(_coin_flips.get(side_is_enemy, 0)) <= 0:
		return false
	_coin_flips[side_is_enemy] = 0
	return true


func coin_flips(side_is_enemy: bool) -> int:
	return int(_coin_flips.get(side_is_enemy, 0))


func _keeper_effect(ability: AbilityData, source: PlayerData, keeper_is_enemy: bool) -> void:
	var who := "away" if keeper_is_enemy else "home"
	var name_text := source.player_name if source != null else "?"
	match ability.effect:
		"goaliechance":
			if ability.scope == "match":
				_keeper_shift_match[keeper_is_enemy] = float(_keeper_shift_match[keeper_is_enemy]) + float(ability.value)
			else:
				_keeper_shift_round[keeper_is_enemy] = float(_keeper_shift_round[keeper_is_enemy]) + float(ability.value)
			log_lines.append("      %s: the %s keeper is %+d%% to be beaten (now %+.0f%%)" % [
				name_text, who, ability.value, keeper_shift(keeper_is_enemy)])
		"goalieshield":
			_stamina_pending.append({"enemy_side": keeper_is_enemy, "delta": 0, "shield": ability.value})
			log_lines.append("      %s: +%d shield on the %s keeper" % [name_text, ability.value, who])
		"removeshields":
			_stamina_pending.append({"enemy_side": keeper_is_enemy, "delta": 0, "clear_shields": true})
			log_lines.append("      %s: every shield off the %s keeper" % [name_text, who])


func _referee_effect(ability: AbilityData, source: PlayerData, source_is_enemy: bool) -> void:
	var name_text := source.player_name if source != null else "?"
	var against := not source_is_enemy
	match ability.effect:
		"foulheat":
			_heat_add[against] = float(_heat_add[against]) + float(ability.value)
			log_lines.append("      %s: +%d on the referee's bar against the %s side" % [
				name_text, ability.value, "away" if against else "home"])
		"foulchance":
			if ability.scope == "match":
				_foul_shift_match[against] = float(_foul_shift_match[against]) + float(ability.value)
			else:
				_foul_shift_round[against] = float(_foul_shift_round[against]) + float(ability.value)
			log_lines.append("      %s: the %s side is %+d%% likelier to foul (now %+.0f%%)" % [
				name_text, "away" if against else "home", ability.value, foul_shift(against)])
		"foulcoinflip":
			_coin_flips[source_is_enemy] = 1
			log_lines.append("      %s: the next foul of the %s side is a coin toss" % [
				name_text, "away" if source_is_enemy else "home"])


# =============================================================
#  ASKING THE PLAYER (round AA)
# =============================================================

## Does this ability need a yes from this side?
func needs_yes(ability: AbilityData, side_is_enemy: bool) -> bool:
	if not bool(interactive.get(side_is_enemy, false)):
		return false
	return ability.ask or (ability.cost_kind == "ore" and ask_before_ore)


## BEFORE A DUEL: the abilities of this card (and its Emblem rows) that could
## go off in the coming duel AND need a yes - a Cost it can pay, or an Ask.
## The match asks you about each and calls consent().
func duel_questions(card: PlayerData, side_is_enemy: bool, role: String,
		opponent: PlayerData, opponent_is_enemy: bool) -> Array[AbilityData]:
	var out: Array[AbilityData] = []
	if card == null or not bool(interactive.get(side_is_enemy, false)):
		return out
	var key := _k(card, side_is_enemy)
	var was = _role.get(key, null)
	_role[key] = role
	var wanted: Array[String] = ["flip", "onduelstart", "onattack" if role == "attack" else "ondefend"]
	var cells: Array[String] = [card.active_attack_ability() if role == "attack" or not role_side else card.active_defend_ability()]
	if not role_side:
		cells = [card.active_attack_ability(), card.active_defend_ability()]
	var rows: Array[AbilityData] = []
	for cell in cells:
		for piece in String(cell).split(";"):
			var a := db.get_ability(String(piece).strip_edges())
			if a != null:
				rows.append(a)
	for thing in (_emblems.get(side_is_enemy, []) as Array):
		var badge := thing as ClassBook.Emblem
		if badge != null and badge.basic_ability != "" and EmblemBook.feeds_basic(card, badge):
			for piece in badge.basic_ability.split(";"):
				var a := db.get_ability(String(piece).strip_edges())
				if a != null:
					rows.append(a)
	var ore_left := pool(side_is_enemy, "ore")
	for a in rows:
		if not wanted.has(a.trigger) or not needs_yes(a, side_is_enemy):
			continue
		if a.cost_kind == "ore" and ore_left < a.cost_amount:
			continue
		if not _condition_ok(a, card, side_is_enemy, opponent, opponent_is_enemy):
			continue
		if a.max_uses > 0:
			var use_key := ("side%d" % int(side_is_enemy)) if a.max_shared else key
			use_key += "|" + a.id
			if a.max_per == "cycle":
				use_key += "|cycle%d" % cycle_number
			elif a.max_per == "round":
				use_key += "|round%d" % round_number
			if int(_uses.get(use_key, 0)) >= a.max_uses:
				continue
		out.append(a)
	if was == null:
		_role.erase(key)
	else:
		_role[key] = was
	return out


## Your answer to one of duel_questions(), for this duel.
func consent(card: PlayerData, side_is_enemy: bool, ability_id: String, yes: bool) -> void:
	_consent[_k(card, side_is_enemy) + "|" + ability_id] = yes


func _queue_ask(ask: Dictionary) -> void:
	_ask_serial += 1
	ask["id"] = _ask_serial
	_asks.append(ask)


## The questions waiting for the match, oldest first. Each is a Dictionary:
##   kind "confirm"  yes / no                    answer(ask, true)
##   kind "pick"     one of ask["options"]       answer(ask, card)
##   kind "side"     "attack" / "defend"         answer(ask, "attack")
## and ask["text"] says it in words.
func take_asks() -> Array:
	var out := _asks.duplicate()
	_asks.clear()
	return out


func answer(ask: Dictionary, choice) -> void:
	var side := bool(ask["side"])
	match String(ask["kind"]):
		"confirm":
			if bool(choice):
				_apply_one(ask["ability"], ask["card"], side, ask.get("opponent"),
					bool(ask.get("opponent_enemy", not side)), ask.get("badge"), true)
			else:
				log_lines.append("      you said no to %s" % (ask["ability"] as AbilityData).id)
		"pick":
			var chosen := choice as PlayerData
			if chosen == null or not (ask["options"] as Array).has(chosen):
				chosen = ask["default"]
			_make_token(String(ask["token"]), chosen, side, ask["card"])
		"side":
			set_side_up(ask["card"], side, String(choice))


## What happens when nobody answers: yes, the engine's own pick, the side it
## played last.
func answer_default(ask: Dictionary) -> void:
	match String(ask["kind"]):
		"confirm":
			answer(ask, true)
		"pick":
			answer(ask, ask["default"])
		"side":
			answer(ask, String(ask["default"]))


## RULING F2: which side of this card counts outside a duel, this cycle.
func set_side_up(card: PlayerData, side_is_enemy: bool, slot: String) -> void:
	if not (slot in ["attack", "defend"]):
		return
	_side_up[_k(card, side_is_enemy)] = {"slot": slot, "cycle": cycle_number}


func side_up(card: PlayerData, side_is_enemy: bool) -> String:
	var up: Dictionary = _side_up.get(_k(card, side_is_enemy), {})
	if not up.is_empty() and int(up.get("cycle", -1)) == cycle_number:
		return String(up["slot"])
	return String(_role.get(_k(card, side_is_enemy), "attack"))


## A card is going to the exhaust. If BOTH its sides have something to do out
## there, you are asked which one stays up - once per cycle (ruling F2).
func _maybe_ask_side(card: PlayerData, side_is_enemy: bool) -> void:
	if not role_side or not bool(interactive.get(side_is_enemy, false)):
		return
	var up: Dictionary = _side_up.get(_k(card, side_is_enemy), {})
	if not up.is_empty() and int(up.get("cycle", -1)) == cycle_number:
		return
	if not (_outside_text(card.active_attack_ability()) and _outside_text(card.active_defend_ability())):
		return
	var played := String(_role.get(_k(card, side_is_enemy), "attack"))
	set_side_up(card, side_is_enemy, played)
	_queue_ask({"kind": "side", "side": side_is_enemy, "card": card, "default": played,
		"attack_text": card.attack_text, "defend_text": card.defend_text,
		"text": "%s goes to the exhaust. Which side stays up this cycle?" % card.player_name})


func _outside_text(cell: String) -> bool:
	for piece in cell.split(";"):
		var a := db.get_ability(String(piece).strip_edges())
		if a != null and OUTSIDE_DUEL.has(a.trigger):
			return true
	return false


## Which of this card's abilities went off in the duel just played.
func fired_in_duel(card: PlayerData, side_is_enemy: bool) -> Array:
	return (_fired.get(_k(card, side_is_enemy), []) as Array).duplicate()


## ROUND AA: every token of that kind goes home. The original walks back on
## in the token's place and zone; the body gets its card back (take_swaps).
func end_tokens(kind: String = "rose") -> void:
	for swap in _all_swaps:
		if not bool(swap.get("active", false)) or String(swap.get("kind", "")) != kind:
			continue
		var side := bool(swap["side"])
		var token: PlayerData = swap["new"]
		var original: PlayerData = swap["old"]
		var where := _zone_for(token, side)
		_zone.erase(_k(token, side))
		_held.erase(_k(original, side))
		_zone[_k(original, side)] = {"card": original, "zone": where if where != "" else FIELD, "enemy": side}
		swap["active"] = false
		_swaps.append({"side": side, "old": token, "new": original, "kind": kind, "active": false})
		log_lines.append("      the %s Unit token goes; %s is back" % [kind.capitalize(), original.player_name])


## ---- FOR TOOLS, AND ONE DAY FOR MINES AND ITEMS ----
## Put something into a side's pool without an ability (Ore from a mine).
func add_to_pool(side_is_enemy: bool, kind: String, n: int) -> void:
	_pool_add(side_is_enemy, kind, n)


## Put a counter on a card without an ability.
func put_counter(card: PlayerData, side_is_enemy: bool, kind: String, n: int = 1) -> void:
	_add_counter(card, side_is_enemy, kind, n, null)


## Give a card a creature type without an ability ("swan").
func make_kind(card: PlayerData, side_is_enemy: bool, kind: String) -> void:
	var key := _k(card, side_is_enemy)
	if not _kinds.has(key):
		_kinds[key] = {}
	(_kinds[key] as Dictionary)[kind] = true


## The bodies to re-card since the last call: [{side, old, new}].
func take_swaps() -> Array:
	var out := _swaps.duplicate()
	_swaps.clear()
	return out


## Every token still standing, so full time can put the originals back.
func all_swaps() -> Array:
	var out: Array = []
	for swap in _all_swaps:
		if bool(swap.get("active", false)):
			out.append(swap)
	return out


## The events since the last call, for Stats.csv: [{event, facts, enemy}].
func take_events() -> Array:
	var out := _events.duplicate()
	_events.clear()
	return out


## The Emblems a side has on the field. The match sets them every round.
func set_emblems(side_is_enemy: bool, badges: Array) -> void:
	_emblems[side_is_enemy] = badges.duplicate()


func _event(event: String, card: PlayerData, side_is_enemy: bool, extra: Dictionary = {}) -> void:
	var facts := {}
	if card != null:
		facts = {"class": card.active_unit_type(), "tier": card.get_tier_clean(),
			"card": card.player_name, "element": card.active_element()}
	facts.merge(extra, true)
	_events.append({"event": event, "facts": facts, "enemy": side_is_enemy})


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
		_role[_k(attacker, attacker_is_enemy)] = "attack"
		_outcome.erase(_k(attacker, attacker_is_enemy))
	if defender != null:
		_role[_k(defender, defender_is_enemy)] = "defend"
		_outcome.erase(_k(defender, defender_is_enemy))

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


## Put a role on a card without a duel - for tools.
func set_role(card: PlayerData, is_enemy: bool, role: String) -> void:
	_role[_k(card, is_enemy)] = role


## After a duel is decided.
func resolve_duel_outcome(winner: PlayerData, winner_is_enemy: bool,
		loser: PlayerData, loser_is_enemy: bool) -> void:
	if winner != null:
		_outcome[_k(winner, winner_is_enemy)] = "won"
	if loser != null:
		_outcome[_k(loser, loser_is_enemy)] = "lost"
	_fire_for(winner, winner_is_enemy, "onwinduel", loser, loser_is_enemy)
	_fire_for(loser, loser_is_enemy, "onloseduel", winner, winner_is_enemy)
	_fire_for(winner, winner_is_enemy, "afterduel", loser, loser_is_enemy)
	_fire_for(loser, loser_is_enemy, "afterduel", winner, winner_is_enemy)
	# "Your last unit won combat" - remembered AFTER this duel's own abilities,
	# so it means the PREVIOUS duel to whoever asks next.
	_last_result[winner_is_enemy] = "won"
	_last_result[loser_is_enemy] = "lost"
	# This duel's yes / no answers are spent.
	_consent.clear()


## Moments where BOTH of a card's abilities are looked at: nothing about
## them belongs to one role.
const BOTH_SIDES: Array[String] = ["passive", "matchstart"]

## Moments OUTSIDE a duel, where ruling F2's chosen side counts.
const OUTSIDE_DUEL: Array[String] = ["whileinexhaust", "endofcycle", "aftercombat",
	"goaliesave", "ongoal", "onconcede", "rejuvenation"]

## Moments the match can stop and ask at (after a reveal, a round, a cycle).
## Anything else happens inside a duel and is asked BEFORE it.
const ASK_AFTER: Array[String] = ["reveal", "contemplation", "roundend", "aftercombat",
	"endofcycle", "rejuvenation", "matchstart", "goaliesave", "ongoal", "onconcede"]


func _fire_for(card: PlayerData, is_enemy: bool, trigger: String,
		opponent: PlayerData, opponent_is_enemy: bool) -> void:
	if card == null:
		return
	# ============ ONE SIDE PER DUEL (ruling F1 / F2) ============
	# Its role in its duel, or - outside a duel - the role it played last.
	# A card that has not duelled yet counts as attacking.
	var slots: Array[String] = ["attack", "defend"]
	var key := _k(card, is_enemy)
	if role_side and not BOTH_SIDES.has(trigger):
		var played: Array[String] = [String(_role.get(key, "attack"))]
		slots = played
		# REVEAL comes before anyone knows who attacks (ruling F3). The side
		# that HAS a reveal ability fires - the Attack side if both do - so a
		# card whose only Reveal is on its Defend side still works, and a card
		# with two never fires twice.
		# (Two typed lists, not `[a] if c else [b]` - that makes an untyped
		# Array and fails silently at runtime. The typed-array rule.)
		if trigger == "reveal" and not _role.has(key):
			var only_defend: Array[String] = ["defend"]
			var only_attack: Array[String] = ["attack"]
			if not _slot_has(card.active_attack_ability(), "reveal") \
					and _slot_has(card.active_defend_ability(), "reveal"):
				slots = only_defend
			else:
				slots = only_attack
	# ============ RULING F2 (round AA): ONE SIDE UP OUTSIDE A DUEL ============
	# Chosen once per cycle - by you, when the card goes to the exhaust; until
	# then, and for the other side, the side it played last.
	if role_side and OUTSIDE_DUEL.has(trigger):
		var up: Dictionary = _side_up.get(key, {})
		if not up.is_empty() and int(up.get("cycle", -1)) == cycle_number:
			var chosen: Array[String] = [String(up["slot"])]
			slots = chosen
	for slot in slots:
		var cell := card.active_attack_ability() if slot == "attack" else card.active_defend_ability()
		# A CELL MAY NAME SEVERAL ROWS, separated by semicolons, so one
		# sentence with two halves ("+1 now. If this wins: ...") is two rows.
		for piece in String(cell).split(";"):
			var ability := db.get_ability(String(piece).strip_edges())
			if ability == null or ability.trigger != trigger:
				continue
			_apply_one(ability, card, is_enemy, opponent, opponent_is_enemy)
	# ============ THE EMBLEMS' BASIC ABILITIES (round Z) ============
	# Every card that feeds an Emblem on its side's field carries that
	# Emblem's Basic Ability rows too. A token is a card like any other here.
	for thing in (_emblems.get(is_enemy, []) as Array):
		var badge := thing as ClassBook.Emblem
		if badge == null or badge.basic_ability == "" or not EmblemBook.feeds_basic(card, badge):
			continue
		for piece in badge.basic_ability.split(";"):
			var ability := db.get_ability(String(piece).strip_edges())
			if ability == null or ability.trigger != trigger:
				continue
			_apply_one(ability, card, is_enemy, opponent, opponent_is_enemy, badge)


# =============================================================
#  THE ONE PLACE THAT KNOWS WHAT AN EFFECT DOES
# =============================================================

func _apply_one(ability: AbilityData, source: PlayerData, source_is_enemy: bool,
		opponent: PlayerData, opponent_is_enemy: bool, badge: ClassBook.Emblem = null,
		answered: bool = false) -> void:

	# ============ THE If COLUMN (round Y) ============
	# Before anything else: a condition that is not met means it did not
	# happen - not counted, not spent against its Max.
	if not _condition_ok(ability, source, source_is_enemy, opponent, opponent_is_enemy):
		return

	# ============ THE MAX COLUMN ============
	#
	# "(Max 5)" on a card means it goes off five times in a match and then
	# stops. A Max of `1/cycle` counts per cycle, `1/round` per round, and
	# `2/cycle/side` counts for the whole side (Belphegor's Emblem).
	var use_key := ""
	if ability.max_uses > 0 and source != null:
		use_key = ("side%d" % int(source_is_enemy)) if ability.max_shared \
			else _k(source, source_is_enemy)
		use_key += "|" + ability.id
		if ability.max_per == "cycle":
			use_key += "|cycle%d" % cycle_number
		elif ability.max_per == "round":
			use_key += "|round%d" % round_number
		if int(_uses.get(use_key, 0)) >= ability.max_uses:
			return

	# ============ THE Cost COLUMN (round Z) ============
	# "Consume 3 Ore:" - not enough Ore and it simply does not happen.
	if ability.cost_kind == "ore" and pool(source_is_enemy, "ore") < ability.cost_amount:
		return

	# ============ ASK THE PLAYER (round AA) ============
	if not answered and needs_yes(ability, source_is_enemy):
		if ASK_AFTER.has(ability.trigger):
			# The match will ask, and call answer(). Nothing happens yet.
			_queue_ask({"kind": "confirm", "side": source_is_enemy, "card": source,
				"ability": ability, "opponent": opponent, "opponent_enemy": opponent_is_enemy,
				"badge": badge,
				"text": "%s - %s" % [source.player_name, ability.plain()]})
			return
		# In a duel: the answer was asked before it. No answer = yes.
		var said = _consent.get(_k(source, source_is_enemy) + "|" + ability.id, null)
		if said != null and not bool(said):
			log_lines.append("      %s: you said no to %s" % [source.player_name, ability.id])
			return

	if ability.cost_kind == "ore":
		_pool_add(source_is_enemy, "ore", -ability.cost_amount)
		_event("ore_spent", source, source_is_enemy, {"amount": str(ability.cost_amount)})
		log_lines.append("      %s pays %d Ore (%d left)" % [source.player_name, ability.cost_amount,
			pool(source_is_enemy, "ore")])

	if use_key != "":
		_uses[use_key] = int(_uses.get(use_key, 0)) + 1

	# ============ ONE TRIGGER ============
	#
	# Counted HERE and nowhere else, because this is the only line the game
	# reaches when an ability has actually gone off — past the trigger match,
	# past the priority sort, about to change a number. The foul system reads
	# it after the combat. See foul_book.gd.
	note_trigger(source_is_enemy)
	if source != null:
		var fk := _k(source, source_is_enemy)
		if not _fired.has(fk):
			_fired[fk] = []
		(_fired[fk] as Array).append(ability.id)
	if badge != null:
		_event("emblem_basic", source, source_is_enemy, {"emblem": badge.star, "effect": ability.effect})

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
		else:
			_keeper_effect(ability, source, keeper_is_enemy)
		return

	# --- The referee (round AA, C3) - always against a SIDE ---
	if ability.effect in ["foulheat", "foulchance", "foulcoinflip"]:
		_referee_effect(ability, source, source_is_enemy)
		return

	# --- The side's own pools: Ore, victory counters (round Z) ---
	if ability.effect == "gainore":
		_gain_ore(source, source_is_enemy, ability.value)
		return
	if ability.effect == "addcounter" and CardDatabase._normalise(ability.target) == "side":
		_pool_add(source_is_enemy, ability.effect_arg, ability.value)
		_event("counter_placed", source, source_is_enemy, {"kind": ability.effect_arg, "on": "side"})
		log_lines.append("      %s: +%d %s for the side (now %d)" % [source.player_name, ability.value,
			ability.effect_arg, pool(source_is_enemy, ability.effect_arg)])
		return

	# --- A token takes a card's place (round Z) ---
	if ability.effect == "createtoken":
		var kind := ability.effect_arg if ability.effect_arg != "" else "rose"
		var flat_target := CardDatabase._normalise(ability.target)
		if flat_target == "self":
			# He finishes his duel first; the swap happens when the round ends.
			if _zone_for(source, source_is_enemy) == COMBAT:
				_replace_after_round.append({"kind": kind, "card": source, "side": source_is_enemy, "source": source})
			else:
				_make_token(kind, source, source_is_enemy, source)
			return
		if ability.target.begins_with("replace:"):
			var victim := _pick_to_replace(source_is_enemy, ability.target.substr(8))
			if victim == null:
				return
			# RULING (round AA): YOU choose which unit the token replaces.
			if bool(interactive.get(source_is_enemy, false)):
				var options := _candidates_to_replace(source_is_enemy, ability.target.substr(8))
				if options.size() > 1:
					_queue_ask({"kind": "pick", "side": source_is_enemy, "card": source,
						"token": kind, "options": options, "default": victim,
						"text": "A %s Unit token takes the place of one of your units. Which one?" % kind.capitalize()})
					return
			_make_token(kind, victim, source_is_enemy, source)
		return

	# --- "THE NEXT ONE" waits for its card (round Y) ---
	var next := AbilityData.parse_next(ability.target)
	if not next.is_empty():
		if String(next["kind"]) == "ally":
			# Not "next": your card in that tier/kind THIS round, now.
			for thing in (_lineup.get(source_is_enemy, []) as Array):
				var mate := thing as PlayerData
				if mate != null and matches(mate, source_is_enemy, String(next["filter"])):
					_land_on(ability, mate, source_is_enemy, source, source_is_enemy)
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

	# --- Counters and swans land on CARDS (round Z) ---
	if ability.effect in ["addcounter", "removecounter", "makeswan"]:
		for pair in _cards_hit(ability.target, source, source_is_enemy, opponent, opponent_is_enemy):
			_land_on(ability, pair[0], pair[1], source, source_is_enemy)
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

	var lower := target.strip_edges().to_lower().replace("enemy_tier:", "enemytier:")
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


## The cards a counter or a swan lands on NOW: [[card, side], ...].
func _cards_hit(target: String, source: PlayerData, source_is_enemy: bool,
		opponent: PlayerData, opponent_is_enemy: bool) -> Array:
	var out: Array = []
	match CardDatabase._normalise(target):
		"self":
			out.append([source, source_is_enemy])
		"opponent":
			if opponent != null:
				out.append([opponent, opponent_is_enemy])
		"allallies":
			for card in cards_in(source_is_enemy):
				out.append([card, source_is_enemy])
		"allenemies":
			for card in cards_in(not source_is_enemy):
				out.append([card, not source_is_enemy])
	return out


# =============================================================
#  COUNTERS, ORE, TOKENS, SWANS (round Z, C2)
# =============================================================

func _pool_add(side_is_enemy: bool, kind: String, n: int) -> void:
	var p: Dictionary = _pool[side_is_enemy]
	p[kind] = maxi(0, int(p.get(kind, 0)) + n)
	if n > 0:
		var r: Dictionary = _pool_round[side_is_enemy]
		r[kind] = int(r.get(kind, 0)) + n


func _gain_ore(source: PlayerData, side_is_enemy: bool, n: int) -> void:
	_pool_add(side_is_enemy, "ore", n)
	_event("ore_gained", source, side_is_enemy, {"amount": str(n)})
	log_lines.append("      %s: +%d Ore (pool %d)" % [source.player_name if source != null else "?", n,
		pool(side_is_enemy, "ore")])


## One ability landing on one card: a buff, a counter, a swan, a keeper knock.
## Used by "the next one", by `ally:` targets and by the plain targets above.
func _land_on(ability: AbilityData, card: PlayerData, card_is_enemy: bool,
		source: PlayerData, source_is_enemy: bool) -> void:
	match ability.effect:
		"addcounter":
			_add_counter(card, card_is_enemy, ability.effect_arg, ability.value, source)
		"removecounter":
			_remove_counter(card, card_is_enemy, ability.effect_arg, ability.value)
		"makeswan":
			if is_kind(card, card_is_enemy, "swan"):
				return
			var key := _k(card, card_is_enemy)
			if not _kinds.has(key):
				_kinds[key] = {}
			(_kinds[key] as Dictionary)["swan"] = true
			_event("swan_made", card, card_is_enemy)
			log_lines.append("      %s becomes a Swan" % card.player_name)
		"drainstamina", "restorestamina", "addshotpower", "addcardchance", \
		"goaliechance", "goalieshield", "removeshields", "foulheat", "foulchance", "foulcoinflip":
			_land_side_effect(ability, source, source_is_enemy)
		"gainore":
			_gain_ore(source, source_is_enemy, ability.value)
		_:
			_land_buff(ability, card, card_is_enemy, source)


func _add_counter(card: PlayerData, card_is_enemy: bool, kind: String, n: int, source: PlayerData) -> void:
	if card == null or kind == "" or n == 0:
		return
	var key := _k(card, card_is_enemy)
	if not _counters.has(key):
		_counters[key] = {}
	var on: Dictionary = _counters[key]
	on[kind] = int(on.get(kind, 0)) + n
	_event("counter_placed", source if source != null else card, card_is_enemy,
		{"kind": kind, "on": card.player_name, "on_class": card.active_unit_type()})
	log_lines.append("      %s gets %+d %s counter (now %d)" % [card.player_name, n, kind, int(on[kind])])
	# ON_COUNTER: the card that received it gets its moment. Depth-capped, so
	# an ability that answers a counter with a counter cannot loop forever.
	if _depth < 3:
		_depth += 1
		_fire_for(card, card_is_enemy, "oncounter", null, not card_is_enemy)
		_depth -= 1


func _remove_counter(card: PlayerData, card_is_enemy: bool, kind: String, n: int) -> void:
	var on: Dictionary = _counters.get(_k(card, card_is_enemy), {})
	var kinds: Array = [kind] if kind != "" else on.keys()
	var left := maxi(1, absi(n))
	for k in kinds:
		while left > 0 and int(on.get(k, 0)) != 0:
			var v := int(on[k])
			on[k] = v - signi(v)
			left -= 1
		if int(on.get(k, 0)) == 0:
			on.erase(k)
	log_lines.append("      %s loses a counter" % card.player_name)


## Every card a token could replace, best first (the default first).
func _candidates_to_replace(side_is_enemy: bool, filter: String) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for card in cards_in(side_is_enemy):
		if card.is_token() or card.is_star() or _held.has(_k(card, side_is_enemy)):
			continue
		if _zone_for(card, side_is_enemy) == COMBAT or not matches(card, side_is_enemy, filter):
			continue
		out.append(card)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var za := 0 if _zone_for(a, side_is_enemy) == FIELD else 10
		var zb := 0 if _zone_for(b, side_is_enemy) == FIELD else 10
		return a.get_attack_power() + za < b.get_attack_power() + zb)
	return out


## Which of your cards a token replaces: one matching the filter ("water+I"),
## not a Star, not already a token, not already replaced. One still on the
## FIELD first (so the token can play this cycle), else one in the exhaust;
## the lowest power first, because the token gets its power anyway.
func _pick_to_replace(side_is_enemy: bool, filter: String) -> PlayerData:
	var best: PlayerData = null
	var best_score := 999
	for card in cards_in(side_is_enemy):
		if card.is_token() or card.is_star() or _held.has(_k(card, side_is_enemy)):
			continue
		if not matches(card, side_is_enemy, filter):
			continue
		var zone := _zone_for(card, side_is_enemy)
		if zone == COMBAT:
			continue
		var score := card.get_attack_power() + (0 if zone == FIELD else 10)
		if score < best_score:
			best_score = score
			best = card
	return best


## THE TOKEN. A copy of `original`: same tier, same power, same artwork, no
## abilities, the words ["<kind>", "token"]. The original goes to the exhaust
## and is held there; the token takes its zone and, through take_swaps(), its
## body on the pitch.
func _make_token(kind: String, original: PlayerData, side_is_enemy: bool, source: PlayerData) -> void:
	if original == null:
		return
	var token := original.duplicate() as PlayerData
	token.player_name = "%s Unit" % kind.capitalize()
	token.attack_ability_id = ""
	token.defend_ability_id = ""
	token.brew_attack_ability = ""
	token.brew_defend_ability = ""
	token.attack_text = "%s Unit token. It took %s's place." % [kind.capitalize(), original.player_name]
	token.defend_text = token.attack_text
	token.player_type = "Normal"
	token.extra_tags = PackedStringArray([kind, "token"])
	var was := _zone_for(original, side_is_enemy)
	if was == "":
		was = FIELD
	# The original to the exhaust (contemplation fires), held there.
	_move(original, side_is_enemy, EXHAUST)
	_held[_k(original, side_is_enemy)] = true
	_zone[_k(token, side_is_enemy)] = {"card": token, "zone": was, "enemy": side_is_enemy}
	var swap := {"side": side_is_enemy, "old": original, "new": token, "kind": kind, "active": true}
	_swaps.append(swap)
	_all_swaps.append(swap)
	_event("token_made", original, side_is_enemy, {"kind": kind,
		"by": source.player_name if source != null else ""})
	log_lines.append("      a %s Unit token takes %s's place" % [kind.capitalize(), original.player_name])


## Does this card match a filter like "water+I", "fire", "swan", "token"?
## AbilityData.card_matches() for everything printed on the card; the
## creature types gained in the match ("swan") are known only here.
func matches(card: PlayerData, side_is_enemy: bool, filter: String) -> bool:
	if card == null:
		return false
	for piece in filter.split("+"):
		var want := String(piece).strip_edges().to_lower()
		if want == "":
			continue
		if is_kind(card, side_is_enemy, want):
			continue
		if not AbilityData.card_matches(card, want):
			return false
	return true


# =============================================================
#  CONDITIONS AND "NEXT" (round Y, C1 - round Z, C2)
# =============================================================

func _condition_ok(ability: AbilityData, source: PlayerData, source_is_enemy: bool,
		opponent: PlayerData, opponent_is_enemy: bool) -> bool:
	if ability.condition.strip_edges() == "":
		return true
	var me := _k(source, source_is_enemy)
	for term in AbilityData.condition_terms(ability.condition):
		var word := String(term["word"])
		var arg := String(term["arg"])
		var ok := false
		match word:
			"defending":
				ok = String(_role.get(me, "")) == "defend"
			"attacking":
				ok = String(_role.get(me, "")) == "attack"
			"won":
				ok = String(_outcome.get(me, "")) == "won"
			"lost":
				ok = String(_outcome.get(me, "")) == "lost"
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
						if String(_role.get(_k(opponent, opponent_is_enemy), "attack")) == "attack" \
						else defense_power(opponent, opponent_is_enemy)
					ok = now < opponent.base_power_left
			"inexhaust":
				ok = _zone_for(source, source_is_enemy) == EXHAUST
			"infield":
				ok = _zone_for(source, source_is_enemy) == FIELD
			"incombat":
				ok = _zone_for(source, source_is_enemy) == COMBAT
			"hastag":
				ok = source.has_tag(arg) or is_kind(source, source_is_enemy, arg)
			# ---- round Z, C2 ----
			"hascounter":
				ok = counter(source, source_is_enemy, arg) != 0
			"enemyhascounter":
				ok = opponent != null and counter(opponent, opponent_is_enemy, arg) != 0
			"hastoken":
				ok = token_count(source_is_enemy) >= 1
			"tokensatleast":
				ok = token_count(source_is_enemy) >= maxi(1, int(arg))
			"isswan":
				ok = is_kind(source, source_is_enemy, "swan")
			"istoken":
				ok = source.is_token()
			"orethisround":
				ok = int((_pool_round[source_is_enemy] as Dictionary).get("ore", 0)) > 0
			"oreatleast":
				ok = pool(source_is_enemy, "ore") >= maxi(1, int(arg))
			"element":
				ok = CardDatabase._normalise(source.active_element()) == CardDatabase._normalise(arg)
			"exhaustedthisround":
				var bits := arg.split(":", true, 1)
				var need := maxi(1, int(String(bits[0])))
				var filter := String(bits[1]) if bits.size() > 1 else ""
				var n := 0
				for thing in (_exhausted_round[source_is_enemy] as Array):
					if matches(thing as PlayerData, source_is_enemy, filter):
						n += 1
				ok = n >= need
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
##
## Up to three passes, because landing one can make another: a burn counter
## landing fires on_counter, and Buer's "+1 during their combat" then waits
## for this same card - and its combat is NOW.
func _consume_pending(card: PlayerData, card_is_enemy: bool) -> void:
	for _pass in 3:
		var current := _pending
		_pending = []
		var kept: Array = []
		var landed := false
		for p in current:
			var take := bool(p["side"]) == card_is_enemy
			var fizzle := false
			if take:
				match String(p["kind"]):
					"next_self":
						take = p["source"] == card and bool(p["source_enemy"]) == card_is_enemy
					"next_ally":
						take = p["source"] != card and matches(card, card_is_enemy, String(p["filter"]))
					"next_tier_ally":
						# RULING R03: the VERY NEXT card - if it is not the kind
						# asked for, the effect is spent on nothing.
						take = p["source"] != card
						fizzle = take and not matches(card, card_is_enemy, String(p["filter"]))
					_:
						take = matches(card, card_is_enemy, String(p["filter"]))
			if not take:
				kept.append(p)
				continue
			if fizzle:
				log_lines.append("      %s's effect finds %s, who is not %s - it is lost" % [
					(p["source"] as PlayerData).player_name, card.player_name, p["filter"]])
			else:
				_land_on(p["ability"], card, card_is_enemy, p["source"], bool(p["source_enemy"]))
				landed = true
			p["count"] = int(p["count"]) - 1
			if int(p["count"]) > 0:
				kept.append(p)
		_pending = kept + _pending
		if not landed:
			return


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
	if ability.effect in ["foulheat", "foulchance", "foulcoinflip"]:
		_referee_effect(ability, source, source_is_enemy)
		return
	if ability.effect in ["goaliechance", "goalieshield", "removeshields"]:
		var own := CardDatabase._normalise(ability.target) == "owngoalie"
		_keeper_effect(ability, source, source_is_enemy if own else not source_is_enemy)
		return
	if ability.effect == "addshotpower":
		_shot_bonus[source_is_enemy] = int(_shot_bonus.get(source_is_enemy, 0)) + ability.value
		return
	if ability.effect == "addcardchance":
		card_chance[not source_is_enemy] = float(card_chance.get(not source_is_enemy, 0.0)) + float(ability.value)
		return
	var flat := CardDatabase._normalise(ability.target)
	# A drain hits THEIR keeper, a restore YOURS - unless the row names one.
	var keeper_is_enemy := not source_is_enemy
	if flat == "owngoalie" or (ability.effect == "restorestamina" and flat != "enemygoalie"):
		keeper_is_enemy = source_is_enemy
	var delta := -ability.value if ability.effect == "drainstamina" else ability.value
	_stamina_pending.append({"enemy_side": keeper_is_enemy, "delta": delta})
	log_lines.append("      %s: %s %d on the %s keeper (it was waiting)" % [
		source.player_name if source != null else "?", ability.effect, absi(delta),
		"away" if keeper_is_enemy else "home"])


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
