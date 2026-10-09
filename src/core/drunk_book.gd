class_name DrunkBook
extends RefCounted

# =============================================================
#  THE DRUNK METER  (round AN)
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "In the pub, when a player drinks, their drunk meter reaches certain
#   levels to then give them special treatment. This includes turning a
#   player into a star player. If a player isn't drunk enough, they won't be
#   able to be affected by the different elemental brews or inspirational
#   brews. Some brews are weaker than others, so the meter needs to fill up
#   based on the inspirational % content."
#
#  ============ THE THREE FILES ============
#
#      Brews.csv  Inspiration   how much of the meter one pour fills, in %.
#                               A row with no Becomes and no abilities is a
#                               PLAIN BEER: it only fills the meter.
#      Items.csv  Inspiration   the same for a bottle in the bag. Blank =
#                               the brew's own number. A bought bottle can
#                               be weaker than the one your Brewery makes.
#      DrunkLevels.csv          where each level starts and what it does:
#                                   brews            elemental and
#                                                    inspirational brews
#                                                    take hold from here
#                                   star             he plays as a Star,
#                                                    with the ability from
#                                                    StarAbilities.csv
#                                   turn_drinks:-2   two fewer turning beers
#                                   turns            a brew with a Becomes
#                                                    (the Fire Brew) changes
#                                                    his class only if he was
#                                                    this drunk BEFORE he
#                                                    drank it (Anthony, 9 Oct)
#      StarAbilities.csv        the star ability by Tier and Power.
#
#  ============ WHERE IT LIVES ============
#
#  In the save, one number per player: the counter  drunk_<name> , 0 to 100.
#  After every ROUND he played (a match or an Adventure played to the end)
#  he loses `drunk_lost_per_round` % of what he has (Tuning.csv, 50 = half),
#  so a player who can still play is topped up with more beers. Once he has
#  played his rounds (Recovery.csv Plays) he is exhausted and rests in the
#  Dorms - and a resting player's meter is EMPTY (Anthony, 8 Oct).
# =============================================================

const PREFIX := "drunk_"
## Was he drunk enough to turn when he drank this brew? One counter per
## player and brew: drunk_turns_<name>_<brew id>, 1 = yes.
const TURNS_PREFIX := "drunk_turns_"
const LEVELS_FILE := "res://data/DrunkLevels.csv"
const STARS_FILE := "res://data/StarAbilities.csv"

static var _levels: Array[Dictionary] = []
static var _stars: Array[Dictionary] = []
static var _loaded := false
## Cards wearing the star overlay right now.
static var _applied: Array[PlayerData] = []


static func reload_files() -> void:
	_loaded = false
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_levels.clear()
	_stars.clear()
	for row in _rows(LEVELS_FILE):
		var id_text := String(row.get("id", ""))
		if id_text == "":
			continue
		var effects: Dictionary = {}
		for piece in String(row.get("effect", "")).split(";", false):
			var bits := String(piece).strip_edges().split(":")
			var verb := String(bits[0]).strip_edges().to_lower()
			if verb != "":
				effects[verb] = String(bits[1]).strip_edges() if bits.size() > 1 else ""
		_levels.append({
			"id": id_text,
			"name": String(row.get("name", id_text)),
			"from": clampi(int(String(row.get("from", "0"))), 0, 100),
			"effects": effects,
			"colour": String(row.get("colour", "")),
		})
	_levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["from"]) < int(b["from"]))
	for row in _rows(STARS_FILE):
		var ability := String(row.get("ability", ""))
		if ability != "":
			_stars.append({
				"tier": String(row.get("tier", "any")).to_upper(),
				"power": String(row.get("power", "any")).to_lower(),
				"ability": ability,
			})


static func _rows(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var rows := CardDatabase.parse_csv(file.get_as_text())
	file.close()
	if rows.size() < 2:
		return out
	var header: PackedStringArray = rows[0]
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var entry: Dictionary = {}
		for c in header.size():
			var key := CardDatabase._normalise(header[c])
			if key != "":
				entry[key] = String(row[c]).strip_edges() if c < row.size() else ""
		out.append(entry)
	return out


# =============================================================
#  THE LEVELS
# =============================================================

static func levels() -> Array[Dictionary]:
	_load()
	return _levels


## Where the first level carrying this effect starts. -1 = no level has it.
static func threshold(effect: String) -> int:
	for level in levels():
		if (level["effects"] as Dictionary).has(effect):
			return int(level["from"])
	return -1


# =============================================================
#  ONE PLAYER'S METER
# =============================================================

static func _key(card: PlayerData) -> String:
	return PREFIX + CardDatabase._normalise(card.player_name)


static func meter(card: PlayerData, state: GameState) -> int:
	if card == null or state == null:
		return 0
	return clampi(state.count(_key(card)), 0, 100)


static func set_meter(card: PlayerData, value: int, state: GameState) -> void:
	if card != null and state != null:
		state.set_count(_key(card), clampi(value, 0, 100))


## THE TUTORIAL'S HOOK: MatchTalk.csv  inspire:Koch=75  sets his meter in the
## save that is playing. Also re-lays the star overlay on him at once.
static func set_level(card: PlayerData, percent: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if card == null or tree == null:
		return
	var state := GameState.fetch(tree)
	set_meter(card, int(round(percent)), state)
	card.drunk_star = card.is_star() == false and is_star(card, state)
	card.drunk_ability = star_ability(card) if card.drunk_star else ""
	if card.drunk_star and not _applied.has(card):
		_applied.append(card)


## The highest level he has reached: {"id", "name", "from", "effects", "colour"}.
static func level_of(card: PlayerData, state: GameState) -> Dictionary:
	var now := meter(card, state)
	var out: Dictionary = {}
	for level in levels():
		if now >= int(level["from"]):
			out = level
	return out


## Does any level he has reached carry this effect?
static func has(card: PlayerData, state: GameState, effect: String) -> bool:
	if not on():
		return false
	var now := meter(card, state)
	for level in levels():
		if now >= int(level["from"]) and (level["effects"] as Dictionary).has(effect):
			return true
	return false


## A level with this effect, its number added up over every level reached.
static func amount(card: PlayerData, state: GameState, effect: String) -> int:
	var total := 0
	if not on():
		return total
	var now := meter(card, state)
	for level in levels():
		var effects: Dictionary = level["effects"]
		if now >= int(level["from"]) and effects.has(effect):
			total += int(String(effects[effect]))
	return total


static func is_star(card: PlayerData, state: GameState) -> bool:
	return has(card, state, "star")


# =============================================================
#  THE BREWS
# =============================================================

## How much of the meter this brew fills. A bottle's own Inspiration
## (Items.csv) beats the brew's, so a bought bottle can be weaker.
static func inspiration(entry: Dictionary, item: Dictionary = {}) -> int:
	# Below 0 SOBERS HIM UP - the Glass of Water (Anthony, 9 Oct).
	var own := String(item.get("inspiration", "")).strip_edges()
	if own.is_valid_int():
		return int(own)
	return int(entry.get("inspiration", 0))


## A plain beer only fills the meter: no new class, no ability.
static func is_plain(entry: Dictionary) -> bool:
	return String(entry.get("becomes", "")).strip_edges() == "" \
		and String(entry.get("attack", "")).strip_edges() == "" \
		and String(entry.get("defend", "")).strip_edges() == ""


## Elemental (an Element, a Becomes) or inspirational (an ability) - the
## brews a sober player shrugs off.
## ROUND AN - PLAIN BEER (Anthony, 8 Oct): a lucky-dip brew (Brews.csv Pool)
## takes less to get the ability, so it takes hold however sober he is.
static func needs_drunk(entry: Dictionary) -> bool:
	return not entry.is_empty() and not is_plain(entry) \
		and String(entry.get("pool", "")).strip_edges() == ""


## Is he drunk enough for this one to take hold?
static func takes_hold(card: PlayerData, entry: Dictionary, state: GameState) -> bool:
	if not on() or not needs_drunk(entry):
		return true
	# AN ELEMENTAL BEER is all or nothing: class, element and abilities come
	# together, and only if he was drunk enough BEFORE he drank it.
	if changes_class(entry) and threshold("turns") >= 0:
		return turns(card, entry, state)
	var gate := threshold("brews")
	# ROUND AN (Anthony, 8 Oct): a drink used on the pitch takes less to
	# take hold (it lasts only the cycle, and leaves him barely drunk).
	if BrewDB.is_cycle_drink(card, String(entry.get("id", "")), state):
		var db := CardDatabase.get_db()
		gate = db.tune_int("match_drink_takes_hold_at", 0) if db != null else 0
	return gate < 0 or meter(card, state) >= gate


## Why it would not take hold, in a sentence. "" = it would.
static func refusal(card: PlayerData, entry: Dictionary, state: GameState) -> String:
	if takes_hold(card, entry, state):
		return ""
	var gate := threshold("brews")
	if changes_class(entry) and threshold("turns") >= 0:
		return "%s was only %d%% when he drank it. %s needs him at %d%% BEFORE he drinks it." % [
			card.player_name, meter(card, state), String(entry.get("name", "That brew")),
			threshold("turns")]
	var level := level_of(card, state)
	return "%s is only %s (%d%%). %s needs %d%% before it takes hold - pour him a plain beer first." % [
		card.player_name, String(level.get("name", "sober")).to_lower(), meter(card, state),
		String(entry.get("name", "That brew")), gate]


## ROUND AN (Anthony, 9 Oct): AN ELEMENTAL BEER TURNS A PLAIN PLAYER.
## "60% needed and then drink any of the elemental beers to transform them
## from normal to an elemental one." Any brew with a Becomes - the Fire and
## Water Brews and the turning beers - takes hold only if his meter was at
## the level carrying `turns` (DrunkLevels.csv) BEFORE this drink. Then the
## class, element and abilities all come at once; too sober and the beer
## only fills his meter. To change element he drinks water until he is
## below that level again, which turns him back to plain (sober_up()).
static func changes_class(entry: Dictionary) -> bool:
	return String(entry.get("becomes", "")).strip_edges() != ""


static func _turns_key(card: PlayerData, entry: Dictionary) -> String:
	return TURNS_PREFIX + CardDatabase._normalise(card.player_name) + "_" \
		+ CardDatabase._normalise(String(entry.get("id", "")))


## Was he drunk enough when he drank this one? Always true for a brew that
## changes no class, or when no level carries `turns`.
static func turns(card: PlayerData, entry: Dictionary, state: GameState) -> bool:
	if not on() or not changes_class(entry) or threshold("turns") < 0:
		return true
	return state != null and card != null and state.count(_turns_key(card, entry)) > 0


## One drink: the meter goes up by the brew's Inspiration. Returns the
## level he was on and the one he is on now, so the Pub can cheer a new one.
static func drink(card: PlayerData, entry: Dictionary, state: GameState,
		item: Dictionary = {}) -> Dictionary:
	var before := level_of(card, state)
	var was := meter(card, state)
	if changes_class(entry) and card != null and state != null:
		var gate := threshold("turns")
		state.set_count(_turns_key(card, entry), 1 if gate < 0 or was >= gate else 0)
	var now := clampi(was + inspiration(entry, item), 0, 100)
	set_meter(card, now, state)
	var after := level_of(card, state)
	if now != was:
		print("[drunk] %s %d%% -> %d%% (%s)." % [card.player_name, was, now,
			String(after.get("name", ""))])
	var back := now < was and sober_up(card, state)
	return {"from": was, "to": now, "before": before, "after": after,
		"turned_back": back,
		"new_level": String(before.get("id", "")) != String(after.get("id", ""))}


## Is he elemental already - turned, or wearing an elemental brew? Then a
## second elemental beer is refused: water first (Anthony, 9 Oct).
static func is_elemental(card: PlayerData, state: GameState) -> bool:
	if card == null or state == null:
		return false
	if TransformBook.has_turned(card, state):
		return true
	for prefix in [BrewDB.TEMP_PREFIX, BrewDB.PERM_PREFIX]:
		var brew := BrewDB.get_db().find(state.text(String(prefix) + BrewDB.card_key(card)))
		if not brew.is_empty() and changes_class(brew):
			return true
	return false


## The sentence for refusing a second elemental beer. "" = he may drink it.
static func elemental_refusal(card: PlayerData, entry: Dictionary, state: GameState) -> String:
	if not on() or threshold("turns") < 0 or not changes_class(entry) \
			or not is_elemental(card, state):
		return ""
	return "%s is already elemental. Give him water until he is below %d%% to turn him back first." % [
		card.player_name, threshold("turns")]


## WATER TURNS HIM BACK (Anthony, 9 Oct): "If they want to switch from
## Elemental to another, give them water, to reduce their drunkenness to get
## below 60% to transform them back to normal." Called when a drink LOWERED
## his meter: below the `turns` level he is plain again. True = he was
## elemental and is plain now.
static func sober_up(card: PlayerData, state: GameState) -> bool:
	var gate := threshold("turns")
	if not on() or gate < 0 or card == null or state == null or meter(card, state) >= gate:
		return false
	return turn_back(card, state)


## Plain again: the class he turned into and any elemental brew on him go.
## Water does it below 60%, and the END OF EVERY GAME does it to everyone who
## played (Anthony, 9 Oct: "they are supposed to lose their elemental at the
## end of each game"). True = he was elemental.
static func turn_back(card: PlayerData, state: GameState) -> bool:
	if card == null or state == null:
		return false
	var back := false
	if TransformBook.has_turned(card, state):
		TransformBook.forget_player(card.player_name, state)
		back = true
	for prefix in [BrewDB.TEMP_PREFIX, BrewDB.PERM_PREFIX]:
		var key := String(prefix) + BrewDB.card_key(card)
		var brew := BrewDB.get_db().find(state.text(key))
		if not brew.is_empty() and changes_class(brew):
			state.set_text(key, "")
			back = true
	if back:
		print("[drunk] %s is a plain player again." % card.player_name)
	return back


## ROUND AN (Anthony, 8 Oct): A ROUND IS OVER - a match or an Adventure
## played to the end (a Quit puts the save back, so it never gets here).
## Everybody who played loses `drunk_lost_per_round` % OF WHAT HE HAS (50 =
## half), so a fit player can be topped up with more beers. Anybody in the
## Dorms is resting, and a resting player's meter is empty. Call it AFTER
## RecoveryBook has sent the exhausted ones to bed. Returns how many changed.
static func after_round(cards: Array, state: GameState, db: CardDatabase) -> int:
	if state == null:
		return 0
	var lost := clampi(db.tune_int("drunk_lost_per_round", 50) if db != null else 50, 0, 100)
	var many := 0
	for card in cards:
		if card == null or not (card is PlayerData):
			continue
		# THE GAME IS OVER, SO IS THE ELEMENT (Anthony, 9 Oct).
		if on() and threshold("turns") >= 0 and turn_back(card, state):
			many += 1
		var was := meter(card, state)
		if was <= 0:
			continue
		set_meter(card, was - int(round(float(was) * float(lost) / 100.0)), state)
		many += 1
	many += empty_the_resting(state, db)
	return many


## Everybody in bed is sober. Returns how many meters were emptied.
static func empty_the_resting(state: GameState, db: CardDatabase) -> int:
	if state == null or db == null:
		return 0
	var many := 0
	for row in RecoveryBook.in_the_dorms(db, state):
		var key := PREFIX + CardDatabase._normalise(String(row["name"]))
		if state.count(key) > 0:
			state.set_count(key, 0)
			many += 1
	return many


static func on() -> bool:
	var db := CardDatabase.get_db()
	return db == null or db.tune_bool("drunk_meter", true)


# =============================================================
#  THE STAR ABILITY
# =============================================================

## The StarAbilities.csv row for this Tier and Power. The most exact wins.
static func star_ability(card: PlayerData) -> String:
	_load()
	if card == null:
		return ""
	var best := ""
	var best_score := -1
	for row in _stars:
		var score := 0
		var tier := String(row["tier"])
		if tier != "ANY" and tier != "":
			if tier != card.get_tier_clean():
				continue
			score += 2
		var power := String(row["power"])
		if power != "any" and power != "":
			if not power.is_valid_int() or int(power) != card.base_power_left:
				continue
			score += 1
		if score > best_score:
			best_score = score
			best = String(row["ability"])
	return best


# =============================================================
#  THE MATCH
# =============================================================

## Lay the star overlay on everybody drunk enough. Called by BrewDB.apply_all
## at kick-off, after the brews, so a brew's ability beats the star one.
static func apply_all(db: CardDatabase, state: GameState) -> int:
	restore_all()
	if db == null or state == null or not on():
		return 0
	var many := 0
	for card in db.players:
		if card == null or card.is_star() or not is_star(card, state):
			continue
		card.drunk_star = true
		card.drunk_ability = star_ability(card)
		_applied.append(card)
		many += 1
	if many > 0:
		print("[drunk] %d player(s) drunk enough to play as a Star." % many)
	return many


static func restore_all() -> void:
	for card in _applied:
		if card != null:
			card.drunk_star = false
			card.drunk_ability = ""
	_applied.clear()


# =============================================================
#  CHECKS
# =============================================================

static func problems() -> Array[String]:
	reload_files()
	var out: Array[String] = []
	var db := CardDatabase.get_db()
	if threshold("brews") < 0:
		out.append("DrunkLevels.csv: no level has the effect 'brews' - every brew takes hold on a sober player")
	for row in _stars:
		if db != null and db.get_ability(String(row["ability"])) == null:
			out.append("StarAbilities.csv: '%s' is not in Abilities.csv" % row["ability"])
	for level in _levels:
		for verb in (level["effects"] as Dictionary).keys():
			if not String(verb) in ["brews", "star", "turn_drinks", "turns"]:
				out.append("DrunkLevels.csv %s: '%s' is not an effect the game knows (brews, star, turn_drinks, turns)" % [level["id"], verb])
	return out
