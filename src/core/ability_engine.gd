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
	## Round AB (C4): whose ability made it, so a negate can take it back.
	var source_key: String = ""

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
# ---- round AB, PHASE C4: bending the duel. Every one of these lasts the
# duel it was made in (cleared in begin_duel), except always_defending. ----
## key -> + / - on its place in the order abilities resolve (lower = first).
var _prio_mod: Dictionary = {}
## key -> "attack" / "defend": the side it is FORCED to use this duel.
var _force_slot: Dictionary = {}
## key -> the side of it that was negated this duel.
var _negated: Dictionary = {}
## key -> true: its ability cannot be negated or forced this duel (Herbert).
var _uncounterable: Dictionary = {}
## key -> true: its If column is ignored this duel (Leon).
var _ignore_if: Dictionary = {}
## key -> true: "always counts as defending" (Sallos) - for the match.
var _always_def: Dictionary = {}
## key -> the token whose power it used / gave this duel (Sven, Ignaz).
var _token_used: Dictionary = {}
## The card that switched to defender in the duel just resolved, or null -
## the match reads it (take_switch) and turns the duel round.
var _switch_card: PlayerData = null
var _switch_side := false
var _last_switch := {}

## key -> true once that card has played a duel this match (card_played).
var _played_once: Dictionary = {}
## ---- ROUND AC, PHASE C5: the zones in action ----
const C5_EFFECTS: Array[String] = ["swapintier", "sendtoexhaust", "swapfromexhaust",
	"exhaustotherreturn", "revealanother", "revealfromexhaust", "doubleattack"]
## Cards C5 moved between zones, for the match to show: [{card, side, zone}].
var _zone_moves: Array = []
## key(card that swapped in) -> the card it replaced (swapped_was).
var _swapped_out: Dictionary = {}
## key(card) -> the card it revealed from the exhaust (revealed_was).
var _revealed_from: Dictionary = {}
## Ingrid: the next card this side picks is revealed too.
var _reveal_next := {false: false, true: false}
## Lothar: key -> true, swap with the exhaust after its duel.
var _swap_after_duel: Dictionary = {}
## Exhaust swaps done for the coming duel, fired after begin_duel.
var _swaps_in: Array = []
## Tuning: does the AI save its Ore for its most expensive card (Q018)?
var ai_saves_ore := true
## Tuning: does a goal send every Rose token home (ruling, round AA)?
var rose_ends_on_goal := true


func _init(database: CardDatabase = null) -> void:
	db = database if database != null else CardDatabase.get_db()
	role_side = db == null or db.tune_bool("ability_uses_role_side", true)
	swans_are_tokens = db == null or db.tune_bool("swans_count_as_tokens", true)
	ask_before_ore = db == null or db.tune_bool("ask_before_spending_ore", true)
	rose_ends_on_goal = db == null or db.tune_bool("rose_tokens_end_on_goal", true)
	ai_saves_ore = db == null or db.tune_bool("ai_saves_ore", true)


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
	_prio_mod.clear()
	_force_slot.clear()
	_negated.clear()
	_uncounterable.clear()
	_ignore_if.clear()
	_token_used.clear()
	_switch_card = null
	# THE EXHAUST FIRST, THEN "THE NEXT ONE" (round AB). A card in the exhaust
	# that says "give a Tier II water unit priority" makes a waiting effect -
	# and the Tier II about to duel is the one it is for, so it must already
	# be waiting when this duel's waiting effects land.
	for key in _zone.keys():
		var e: Dictionary = _zone[key]
		if String(e["zone"]) == EXHAUST:
			var side := bool(e["enemy"])
			var facing: PlayerData = enemy_card if not side else player_card
			_fire_for(e["card"], side, "whileinexhaust", facing, not side)
	if player_card != null:
		_consume_pending(player_card, false)
	if enemy_card != null:
		_consume_pending(enemy_card, true)
	# ROUND AC (C5): a card that has just swapped in from the exhaust does
	# what the rest of its `exhaust_swap` rows say - now, for this duel.
	var swaps := _swaps_in.duplicate()
	_swaps_in.clear()
	for sw in swaps:
		var side := bool(sw["side"])
		var facing: PlayerData = enemy_card if not side else player_card
		_fire_for(sw["in"], side, "exhaustswap", facing, not side)


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
		# Round AB (Q005 / Q021): only when THEIR OWNER scores - the scoring
		# side's Rose tokens go home and its Swans turn back.
		if rose_ends_on_goal:
			end_tokens("rose", 1 if shooter_is_enemy else 0)
			end_swans(shooter_is_enemy)
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
		"doubleattack": return "printed power doubled"
		"swapfromexhaust": return "then swaps with the exhaust"
		"setpowerfromtoken": return "fights with a token's power"
		"changepriority": return "%+d priority" % ability.value
		"givepriority": return "resolves first"
	return ability.effect.replace("_", " ")


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
			if _condition_ok(ability, card, side_is_enemy, null, not side_is_enemy):
				return true
	return false


# =============================================================
#  BENDING THE DUEL (round AB, phase C4)
# =============================================================

const C4_EFFECTS: Array[String] = ["switchtodefender", "alwaysdefending", "swappower",
	"setpowerfromtoken", "useenemypower", "forceability", "negateability", "negatebuff",
	"changepriority", "givepriority", "uncounterable", "powerfromcount", "removecondition"]


## ---- what C4 did, for tools and screens ----
func forced_side(card: PlayerData, side_is_enemy: bool) -> String:
	return String(_force_slot.get(_k(card, side_is_enemy), ""))


func negated_side(card: PlayerData, side_is_enemy: bool) -> String:
	return String(_negated.get(_k(card, side_is_enemy), ""))


func priority_mod(card: PlayerData, side_is_enemy: bool) -> int:
	return int(_prio_mod.get(_k(card, side_is_enemy), 0))


func is_uncounterable(card: PlayerData, side_is_enemy: bool) -> bool:
	return _uncounterable.has(_k(card, side_is_enemy))


func ignores_if(card: PlayerData, side_is_enemy: bool) -> bool:
	return _ignore_if.has(_k(card, side_is_enemy))


func is_always_defending(card: PlayerData, side_is_enemy: bool) -> bool:
	return _always_def.has(_k(card, side_is_enemy))


## Is this card protected from negate / force this duel (Herbert, Q053)?
func _protected(card: PlayerData, side_is_enemy: bool) -> bool:
	return _uncounterable.has(_k(card, side_is_enemy))


## One C4 effect on one card. `card` is who it lands on; `source` whose it is.
func _bend(ability: AbilityData, card: PlayerData, card_is_enemy: bool, source: PlayerData,
		source_is_enemy: bool, opponent: PlayerData, opponent_is_enemy: bool) -> void:
	if card == null:
		return
	var key := _k(card, card_is_enemy)
	var hostile := card_is_enemy != source_is_enemy
	var who := card.player_name
	match ability.effect:
		"switchtodefender":
			if String(_role.get(key, "")) == "attack":
				_switch_card = card
				_switch_side = card_is_enemy
		"alwaysdefending":
			_always_def[key] = true
		"changepriority":
			_prio_mod[key] = int(_prio_mod.get(key, 0)) + ability.value
			log_lines.append("      %s: priority %+d (now %d)" % [who, ability.value,
				card.get_ability_priority() + int(_prio_mod[key])])
		"givepriority":
			_prio_mod[key] = int(_prio_mod.get(key, 0)) - 100
			log_lines.append("      %s resolves FIRST this duel" % who)
		"uncounterable":
			_uncounterable[key] = true
			log_lines.append("      %s cannot be countered this duel" % who)
		"removecondition":
			_ignore_if[key] = true
			log_lines.append("      %s: its If is ignored this duel" % who)
		"forceability":
			if hostile and _protected(card, card_is_enemy):
				log_lines.append("      %s cannot be forced" % who)
				return
			var slot := ability.effect_arg
			var playing := String(_role.get(key, "attack"))
			if slot == "other" or slot == "":
				slot = "defend" if playing == "attack" else "attack"
			_force_slot[key] = slot
			log_lines.append("      %s must use its %s side" % [who, slot.to_upper()])
			# On ITSELF ("this unit uses its attack ability") it happens now.
			if not hostile and slot != playing:
				var t := "onattack" if slot == "attack" else "ondefend"
				var cell := card.active_attack_ability() if slot == "attack" else card.active_defend_ability()
				for piece in cell.split(";"):
					var a := db.get_ability(String(piece).strip_edges())
					if a != null and a.trigger == t:
						_apply_one(a, card, card_is_enemy, opponent, opponent_is_enemy)
		"negateability":
			if hostile and _protected(card, card_is_enemy):
				log_lines.append("      %s cannot be countered" % who)
				return
			# Q050: the side it is using NOW is negated - a card that has
			# switched sides has dodged it.
			var side := String(_force_slot.get(key, _role.get(key, "attack")))
			_negated[key] = side
			var kept: Array[Buff] = []
			for b in _buffs:
				if b.scope == "duel" and b.source_key == key:
					continue
				kept.append(b)
			_buffs = kept
			log_lines.append("      %s's %s ability is NEGATED" % [who, side])
		"negatebuff":
			if hostile and _protected(card, card_is_enemy):
				return
			var kept2: Array[Buff] = []
			for b in _buffs:
				if b.card == card and b.side_is_enemy == card_is_enemy and (b.attack > 0 or b.defense > 0):
					continue
				kept2.append(b)
			_buffs = kept2
			log_lines.append("      %s loses its power buffs" % who)
		"swappower":
			# Q052: PRINTED powers. Against a token (Ignaz), the token's.
			if CardDatabase._normalise(ability.target) == "token":
				# Ignaz: this card takes the power of a token you own.
				var token := _pick_token(source, source_is_enemy)
				if token == null:
					return
				_token_used[_k(source, source_is_enemy)] = token
				_set_power(source, source_is_enemy, token.get_attack_power(), source)
				log_lines.append("      %s takes the power of %s (%d)" % [source.player_name, token.player_name, token.get_attack_power()])
			else:
				# The card it lands on and the source swap PRINTED power; the
				# source only changes if it is fighting too (not from the exhaust).
				var mine := source.get_attack_power()
				var theirs := card.get_attack_power()
				_set_power(card, card_is_enemy, mine, source)
				if _zone_for(source, source_is_enemy) == COMBAT and source != card:
					_set_power(source, source_is_enemy, theirs, source)
				log_lines.append("      %s swaps power with %s" % [source.player_name, who])
		"setpowerfromtoken":
			var token := _pick_token(source, source_is_enemy)
			if token == null:
				return
			_token_used[_k(source, source_is_enemy)] = token
			_set_power(card, card_is_enemy, token.get_attack_power(), source)
			log_lines.append("      %s fights with the power of %s (%d)" % [who, token.player_name, token.get_attack_power()])
		"useenemypower":
			if opponent != null:
				var now := attack_power(opponent, opponent_is_enemy) if String(_role.get(_k(opponent, opponent_is_enemy), "attack")) == "attack" else defense_power(opponent, opponent_is_enemy)
				_set_power(card, card_is_enemy, now, source)
		"powerfromcount":
			var n := _count_for(ability.effect_arg, card_is_enemy, ability.value)
			_set_power(card, card_is_enemy, n, source)
			log_lines.append("      %s: power = %d (%s)" % [who, n, ability.effect_arg])


## Make a card fight with exactly `power` this duel: a buff of the difference.
func _set_power(card: PlayerData, card_is_enemy: bool, power: int, source: PlayerData) -> void:
	var now_atk := attack_power(card, card_is_enemy)
	var now_def := defense_power(card, card_is_enemy)
	var buff := Buff.new()
	buff.scope = "duel"
	buff.card = card
	buff.side_is_enemy = card_is_enemy
	buff.attack = power - now_atk
	buff.defense = power - now_def
	buff.source_key = _k(source, card_is_enemy) if source != null else ""
	_buffs.append(buff)


## What power_from_count counts. victory = your side's victory counters;
## enemy_exhaust_II = their Tier II cards in the exhaust; field_objects =
## different elements on the pitch (and, in C6, structures), up to `cap`.
func _count_for(what: String, side_is_enemy: bool, cap: int) -> int:
	var n := 0
	match what:
		"victory":
			n = pool(side_is_enemy, "victory")
		"enemyexhaustii", "enemy_exhaust_ii":
			for c in cards_in(not side_is_enemy, EXHAUST):
				if c.get_tier_clean() == "II":
					n += 1
		"fieldobjects", "field_objects":
			var seen := {}
			for side in [false, true]:
				for c in cards_in(side):
					seen[CardDatabase._normalise(c.active_element())] = true
			n = seen.size()
			if cap > 0:
				n = mini(n, cap)
	return n


## The token a card uses (Sven, Ignaz): the one YOU picked before the duel
## (consent), else the weakest - Sven makes the ENEMY fight with it.
func _pick_token(source: PlayerData, side_is_enemy: bool) -> PlayerData:
	var picked = _consent.get(_k(source, side_is_enemy) + "|token", null)
	if picked is PlayerData:
		return picked
	var best: PlayerData = null
	for c in tokens_of(side_is_enemy):
		if best == null or c.get_attack_power() < best.get_attack_power():
			best = c
	return best


## Every token a side controls (the cards themselves), for a pick window.
func tokens_of(side_is_enemy: bool) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for card in cards_in(side_is_enemy):
		if _held.has(_k(card, side_is_enemy)):
			continue
		if card.is_token() or (swans_are_tokens and is_kind(card, side_is_enemy, "swan")):
			out.append(card)
	return out


## Your token pick for a duel (Q003).
func consent_token(card: PlayerData, side_is_enemy: bool, token: PlayerData) -> void:
	_consent[_k(card, side_is_enemy) + "|token"] = token


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

## The most Ore any ability of this side's cards (still in the match) costs.
func _biggest_ore_cost(side_is_enemy: bool) -> int:
	var top := 0
	for card in cards_in(side_is_enemy):
		for cell in [card.active_attack_ability(), card.active_defend_ability()]:
			for piece in String(cell).split(";"):
				var a := db.get_ability(String(piece).strip_edges())
				if a != null and a.cost_kind == "ore":
					top = maxi(top, a.cost_amount)
	return top


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
		if not wanted.has(a.trigger) or not (needs_yes(a, side_is_enemy) or needs_token_pick(a, side_is_enemy)):
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


## Round AB (Q003): does this ability make you choose one of SEVERAL tokens?
func needs_token_pick(ability: AbilityData, side_is_enemy: bool) -> bool:
	if not bool(interactive.get(side_is_enemy, false)):
		return false
	var uses_token := ability.effect == "setpowerfromtoken" \
		or (ability.effect == "swappower" and CardDatabase._normalise(ability.target) == "token")
	return uses_token and tokens_of(side_is_enemy).size() > 1


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
		"choose":
			var picked := choice as PlayerData
			if picked == null or not (ask["options"] as Array).has(picked):
				picked = ask["default"]
			match String(ask.get("action", "")):
				"exhaust_other":
					_do_exhaust_other(ask["card"], picked, side)


## What happens when nobody answers: yes, the engine's own pick, the side it
## played last.
func answer_default(ask: Dictionary) -> void:
	match String(ask["kind"]):
		"confirm":
			answer(ask, true)
		"pick", "choose":
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
func end_tokens(kind: String = "rose", only_side: int = -1) -> void:
	for swap in _all_swaps:
		if not bool(swap.get("active", false)) or String(swap.get("kind", "")) != kind:
			continue
		var side := bool(swap["side"])
		if only_side >= 0 and side != (only_side == 1):
			continue
		var token: PlayerData = swap["new"]
		var original: PlayerData = swap["old"]
		var where := _zone_for(token, side)
		_zone.erase(_k(token, side))
		_held.erase(_k(original, side))
		_zone[_k(original, side)] = {"card": original, "zone": where if where != "" else FIELD, "enemy": side}
		swap["active"] = false
		_swaps.append({"side": side, "old": token, "new": original, "kind": kind, "active": false})
		log_lines.append("      the %s Unit token goes; %s is back" % [kind.capitalize(), original.player_name])


## Round AB (Q021): every Swan of that side turns back at its goal.
func end_swans(side_is_enemy: bool) -> void:
	var n := 0
	for key in _kinds.keys():
		if String(key).ends_with("|%d" % (1 if side_is_enemy else 0)) and bool((_kinds[key] as Dictionary).get("swan", false)):
			(_kinds[key] as Dictionary).erase("swan")
			n += 1
	if n > 0:
		log_lines.append("      %d Swan(s) of the %s side turn back" % [n, "away" if side_is_enemy else "home"])


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

	# ROUND AB (C4): THE STACK RE-SORTS AS IT GOES. A priority change that
	# lands before a card resolves moves it in the queue (give / change
	# priority, mostly from the exhaust and from "next" effects).
	while not queue.is_empty():
		for e in queue:
			e["priority"] = _duel_priority(e["card"], shown, e["role"] == "attack") \
				+ int(_prio_mod.get(_k(e["card"], e["enemy"]), 0))
		queue.sort_custom(func(a, b):
			if a["priority"] == b["priority"]:
				return a["order"] < b["order"]
			return a["priority"] < b["priority"])
		var entry: Dictionary = queue.pop_front()
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

	# ============ SWITCH TO BEING THE DEFENDER (C4, ruling F1, Q047) ============
	# Abilities first, THEN the switch: the card now defends and uses its
	# Defend side, the other card attacks, and the winner attacks next as
	# always. The match reads take_switch() to turn the comparison round.
	_last_switch = {}
	if _switch_card != null:
		var flipper := _switch_card
		var flipper_enemy := _switch_side
		var other: PlayerData = defender if flipper == attacker else attacker
		_role[_k(flipper, flipper_enemy)] = "defend"
		if other != null:
			_role[_k(other, not flipper_enemy)] = "attack"
		log_lines.append("      %s switches to being the DEFENDER" % flipper.player_name)
		_fire_for(flipper, flipper_enemy, "ondefend", other, not flipper_enemy)
		_last_switch = {"card": flipper, "enemy": flipper_enemy}
		_switch_card = null


## Did a card switch to defender in the duel just resolved? {card, enemy} or
## {}. Read once by the match.
func take_switch() -> Dictionary:
	var out := _last_switch
	_last_switch = {}
	return out


## The token a card used in this duel (Sven, Ignaz), for the duel window.
func token_used(card: PlayerData, side_is_enemy: bool) -> PlayerData:
	return _token_used.get(_k(card, side_is_enemy), null)


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
	# ROUND AC (C5): Lothar's token - its doubled duel is done, now it goes
	# to the exhaust and one of the same tier comes back.
	for pair in [[winner, winner_is_enemy], [loser, loser_is_enemy]]:
		var c := pair[0] as PlayerData
		if c != null and _swap_after_duel.has(_k(c, pair[1])):
			_swap_after_duel.erase(_k(c, pair[1]))
			_swap_with_exhaust(c, pair[1])


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
	# ============ FORCED TO USE ONE SIDE (C4) ============
	# "Enemy has to use Attack Ability": its forced side answers its role's
	# moment - a defender forced to attack fires its ATTACK side's on_attack
	# rows when its on_defend moment comes.
	var wanted := trigger
	if _force_slot.has(key) and (trigger == "onattack" or trigger == "ondefend"):
		var forced: Array[String] = [String(_force_slot[key])]
		slots = forced
		wanted = "onattack" if String(_force_slot[key]) == "attack" else "ondefend"
	for slot in slots:
		# NEGATED (C4): that side of this card does nothing more this duel.
		if String(_negated.get(key, "")) == slot:
			continue
		var cell := card.active_attack_ability() if slot == "attack" else card.active_defend_ability()
		# A CELL MAY NAME SEVERAL ROWS, separated by semicolons, so one
		# sentence with two halves ("+1 now. If this wins: ...") is two rows.
		for piece in String(cell).split(";"):
			var ability := db.get_ability(String(piece).strip_edges())
			if ability == null or ability.trigger != wanted:
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
	# ROUND AB (Q018): THE AI SAVES FOR ITS BIGGEST CARD. A side nobody asks
	# (the other side) does not spend on a small Cost if that would leave it
	# unable to pay its most expensive one. `ai_saves_ore` in Tuning.csv.
	if ability.cost_kind == "ore" and not bool(interactive.get(source_is_enemy, false)) and ai_saves_ore:
		var biggest := _biggest_ore_cost(source_is_enemy)
		if ability.cost_amount < biggest and pool(source_is_enemy, "ore") - ability.cost_amount < biggest:
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
	if ability.effect == "removecounter" and CardDatabase._normalise(ability.target) == "side":
		_pool_add(source_is_enemy, ability.effect_arg, -ability.value)
		log_lines.append("      %s: -%d %s from the side (now %d)" % [source.player_name, ability.value,
			ability.effect_arg, pool(source_is_enemy, ability.effect_arg)])
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

	# --- C5 (round AC): effects about the SOURCE itself happen now, whatever
	# the Target column says (it is `next_self` for a reveal or a card going
	# to the exhaust, which would otherwise make them wait for its duel).
	if ability.effect in ["swapintier", "revealanother", "revealfromexhaust", "exhaustotherreturn"]:
		_zone_effect(ability, source, source_is_enemy, source, source_is_enemy)
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

	# --- The zones in action (round AC, C5) ---
	if C5_EFFECTS.has(ability.effect):
		for pair in _cards_hit(ability.target, source, source_is_enemy, opponent, opponent_is_enemy):
			_zone_effect(ability, pair[0], pair[1], source, source_is_enemy)
		return

	# --- Bending the duel (round AB, C4) ---
	if C4_EFFECTS.has(ability.effect):
		for pair in _cards_hit(ability.target, source, source_is_enemy, opponent, opponent_is_enemy):
			_bend(ability, pair[0], pair[1], source, source_is_enemy, opponent, opponent_is_enemy)
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
	buff.source_key = _k(source, source_is_enemy)

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
	var lower := target.strip_edges().to_lower().replace("enemy_tier:", "enemytier:")
	if lower.begins_with("enemytier:"):
		var t := lower.substr(10).to_upper()
		for thing in (_lineup.get(not source_is_enemy, []) as Array):
			var c := thing as PlayerData
			if c != null and c.get_tier_clean() == t:
				out.append([c, not source_is_enemy])
	elif lower.begins_with("tier:"):
		var t2 := lower.substr(5).to_upper()
		for thing in (_lineup.get(source_is_enemy, []) as Array):
			var c2 := thing as PlayerData
			if c2 != null and c2.get_tier_clean() == t2:
				out.append([c2, source_is_enemy])
	elif lower == "token":
		var t3 := _pick_token(source, source_is_enemy)
		if t3 != null:
			out.append([source, source_is_enemy])
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
			# ROUND AC (C5): JAKOB. "Reveal: if this unit is a swan ..." - the
			# Swan is made by the Emblem in the same reveal (often after you
			# say yes), so his own reveal rows that ask `is_swan` are read
			# again now that the answer has changed.
			_reread_reveal_for_swan(card, card_is_enemy)
		"drainstamina", "restorestamina", "addshotpower", "addcardchance", \
		"goaliechance", "goalieshield", "removeshields", "foulheat", "foulchance", "foulcoinflip":
			_land_side_effect(ability, source, source_is_enemy)
		"gainore":
			_gain_ore(source, source_is_enemy, ability.value)
		_:
			if C5_EFFECTS.has(ability.effect):
				_zone_effect(ability, card, card_is_enemy, source, source_is_enemy)
			elif C4_EFFECTS.has(ability.effect):
				_bend(ability, card, card_is_enemy, source, source_is_enemy, null, not card_is_enemy)
			else:
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
#  THE ZONES IN ACTION (round AC, phase C5)
#
#  Cards moving between the field, combat and the exhaust because an ability
#  says so - and the swap from the exhaust before a duel (ruling R17). Every
#  move made here is also written to _zone_moves, which the match reads with
#  take_zone_moves() to dim or light the bodies on the pitch.
# =============================================================

func _c5_move(card: PlayerData, side_is_enemy: bool, to: String) -> void:
	if card == null:
		return
	_move(card, side_is_enemy, to)
	_zone_moves.append({"card": card, "side": side_is_enemy, "zone": to})


## What C5 moved since the last call, for the match.
func take_zone_moves() -> Array:
	var out := _zone_moves.duplicate()
	_zone_moves.clear()
	return out


## Ingrid: is this side's next pick to be revealed too? Read (and spent) by
## the match when the next card is picked.
func take_reveal_next(side_is_enemy: bool) -> bool:
	var yes := bool(_reveal_next.get(side_is_enemy, false))
	_reveal_next[side_is_enemy] = false
	return yes


func _zone_effect(ability: AbilityData, card: PlayerData, card_is_enemy: bool,
		source: PlayerData, source_is_enemy: bool) -> void:
	match ability.effect:
		"swapintier":
			# The swap was offered and made by the match (exhaust_swap_options
			# / do_exhaust_swap). This row is the marker - and its Max.
			log_lines.append("      %s swaps in from the exhaust" % source.player_name)
		"sendtoexhaust":
			if card != null and _zone_for(card, card_is_enemy) != EXHAUST:
				_c5_move(card, card_is_enemy, EXHAUST)
				log_lines.append("      %s goes to the exhaust" % card.player_name)
		"revealanother":
			_reveal_next[source_is_enemy] = true
			log_lines.append("      %s: the next card picked this round is revealed too" % source.player_name)
		"revealfromexhaust":
			var shown := _pick_from_exhaust(source_is_enemy, source)
			if shown == null:
				log_lines.append("      %s: nothing in the exhaust to reveal" % source.player_name)
				return
			_revealed_from[_k(source, source_is_enemy)] = shown
			_event("revealed_from_exhaust", shown, source_is_enemy, {"by": source.player_name})
			log_lines.append("      %s reveals %s from the exhaust (%s)" % [source.player_name,
				shown.player_name, shown.active_element()])
		"exhaustotherreturn":
			_exhaust_other_return(source, source_is_enemy)
		"doubleattack":
			if card == null:
				return
			var cap := max_power
			var buff := Buff.new()
			buff.scope = "duel"
			buff.card = card
			buff.side_is_enemy = card_is_enemy
			buff.source_key = _k(source, source_is_enemy) if source != null else ""
			# PRINTED power doubled, capped; buffs are added after (Q051).
			buff.attack = mini(card.get_attack_power() * 2, cap) - card.get_attack_power()
			buff.defense = mini(card.get_defense_power() * 2, cap) - card.get_defense_power()
			_buffs.append(buff)
			log_lines.append("      %s: %s's printed power is doubled for this duel" % [
				source.player_name if source != null else "?", card.player_name])
		"swapfromexhaust":
			if card == null:
				return
			_swap_after_duel[_k(card, card_is_enemy)] = true
			log_lines.append("      %s will swap with the exhaust after this duel" % card.player_name)


## Flauros: a fire card if there is one (that is the one worth showing),
## else the strongest.
func _pick_from_exhaust(side_is_enemy: bool, source: PlayerData) -> PlayerData:
	var best: PlayerData = null
	var best_score := -999
	for c in cards_in(side_is_enemy, EXHAUST):
		if c == source:
			continue
		var score := c.get_attack_power() + (10 if CardDatabase._normalise(c.active_element()) == "fire" else 0)
		if score > best_score:
			best_score = score
			best = c
	return best


## Jan, Silke: "send a different Tier IV to the exhaust and return this to
## the stack (if possible)". Another of your cards of its tier still on the
## FIELD goes to the exhaust - the weakest, or the one you pick - and this
## one comes back to be played again this cycle.
func _exhaust_other_return(source: PlayerData, side_is_enemy: bool) -> void:
	if source == null:
		return
	var options := _others_on_field(source, side_is_enemy)
	if options.is_empty():
		log_lines.append("      %s: no other Tier %s on the field - nothing happens" % [
			source.player_name, source.get_tier_clean()])
		return
	if bool(interactive.get(side_is_enemy, false)) and options.size() > 1:
		_queue_ask({"kind": "choose", "side": side_is_enemy, "card": source,
			"action": "exhaust_other", "options": options, "default": options[0],
			"title": "WHO GOES TO THE EXHAUST?",
			"text": "%s comes back to be played again - one of your other Tier %s units goes to the exhaust in its place. Which one?" % [
				source.player_name, source.get_tier_clean()]})
		return
	_do_exhaust_other(source, options[0], side_is_enemy)


func _others_on_field(source: PlayerData, side_is_enemy: bool) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for c in cards_in(side_is_enemy, FIELD):
		if c == source or c.is_star() or c.is_token() or c.get_tier_clean() != source.get_tier_clean():
			continue
		out.append(c)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		return a.get_attack_power() < b.get_attack_power())
	return out


func _do_exhaust_other(source: PlayerData, other: PlayerData, side_is_enemy: bool) -> void:
	_c5_move(other, side_is_enemy, EXHAUST)
	_c5_move(source, side_is_enemy, FIELD)
	log_lines.append("      %s goes to the exhaust; %s comes back to be played" % [
		other.player_name, source.player_name])


## Lothar's token after its duel: to the exhaust, and a card of the same tier
## (the same power if there is one, else the strongest) back to the field.
func _swap_with_exhaust(card: PlayerData, side_is_enemy: bool) -> void:
	var best: PlayerData = null
	var best_score := -999
	for c in cards_in(side_is_enemy, EXHAUST):
		if c == card or c.get_tier_clean() != card.get_tier_clean() or _held.has(_k(c, side_is_enemy)):
			continue
		var score := c.get_attack_power() + (20 if c.get_attack_power() == card.get_attack_power() else 0)
		if score > best_score:
			best_score = score
			best = c
	if best == null:
		log_lines.append("      %s: nothing of its tier in the exhaust to swap with" % card.player_name)
		return
	_c5_move(card, side_is_enemy, EXHAUST)
	_c5_move(best, side_is_enemy, FIELD)
	log_lines.append("      %s goes to the exhaust; %s comes back from it" % [card.player_name, best.player_name])


## ============ R17: THE SWAP FROM THE EXHAUST ============
##
## Which of this side's exhaust cards could swap in for `current` in the duel
## about to start: one with an `exhaust_swap` row whose effect is
## swap_in_tier, of the same tier, whose Max (once per cycle) is not spent.
func exhaust_swap_options(side_is_enemy: bool, current: PlayerData) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	if current == null:
		return out
	for c in cards_in(side_is_enemy, EXHAUST):
		if c.get_tier_clean() != current.get_tier_clean() or _held.has(_k(c, side_is_enemy)):
			continue
		var marker := _swap_marker(c, side_is_enemy)
		if marker == null:
			continue
		if not _has_uses_left(marker, c, side_is_enemy):
			continue
		out.append(c)
	return out


## The swap_in_tier row on the side of this card that is UP (F2: the chosen
## side, else the side it played last).
func _swap_marker(card: PlayerData, side_is_enemy: bool) -> AbilityData:
	var key := _k(card, side_is_enemy)
	var slot := String(_role.get(key, "attack"))
	var up: Dictionary = _side_up.get(key, {})
	if not up.is_empty() and int(up.get("cycle", -1)) == cycle_number:
		slot = String(up["slot"])
	var slots: Array[String] = ["attack", "defend"]
	if role_side:
		slots = [slot]
	for one in slots:
		var cell := card.active_attack_ability() if one == "attack" else card.active_defend_ability()
		for piece in String(cell).split(";"):
			var a := db.get_ability(String(piece).strip_edges())
			if a != null and a.trigger == "exhaustswap" and a.effect == "swapintier":
				return a
	return null


func _has_uses_left(ability: AbilityData, card: PlayerData, side_is_enemy: bool) -> bool:
	if ability.max_uses <= 0:
		return true
	var use_key := (("side%d" % int(side_is_enemy)) if ability.max_shared else _k(card, side_is_enemy)) + "|" + ability.id
	if ability.max_per == "cycle":
		use_key += "|cycle%d" % cycle_number
	elif ability.max_per == "round":
		use_key += "|round%d" % round_number
	return int(_uses.get(use_key, 0)) < ability.max_uses


## Make the swap: `card_in` leaves the exhaust for this duel, `card_out` goes
## to the exhaust in its place. Its `exhaust_swap` rows fire in begin_duel(),
## so call this BEFORE begin_duel() for the duel.
func do_exhaust_swap(card_in: PlayerData, card_out: PlayerData, side_is_enemy: bool) -> void:
	if card_in == null or card_out == null:
		return
	var role := String(_role.get(_k(card_out, side_is_enemy), "attack"))
	_c5_move(card_out, side_is_enemy, EXHAUST)
	_c5_move(card_in, side_is_enemy, COMBAT)
	_role[_k(card_in, side_is_enemy)] = role
	_swapped_out[_k(card_in, side_is_enemy)] = card_out
	var line: Array = _lineup.get(side_is_enemy, [])
	var at := line.find(card_out)
	if at >= 0:
		line[at] = card_in
	_swaps_in.append({"in": card_in, "out": card_out, "side": side_is_enemy})
	_event("exhaust_swap", card_in, side_is_enemy, {"out": card_out.player_name})
	log_lines.append("      %s swaps in from the exhaust for %s" % [card_in.player_name, card_out.player_name])


## Jakob: read his own `is_swan` reveal rows again once he has become one.
func _reread_reveal_for_swan(card: PlayerData, side_is_enemy: bool) -> void:
	for cell in [card.active_attack_ability(), card.active_defend_ability()]:
		for piece in String(cell).split(";"):
			var a := db.get_ability(String(piece).strip_edges())
			if a == null or a.trigger != "reveal" or not a.condition.contains("is_swan"):
				continue
			var fk := _k(card, side_is_enemy)
			if _fired.has(fk) and (_fired[fk] as Array).has(a.id):
				continue
			_apply_one(a, card, side_is_enemy, null, not side_is_enemy)


# =============================================================
#  CONDITIONS AND "NEXT" (round Y, C1 - round Z, C2)
# =============================================================

func _condition_ok(ability: AbilityData, source: PlayerData, source_is_enemy: bool,
		opponent: PlayerData, opponent_is_enemy: bool) -> bool:
	if ability.condition.strip_edges() == "":
		return true
	var me := _k(source, source_is_enemy)
	# Leon (C4): "remove next ally Condition" - this duel its If is ignored.
	if _ignore_if.has(me):
		return true
	for term in AbilityData.condition_terms(ability.condition):
		var word := String(term["word"])
		var arg := String(term["arg"])
		var ok := false
		match word:
			"defending":
				ok = String(_role.get(me, "")) == "defend" or _always_def.has(me)
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
			"swappedwas":
				ok = matches(_swapped_out.get(me, null) as PlayerData, source_is_enemy, arg)
			"revealedwas":
				ok = matches(_revealed_from.get(me, null) as PlayerData, source_is_enemy, arg)
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
	buff.source_key = _k(source, card_is_enemy) if source != null else ""
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
