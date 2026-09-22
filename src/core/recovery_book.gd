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

static var _turns: Dictionary = {}
static var _loaded := false


static func forget() -> void:
	_turns = {}
	_loaded = false


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


## How many fixtures this card sits out after playing one.
static func turns_for(card: PlayerData, db: CardDatabase) -> int:
	if card == null:
		return 0
	var power := maxi(card.get_attack_power(), card.get_defense_power())
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
	for card in db.players:
		var key := key_for(card)
		var left := state.count(key)
		if left <= 0:
			continue
		state.set_count(key, left - 1)
		if left - 1 <= 0:
			woke.append(card.player_name)
	if not woke.is_empty():
		print("[rest] Fit again: %s" % ", ".join(woke))


## Everybody fit, whatever the save says. For a debug key and for the tutorial.
static func rest_everybody(state: GameState, db: CardDatabase) -> void:
	if state == null or db == null:
		return
	for card in db.players:
		state.set_count(key_for(card), 0)
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
