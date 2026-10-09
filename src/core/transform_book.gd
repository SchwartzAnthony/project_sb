class_name TransformBook
extends RefCounted

# =============================================================
#  THREE BEERS AND HE IS ONE OF THEM — the Drinks column of Brews.csv
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "Johannes is a plain Tier I Power 0, but when he drinks 3 water element
#   beer he becomes a Tier I Power 0 Lorelei. Same for all of the other
#   elements."
#
#  And your answers to the three questions that left open:
#
#      WHOSE ABILITIES?   You pick. On the last beer the Pub shows the class's
#                         cards at his tier and power - one per set (Sitri,
#                         Zepar, Sallos) - and he becomes the one you choose.
#      MIXING BEERS?      A new element starts the count again.
#                         Water, Water, Fire  =  Fire 1 of 3.
#      SWITCHED ON?       Yes, for every plain card today. Named recruits are
#                         a separate switch - see recruit_book.gd.
#
#  ============ WHAT MAKES A BREW A TURNING BREW ============
#
#  A number in its DRINKS column. That is the whole rule:
#
#      Drinks blank   an ordinary brew. One match, or permanent, exactly as
#                     every brew has always worked. Nothing changed.
#      Drinks 3       a TURNING brew. Each pour is one beer towards 3. The
#                     third makes the change, and the change is for good.
#
#  ============ WHAT CHANGES, AND WHAT DOES NOT ============
#
#      KEPT      his NAME, his tier, his power. He is still Johannes, still
#                Tier I, still a 0. The ladder never notices.
#      TAKEN     from the card you chose: class, element, set, both ability
#                texts, both ability IDs, and its artwork.
#
#  An ordinary brew can still be poured on top afterwards: a turned Lorelei
#  may drink a one-match Fire Brew, because For Class now sees a Lorelei.
#
#  ============ WHERE IT LIVES ============
#
#  In the save, per player name:
#      drinks_<name>   "water:2"     how far along he is
#      became_<name>   "Tobias"      the Name of the card he turned into
#
#  Because it is stored against the card he BECAME, rewriting that card's
#  abilities in Unit_Set_Lorelei.csv rewrites them for everybody who turned
#  into it. Renaming that card breaks the link - the same rule as every other
#  card name in the game.
# =============================================================

const DRINKS_PREFIX := "drinks_"
const BECAME_PREFIX := "became_"

## Cards wearing somebody else's class right now, and what they were before.
static var _changed: Dictionary = {}     # PlayerData -> {field: value}


# =============================================================
#  QUESTIONS ABOUT A BREW
# =============================================================

## How many beers this row takes. 0 = it is an ordinary brew.
static func drinks_needed(entry: Dictionary) -> int:
	return int(entry.get("drinks", 0))


## How many beers THIS player needs. A Star from the drunk meter needs fewer
## (DrunkLevels.csv turn_drinks), never fewer than one.
static func drinks_needed_for(card: PlayerData, entry: Dictionary, state: GameState) -> int:
	var need := drinks_needed(entry)
	if need <= 0:
		return need
	# ROUND AN (Anthony, 9 Oct): with a `turns` level in DrunkLevels.csv ONE
	# beer does it, if he was drunk enough before it. The count is history.
	if DrunkBook.on() and DrunkBook.threshold("turns") >= 0:
		return 1
	return maxi(1, need + DrunkBook.amount(card, state, "turn_drinks"))


static func is_turning(entry: Dictionary) -> bool:
	return drinks_needed(entry) > 0 and String(entry.get("becomes", "")).strip_edges() != ""


## What counts as "the same beer" for the count. The Element column if it
## has one, otherwise the class it turns you into.
static func element_of(entry: Dictionary) -> String:
	var element := String(entry.get("element", "")).strip_edges()
	if element == "":
		element = String(entry.get("becomes", "")).strip_edges()
	return element.to_lower()


# =============================================================
#  QUESTIONS ABOUT A PLAYER
# =============================================================

static func _key(card: PlayerData) -> String:
	return CardDatabase._normalise(card.player_name) if card != null else ""


## The Name of the card he became, or "" if he is still plain.
static func became(card: PlayerData, state: GameState) -> String:
	if card == null or state == null:
		return ""
	return state.text(BECAME_PREFIX + _key(card))


static func has_turned(card: PlayerData, state: GameState) -> bool:
	return became(card, state) != ""


## {"element": "water", "count": 2}. Empty element = no beers yet.
static func progress(card: PlayerData, state: GameState) -> Dictionary:
	var out := {"element": "", "count": 0}
	if card == null or state == null:
		return out
	var raw := state.text(DRINKS_PREFIX + _key(card))
	if raw == "":
		return out
	var bits := raw.split(":")
	out["element"] = String(bits[0]).strip_edges().to_lower()
	if bits.size() > 1 and String(bits[1]).is_valid_int():
		out["count"] = int(String(bits[1]))
	return out


## The cards he could become: the class's cards at his tier and power, one
## per set, Stars left out. Read from the cards AS WRITTEN in the CSVs.
static func choices(card: PlayerData, entry: Dictionary, db: CardDatabase) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	if card == null or db == null:
		return out
	var wanted := CardDatabase._normalise(String(entry.get("becomes", "")))
	var seen_sets: Dictionary = {}
	for other in db.players:
		if other == null or other == card or other.is_star():
			continue
		if _changed.has(other):
			continue          # a turned player is not a card to turn into
		if CardDatabase._normalise(String(_original(other, "unit_type"))) != wanted:
			continue
		if other.get_tier_clean() != card.get_tier_clean():
			continue
		if other.base_power_left != card.base_power_left:
			continue
		var set_key := CardDatabase._normalise(other.card_set)
		if seen_sets.has(set_key):
			continue
		seen_sets[set_key] = true
		out.append(other)
	return out


## Why he cannot drink this one, in a sentence. "" means he can.
static func refusal(card: PlayerData, entry: Dictionary, state: GameState,
		db: CardDatabase) -> String:
	if not is_turning(entry):
		return ""
	if has_turned(card, state):
		return "%s has already turned. A turning brew only works on a plain player - give him water until he is below %d%% first." % [
			card.player_name, maxi(0, DrunkBook.threshold("turns"))]
	if choices(card, entry, db).is_empty():
		return "%s has no Tier %s, Power %d players outside its Stars, so %s has nothing to turn into." % [
			String(entry.get("becomes", "")), card.get_tier_clean(), card.base_power_left,
			card.player_name]
	return ""


## Has he had enough, and is only waiting for you to choose a set?
static func waiting_to_choose(card: PlayerData, entry: Dictionary, state: GameState) -> bool:
	if not is_turning(entry) or has_turned(card, state):
		return false
	var now := progress(card, state)
	return String(now["element"]) == element_of(entry) and int(now["count"]) >= drinks_needed_for(card, entry, state)


# =============================================================
#  POURING ONE
# =============================================================

## One beer. Pays for it, counts it, and says where he has got to:
##     {"ok": bool, "count": n, "need": n, "ready": bool, "why": "..."}
## `ready` means that was the last one - now ask which card he becomes.
static func pour(card: PlayerData, entry: Dictionary, state: GameState,
		db: CardDatabase) -> Dictionary:
	var need := drinks_needed_for(card, entry, state)
	var out := {"ok": false, "count": 0, "need": need, "ready": false, "why": ""}
	if card == null or state == null or not is_turning(entry):
		return out
	var no := refusal(card, entry, state, db)
	if no != "":
		out["why"] = no
		return out
	if waiting_to_choose(card, entry, state):
		out["ok"] = true
		out["ready"] = true
		out["count"] = need
		out["why"] = "%s has had enough. Choose who he becomes." % card.player_name
		return out
	if not BrewDB.can_afford(entry, state):
		out["why"] = "Not enough to pour it: %s." % BrewDB.cost_text(entry, state)
		return out
	for item in (entry.get("cost", {}) as Dictionary).keys():
		state.add_count(String(item), -int((entry["cost"] as Dictionary)[item]))
	# EVERY BEER FILLS THE DRUNK METER too. See drunk_book.gd. It can make
	# him a Star, who needs fewer turning beers, so the need is asked again.
	DrunkBook.drink(card, entry, state)
	need = drinks_needed_for(card, entry, state)
	out["need"] = need

	# ALWAYS POURED (Anthony, 8 Oct), but TOO SOBER = it does not count
	# towards turning him. It only filled his meter.
	if not DrunkBook.takes_hold(card, entry, state):
		StatsRules.get_rules().record("brew_drunk", {
			"brew": String(entry["id"]), "card": card.player_name,
			"class": card.unit_type, "tier": card.get_tier_clean(),
		}, state)
		var before := progress(card, state)
		out["ok"] = true
		out["count"] = int(before["count"]) if String(before["element"]) == element_of(entry) else 0
		out["why"] = "%s drinks the %s, but he is too sober for it to work. %s It only filled his meter." % [
			card.player_name, String(entry.get("name", entry["id"])),
			DrunkBook.refusal(card, entry, state)]
		return out

	# A NEW ELEMENT STARTS AGAIN. Your answer: water, water, fire = fire 1.
	var now := progress(card, state)
	var element := element_of(entry)
	var count := 1
	if String(now["element"]) == element:
		count = int(now["count"]) + 1
	elif String(now["element"]) != "":
		print("[turning] %s switched from %s to %s - the count starts again."
			% [card.player_name, now["element"], element])
	count = mini(count, need)
	state.set_text(DRINKS_PREFIX + _key(card), "%s:%d" % [element, count])

	StatsRules.get_rules().record("brew_drunk", {
		"brew": String(entry["id"]),
		"card": card.player_name,
		"class": card.unit_type,
		"tier": card.get_tier_clean(),
	}, state)

	out["ok"] = true
	out["count"] = count
	out["ready"] = count >= need
	out["why"] = "%s drinks the %s - %d of %d." % [card.player_name,
		String(entry.get("name", entry["id"])), count, need]
	return out


## The last beer is down and you have chosen. He becomes `role` for good.
static func complete(card: PlayerData, role: PlayerData, state: GameState) -> void:
	if card == null or role == null or state == null:
		return
	state.set_text(BECAME_PREFIX + _key(card), role.player_name)
	state.set_text(DRINKS_PREFIX + _key(card), "")
	print("[turning] %s is now a %s (%s set), Tier %s Power %d."
		% [card.player_name, role.unit_type, role.card_set, card.get_tier_clean(),
			card.base_power_left])
	StatsRules.get_rules().record("player_turned", {
		"card": card.player_name,
		"class": role.unit_type,
		"set": role.card_set,
		"tier": card.get_tier_clean(),
	}, state)


## Undo it entirely - for a release, or a dev-mode reset.
static func forget_player(name_text: String, state: GameState) -> void:
	if state == null:
		return
	var key := CardDatabase._normalise(name_text)
	state.set_text(DRINKS_PREFIX + key, "")
	state.set_text(BECAME_PREFIX + key, "")


# =============================================================
#  WEARING IT
# =============================================================

const COPIED: Array[String] = ["unit_type", "element", "card_set", "attack_text",
	"defend_text", "attack_ability_id", "defend_ability_id", "artwork"]


## Put every turned player into the class he chose. Safe to call as often
## as you like: it takes the old change off first. Every screen that lists
## cards by class calls it on the way in. Returns how many were changed.
static func apply_all(db: CardDatabase, state: GameState) -> int:
	restore_all()
	if db == null or state == null:
		return 0
	# THE RECRUITS GO IN FIRST, so a recruit who has turned is turned too.
	# Done here so every screen needs one call, not two. See recruit_book.gd.
	RecruitBook.apply_all(db, state)
	var by_name: Dictionary = {}
	for other in db.players:
		if other != null:
			by_name[CardDatabase._normalise(other.player_name)] = other
	var many := 0
	for card in db.players:
		if card == null:
			continue
		var role_name := became(card, state)
		if role_name == "":
			continue
		var role: PlayerData = by_name.get(CardDatabase._normalise(role_name), null)
		if role == null:
			push_warning("[turning] %s became '%s', but no card has that Name any more. Was it renamed?"
				% [card.player_name, role_name])
			continue
		var before: Dictionary = {}
		for field in COPIED:
			before[field] = card.get(field)
			card.set(field, role.get(field))
		_changed[card] = before
		many += 1
	return many


static func restore_all() -> void:
	for card in _changed.keys():
		var before: Dictionary = _changed[card]
		for field in before.keys():
			(card as PlayerData).set(String(field), before[field])
	_changed.clear()


## A field as the CSV wrote it, even if the card is wearing a change.
static func _original(card: PlayerData, field: String) -> Variant:
	if _changed.has(card):
		return (_changed[card] as Dictionary).get(field, card.get(field))
	return card.get(field)
