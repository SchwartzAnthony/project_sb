class_name RecoveryBook
extends RefCounted

# =============================================================
#  TIRED PLAYERS — who has just played, and when they are fit again
#
#  ============ THE IDEA IN ONE PARAGRAPH ============
#
#  A player who is picked for a match comes out of it tired, and stays tired
#  for a number of FIXTURES that depends on how good they are. The better the
#  player the longer they need, so a side of your best eleven cannot play
#  every week — and that is the whole point of having a squad rather than a
#  team. When your first choice is resting you either field the ones on the
#  bench or you go and do something else.
#
#  ============ WHAT COUNTS AS A TURN ============
#
#  A FIXTURE: anything that uses up a squad. A league match, a friendly, a
#  cup tie, a run in Adventure mode. Every fixture you play knocks one off
#  everybody's rest, so going off to Adventure with four players is also how
#  the other eight get their legs back.
#
#  That is why the two modes want different numbers of players:
#
#      a match       a full squad — three of each Tier
#      Adventure     four, one of each Tier  (`adventure_minimum_squad`)
#
#  ============ WHERE THE NUMBERS COME FROM ============
#
#  `data/Recovery.csv`, one row per power:
#
#      Power   Turns   Notes
#      0       1       a squad player. Back next week
#      5       4       your best. Two fixtures off, minimum
#
#  A power with no row falls back to `recovery_turns_per_power` in
#  Tuning.csv multiplied by the power, rounded up, minimum one — so the file
#  can be deleted entirely and the system still works.
#
#  ============ WHERE THE STATE LIVES ============
#
#  In the save, as ordinary counters: `rest_<card>` is how many fixtures that
#  card still has to sit out. Nothing new had to be added to the save format,
#  it survives a reload for free, and you can read it in the save inspector.
#
#  A card is identified by NAME, the same way the rest of the save does it —
#  see the warning about renaming cards in the manual.
# =============================================================

const FILE := "res://data/Recovery.csv"
const PREFIX := "rest_"
## WHAT SENT THEM TO THE DORMS. A row ID of data/Resting.csv — `match`,
## `adventure`, `brew` — stored as a text so the Dorms can say it.
const WHY_PREFIX := "restwhy_"
const RESTING_FILE := "res://data/Resting.csv"

static var _turns: Dictionary = {}
static var _loaded := false
static var _causes: Dictionary = {}
static var _causes_loaded := false


static func forget() -> void:
	_turns = {}
	_loaded = false
	_causes = {}
	_causes_loaded = false


## Power -> fixtures out, out of Recovery.csv.
static func table() -> Dictionary:
	if _loaded:
		return _turns
	_loaded = true
	_turns = {}
	for row in MenuSupport.read_csv(FILE):
		var power_text := MenuSupport.field(row, "Power").strip_edges()
		if not power_text.is_valid_int():
			continue
		_turns[int(power_text)] = maxi(0, int(MenuSupport.field(row, "Turns")))
	if _turns.is_empty():
		print("[rest] No Recovery.csv — falling back to recovery_turns_per_power.")
	return _turns


## The key this card's rest is stored under.
static func key_for(card: PlayerData) -> String:
	return PREFIX + CardDatabase._normalise(card.player_name)


## The same key by NAME, for somebody who is not a card in the list right
## now — a brewer, or a recruit while the recruits are not laid in.
static func key_for_name(name_text: String) -> String:
	return PREFIX + CardDatabase._normalise(name_text)


static func turns_left_name(name_text: String, state: GameState) -> int:
	if state == null or name_text == "":
		return 0
	return maxi(0, state.count(key_for_name(name_text)))


## How many fixtures this card sits out after playing one.
static func turns_for(card: PlayerData, db: CardDatabase) -> int:
	if card == null:
		return 0
	return turns_for_power(maxi(card.get_attack_power(), card.get_defense_power()), db)


## How many fixtures a power sits out — Recovery.csv, else the fallback.
static func turns_for_power(power: int, db: CardDatabase) -> int:
	var book := table()
	if book.has(power):
		return int(book[power])
	var per := 1.0
	if db != null:
		per = db.tune_float("recovery_turns_per_power", 0.8)
	return maxi(1, int(ceil(float(power) * per)))


## Is this card resting right now?
static func is_tired(card: PlayerData, state: GameState) -> bool:
	return turns_left(card, state) > 0


static func turns_left(card: PlayerData, state: GameState) -> int:
	if card == null or state == null:
		return 0
	return maxi(0, state.count(key_for(card)))


## Said in words, for a screen: "" when the card is fit.
static func rest_words(card: PlayerData, state: GameState) -> String:
	var left := turns_left(card, state)
	if left <= 0:
		return ""
	return "resting — %d more fixture%s" % [left, "" if left == 1 else "s"]


# =============================================================
#  THE TWO THINGS THAT HAPPEN
# =============================================================

## THEY PLAYED. Called once at the final whistle with everybody who was named,
## after the turn has been advanced — so a player who plays does NOT also get
## a fixture knocked off their own rest for the game they were playing in.
static func played(cards: Array, state: GameState, db: CardDatabase) -> void:
	if state == null:
		return
	var said: Array[String] = []
	for card in cards:
		if card == null or not (card is PlayerData):
			continue
		var turns := turns_for(card, db)
		if turns <= 0:
			continue
		# SET, not add. Playing two matches in a row does not stack a queue of
		# rest up behind a player; it restarts the same rest.
		state.set_count(key_for(card), turns)
		said.append("%s %d" % [card.player_name, turns])
	if not said.is_empty():
		print("[rest] Out for: %s" % ", ".join(said))
	state.save_to_disk()


## A FIXTURE HAS BEEN PLAYED. Knocks one off everybody's rest. Called before
## played(), so the players who were in this one are not let off by it.
static func advance_turn(state: GameState, db: CardDatabase) -> void:
	if state == null or db == null:
		return
	var woke: Array[String] = []
	# EVERYBODY WHO CAN BE IN BED, BY NAME: the cards in the list, your
	# recruits (who are only in the list while a team screen has laid them
	# in) and your brewers (who never are). Once each.
	for name_text in _everybody(db, state):
		var key := key_for_name(name_text)
		var left := state.count(key)
		if left <= 0:
			continue
		state.set_count(key, left - 1)
		if left - 1 <= 0:
			woke.append(name_text)
	if not woke.is_empty():
		print("[rest] Fit again: %s" % ", ".join(woke))


## Everybody fit, whatever the save says. For a debug key and for the tutorial.
static func rest_everybody(state: GameState, db: CardDatabase) -> void:
	if state == null or db == null:
		return
	for name_text in _everybody(db, state):
		state.set_count(key_for_name(name_text), 0)
	state.save_to_disk()


# =============================================================
#  ASKING WHO IS AVAILABLE
# =============================================================

## The fit cards of a class, tier by tier. `{"I": [...], "II": [...]}`.
static func fit_by_tier(db: CardDatabase, state: GameState, unit_type: String,
		include_stars: bool = true) -> Dictionary:
	var out := {}
	for tier in PlayerData.TIER_ORDER:
		out[tier] = []
	for card in db.players:
		if CardDatabase._normalise(card.unit_type) != CardDatabase._normalise(unit_type):
			continue
		if card.is_star() and not include_stars:
			continue
		if is_tired(card, state):
			continue
		var tier := card.get_tier_clean()
		if out.has(tier):
			out[tier].append(card)
	return out


## Can this class put a side out at all? Returns a report rather than a bool,
## because "no" is useless on its own — the screen has to say WHICH tier is
## short and by how many.
##
##     { "ok": bool, "short": {"II": 1}, "words": "..." }
static func can_field(db: CardDatabase, state: GameState, unit_type: String,
		per_tier: int = 3) -> Dictionary:
	var fit := fit_by_tier(db, state, unit_type)
	var short := {}
	for tier in PlayerData.TIER_ORDER:
		var have: int = (fit[tier] as Array).size()
		if have < per_tier:
			short[tier] = per_tier - have
	if short.is_empty():
		return {"ok": true, "short": {}, "words": ""}
	var pieces: Array[String] = []
	for tier in short:
		pieces.append("%d more in Tier %s" % [int(short[tier]), tier])
	return {
		"ok": false,
		"short": short,
		"words": "Not enough fit players: %s. Rest them by playing a bounty in Adventure, or sign more." % ", ".join(pieces),
	}


# =============================================================
#  THE DORMS — data/Resting.csv (round AN)
#
#  "The Dorms become the resting area for all players: Adventure, Match and
#   Brew players." So EVERY way a player can come home tired goes through
#  here, and the Dorms screen is the one list of who is in bed and why.
#
#  One row per activity. A player who played a match on a brew gets the
#  `match` row AND the `brew` row on top; a player knocked out on an
#  Adventure gets `adventure` AND `adventure_down`. Turns blank = by power
#  (Recovery.csv above), Extra is added, `rest_less` in Tuning.csv (the
#  Feather Beds upgrade) is taken off, never below one fixture.
#
#  The master switch is still `recovery` in Tuning.csv. While it is false
#  nobody is ever sent to bed, exactly as before.
# =============================================================

static func causes() -> Dictionary:
	if _causes_loaded:
		return _causes
	_causes_loaded = true
	_causes = {}
	for row in MenuSupport.read_csv(RESTING_FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges().to_lower()
		if id_text == "":
			continue
		var turns_text := MenuSupport.field(row, "Turns").strip_edges()
		_causes[id_text] = {
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"on": not (MenuSupport.field(row, "On", "true").strip_edges().to_lower() in ["false", "no", "0", "off"]),
			"turns": int(turns_text) if turns_text.is_valid_int() else -1,
			"extra": MenuSupport.field_int(row, "Extra", 0),
			"wakes": MenuSupport.field(row, "Wakes Others", "false").strip_edges().to_lower() in ["true", "yes", "1", "on"],
		}
	return _causes


static func cause(id_text: String) -> Dictionary:
	return causes().get(id_text.to_lower(), {})


## Why this card is in bed, in words: "Back from an Adventure". "" when fit.
static func why_words(card: PlayerData, state: GameState) -> String:
	if card == null:
		return ""
	return why_words_name(card.player_name, state)


static func why_words_name(name_text: String, state: GameState) -> String:
	if state == null or turns_left_name(name_text, state) <= 0:
		return ""
	var why := state.text(WHY_PREFIX + CardDatabase._normalise(name_text))
	var row := cause(why)
	return String(row.get("name", "Resting"))


## THE REST DAY (round AN): a fixture passes for the Dorms only — everybody
## in bed is one nearer fit. The Dorms' button, priced by `rest_day_cost`.
## Returns {"ok", "why"}.
static func rest_day(state: GameState, db: CardDatabase) -> Dictionary:
	if state == null or db == null:
		return {"ok": false, "why": "no save"}
	var price := db.tune_int("rest_day_cost", 0)
	if price < 0:
		return {"ok": false, "why": "there is no rest day (rest_day_cost is below 0)"}
	if price > 0:
		if state.count("coins") < price:
			return {"ok": false, "why": "a rest day costs %d coins, and you have %d" % [price, state.count("coins")]}
		state.add_count("coins", -price)
	var before := in_the_dorms(db, state).size()
	advance_turn(state, db)
	var after := in_the_dorms(db, state).size()
	return {"ok": true, "why": "A rest day. %d out of bed, %d still in it." % [before - after, after]}


## Out of bed now, whatever the save says. The Dev screen's Wake button.
static func wake(name_text: String, state: GameState) -> void:
	if state == null:
		return
	state.set_count(key_for_name(name_text), 0)


## How long this card is in bed after `main`, with any `extras` on top.
## A missing or switched-off main row means no rest at all.
static func rest_for(card: PlayerData, main: String, extras: Array,
		db: CardDatabase, state: GameState = null) -> int:
	if card == null:
		return 0
	return rest_for_power(maxi(card.get_attack_power(), card.get_defense_power()),
		main, extras, db, state)


## The same, for somebody known only by a power — a brewer's efficiency.
static func rest_for_power(power: int, main: String, extras: Array,
		db: CardDatabase, state: GameState = null) -> int:
	var row := cause(main)
	if row.is_empty() or not bool(row["on"]):
		return 0
	var turns := int(row["turns"]) if int(row["turns"]) >= 0 else turns_for_power(power, db)
	turns += int(row["extra"])
	for extra in extras:
		var more := cause(String(extra))
		if not more.is_empty() and bool(more["on"]):
			turns += int(more["extra"])
	if turns <= 0:
		return 0
	if db != null:
		if state != null:
			db.apply_bonuses_from(state)
		turns -= maxi(0, db.tune_int("rest_less", 0))
	return maxi(1, turns)


## SEND ONE CARD TO BED. SET, not add — see played().
static func send_to_dorms(card: PlayerData, main: String, extras: Array,
		state: GameState, db: CardDatabase) -> int:
	if card == null or state == null:
		return 0
	return send_name_to_dorms(card.player_name,
		maxi(card.get_attack_power(), card.get_defense_power()), main, extras, state, db)


## Send somebody to bed by NAME — how a brewer goes after his shift.
static func send_name_to_dorms(name_text: String, power: int, main: String,
		extras: Array, state: GameState, db: CardDatabase) -> int:
	if name_text == "" or state == null:
		return 0
	var turns := rest_for_power(power, main, extras, db, state)
	if turns <= 0:
		return 0
	state.set_count(key_for_name(name_text), turns)
	var why := main
	if not extras.is_empty():
		# The extra is the more interesting reason: "Carried home".
		why = String(extras[-1])
	state.set_text(WHY_PREFIX + CardDatabase._normalise(name_text), why)
	return turns


## THE FINAL WHISTLE. Everybody else is a fixture nearer to fit, then the
## eleven who played go to the Dorms — the ones on a one-match brew for a
## little longer. Call BEFORE BrewDB.clear_temporary(), or the brew is gone.
static func after_match(cards: Array, state: GameState, db: CardDatabase) -> void:
	_after("match", cards, {}, state, db)


## HOME FROM AN ADVENTURE, by any door: walked, fled or fell. `party` is
## every card that set off; `down` the ones knocked out on the way.
static func after_adventure(party: Array, down: Array, state: GameState,
		db: CardDatabase) -> void:
	var extras := {}
	for card in down:
		extras[card] = ["adventure_down"]
	_after("adventure", party, extras, state, db)


static func _after(main: String, cards: Array, extras: Dictionary,
		state: GameState, db: CardDatabase) -> void:
	if state == null or db == null or not db.tune_bool("recovery", false):
		return
	var row := cause(main)
	if row.is_empty() or bool(row["wakes"]):
		advance_turn(state, db)
	var said: Array[String] = []
	for card in cards:
		if card == null or not (card is PlayerData):
			continue
		var more: Array = extras.get(card, [])
		# A ONE-MATCH BREW, still on them: the whistle has not cleared it yet.
		if main == "match" and state.text(BrewDB.TEMP_PREFIX + BrewDB.card_key(card)) != "":
			more = ["brew"]
		var turns := send_to_dorms(card, main, more, state, db)
		if turns > 0:
			said.append("%s %d" % [card.player_name, turns])
	if not said.is_empty():
		print("[dorms] To bed after %s: %s" % [main, ", ".join(said)])
	state.save_to_disk()


## Everybody in the Dorms right now, longest rest first. One entry each:
##     {"name", "tier", "power", "left", "why", "brewer"}
## By NAME, so a brewer and a recruit who is not laid into the card list are
## in bed too.
static func in_the_dorms(db: CardDatabase, state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if db == null or state == null:
		return out
	var seen: Dictionary = {}
	# THE BREWERS FIRST, so a card that shares a brewer's name never hides him.
	for name_text in BrewerBook.names(state):
		var key := CardDatabase._normalise(name_text)
		if seen.has(key):
			continue
		seen[key] = true
		var left := turns_left_name(name_text, state)
		if left > 0:
			out.append({"name": name_text, "tier": BrewerBook.tier(name_text, state),
				"power": BrewerBook.efficiency(name_text, state), "left": left,
				"why": why_words_name(name_text, state), "brewer": true})
	var cards: Array = db.players.duplicate()
	cards.append_array(RecruitBook.cards(state, db))
	for card in cards:
		if card == null:
			continue
		var key := CardDatabase._normalise(card.player_name)
		if seen.has(key):
			continue
		seen[key] = true
		var left := turns_left(card, state)
		if left > 0:
			out.append({"name": card.player_name, "tier": card.get_tier_clean(),
				"power": card.base_power_left, "left": left,
				"why": why_words(card, state), "brewer": false})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["left"]) > int(b["left"]))
	return out


## Every name that can be in bed: the cards, the recruits, the brewers.
static func _everybody(db: CardDatabase, state: GameState) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	var names: Array[String] = []
	if db != null:
		for card in db.players:
			if card != null:
				names.append(card.player_name)
	names.append_array(RecruitBook.names(state))
	names.append_array(BrewerBook.names(state))
	for name_text in names:
		var key := CardDatabase._normalise(name_text)
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		out.append(name_text)
	return out
