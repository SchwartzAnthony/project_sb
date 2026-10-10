class_name BaseRooms
extends RefCounted

# =============================================================
#  THE FOUR ROOMS — Dorms, Trophy Room, Training Ground, Club House
#
#  One file, because they are four small things that all do the same shape:
#  read a spreadsheet, test a condition, spend a currency, hand something
#  over. Four files of ninety lines each would have been four files to keep
#  in step.
#
#      data/Dorms.csv      how many players you may keep
#      data/Trophies.csv   what is on the shelf
#      data/Training.csv   Ausbildung, and the five brewing mini-games
#
#      data/Upgrades.csv   what the Club House sells (round AN)
#
#  ROUND AN (Anthony): the DORMS are where every player rests — a view onto
#  recovery_book.gd and data/Resting.csv — and the CLUB HOUSE is the shop
#  for upgrades. An achievement only grants the RIGHT to buy an upgrade;
#  the buying is done here, with money.
#
#  ============ THE ONE RULE THEY SHARE ============
#
#  "The basic foundation is there free, and everything that would make it
#   easier or more can be unlocked later on."
#
#  So the FIRST rooms of the Dorms are free (twelve beds); the rest are bought. Every
#  Ausbildung and every mini-game is bought. And every one of them pays in a
#  currency out of Currencies.csv, which only certain match modes hand out.
# =============================================================

const DORMS_FILE := "res://data/Dorms.csv"
const TROPHY_FILE := "res://data/Trophies.csv"
const TRAINING_FILE := "res://data/Training.csv"
const UPGRADES_FILE := "res://data/Upgrades.csv"

## The dorm you have bought, by id. `bought_dorm_lean_to`.
const DORM_PREFIX := "bought_dorm_"
## And a training you have taken.
const TRAINED_PREFIX := "trained_"
## And an upgrade bought at the Club House. `upgrade_feather_beds`.
const UPGRADE_PREFIX := "upgrade_"

static var _dorms: Array[Dictionary] = []
static var _trophies: Array[Dictionary] = []
static var _training: Array[Dictionary] = []
static var _upgrades: Array[Dictionary] = []
static var _problems: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_dorms = []
	_trophies = []
	_training = []
	_upgrades = []
	_problems = []
	_loaded = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_dorms = []
	_trophies = []
	_training = []
	_upgrades = []
	_problems = []

	for row in MenuSupport.read_csv(DORMS_FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		# ROUND AN (Anthony, 10 Oct): ONE ROW PER ROOM, in the order they are
		# bought. Beds Included come with the room; the rest of its places are
		# single beds bought one at a time.
		_dorms.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"price": maxi(0, MenuSupport.field_int(row, "Price", 0)),
			"currency": MenuSupport.field(row, "Currency").strip_edges(),
			"requires": MenuSupport.field(row, "Requires").strip_edges(),
			"beds": maxi(0, MenuSupport.field_int(row, "Beds Included", 0)),
		})

	if _dorms.is_empty():
		_problems.append("No Dorms.csv rows, so there is no room and no bed for anybody. Write at least a free first row.")
	elif int(_dorms[0]["price"]) > 0:
		_problems.append("Room 1 costs %d. A new game can never buy its first room - the first row has to be free."
			% int(_dorms[0]["price"]))

	for row in MenuSupport.read_csv(TROPHY_FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		var won := MenuSupport.field(row, "Won When").strip_edges()
		_trophies.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"competition": MenuSupport.field(row, "Competition").strip_edges(),
			"won_when": won,
			"art": MenuSupport.field(row, "Art").strip_edges(),
		})
		if won == "":
			_problems.append("Trophy '%s' has an empty Won When, so it is on the shelf from the first minute." % id_text)

	for row in MenuSupport.read_csv(TRAINING_FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		var effect := MenuSupport.field(row, "Effect").strip_edges()
		_training.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"kind": MenuSupport.field(row, "Kind", "ausbildung").strip_edges().to_lower(),
			"section": MenuSupport.field(row, "Section").strip_edges(),
			"needs": MenuSupport.field(row, "Needs").strip_edges(),
			"cost": maxi(0, MenuSupport.field_int(row, "Cost", 0)),
			"currency": MenuSupport.field(row, "Currency").strip_edges(),
			"effect": effect,
		})
		# A ROLE training (brewer, match_player, adventure_player, retrain) has
		# no Effect: giving the player his role IS the effect.
		if effect == "" and not _training[-1]["kind"] in ["brewer", "match_player", "adventure_player", "retrain"]:
			_problems.append("Training '%s' has an empty Effect — it can be bought and then does nothing." % id_text)
		for complaint in DialogueGrammar.complaints(effect, true):
			_problems.append("Training '%s': %s" % [id_text, complaint])

	var achievement_ids: Dictionary = {}
	for one in AchievementBook.rows():
		achievement_ids[String(one["id"]).to_lower()] = true
	for row in MenuSupport.read_csv(UPGRADES_FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		var effect := MenuSupport.field(row, "Effect").strip_edges()
		var earned_by := MenuSupport.field(row, "Achievement").strip_edges()
		_upgrades.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"description": MenuSupport.field(row, "Description").strip_edges(),
			"kind": MenuSupport.field(row, "Kind", "upgrade").strip_edges().to_lower(),
			"achievement": earned_by,
			"needs": MenuSupport.field(row, "Needs").strip_edges(),
			"cost": maxi(0, MenuSupport.field_int(row, "Cost", 0)),
			"currency": MenuSupport.field(row, "Currency").strip_edges(),
			"effect": effect,
		})
		if effect == "":
			_problems.append("Upgrade '%s' has an empty Effect — it can be bought and then does nothing." % id_text)
		for complaint in DialogueGrammar.complaints(effect, true):
			_problems.append("Upgrade '%s': %s" % [id_text, complaint])
		if earned_by != "" and not achievement_ids.has(earned_by.to_lower()):
			_problems.append("Upgrade '%s' waits on achievement '%s', which is not an ID in Achievements.csv — it can never go on sale." % [id_text, earned_by])

	print("[rooms] %d dorm(s), %d trophy(ies), %d training(s), %d upgrade(s)."
		% [_dorms.size(), _trophies.size(), _training.size(), _upgrades.size()])
	for problem in _problems:
		print("[rooms] %s" % problem)


static func problems() -> Array[String]:
	_load()
	return _problems


# =============================================================
#  THE DORMS - rooms of beds (round AN, Anthony 10 Oct)
#
#  data/Dorms.csv is one row per ROOM, in the order they are bought. A room
#  holds `dorm_beds_per_room` beds (Tuning.csv, 10) and there are at most
#  `dorm_max_rooms` rooms (10). A room comes with its Beds Included; every
#  other place in it is a SINGLE BED bought for `dorm_bed_price`.
#
#  In the save:   bought_dorm_<room id>   a flag per room you bought
#                 dorm_beds_bought        single beds bought, all rooms
#
#  Beds fill room 1 first, then room 2, and so on - so the screen can lay
#  them out without remembering which bed is where.
# =============================================================

## Single beds bought, over all the rooms.
const BEDS_BOUGHT := "dorm_beds_bought"
## The old dorms (before rooms) and how many beds each gave in all. A save
## that bought one is given the same number of beds in rooms, once.
const LEGACY_DORMS := {"lean_to": 18, "long_house": 26, "stone_wing": 36}
const LEGACY_MOVED := "dorms_moved_to_rooms"


static func _db() -> CardDatabase:
	return CardDatabase.get_db()


## How many beds one room holds.
static func beds_per_room() -> int:
	var db := _db()
	return maxi(1, db.tune_int("dorm_beds_per_room", 10) if db != null else 10)


## Every room the Dorms can ever have, in buying order.
static func dorms() -> Array[Dictionary]:
	_load()
	var db := _db()
	var most := db.tune_int("dorm_max_rooms", 10) if db != null else 10
	if most <= 0 or _dorms.size() <= most:
		return _dorms
	return _dorms.slice(0, most)


static func owns_dorm(id_text: String, state: GameState) -> bool:
	for room in dorms():
		if String(room["id"]) == id_text:
			return int(room["price"]) == 0 or (state != null
				and state.has_flag(DORM_PREFIX + id_text.to_lower()))
	return false


## The rooms you have, in order.
static func rooms_owned(state: GameState) -> Array[Dictionary]:
	_move_legacy(state)
	var out: Array[Dictionary] = []
	for room in dorms():
		if owns_dorm(String(room["id"]), state):
			out.append(room)
	return out


## The next room on sale, or {} when you have them all. Rooms are bought in
## order, so this is the first one you do not have.
static func next_room(state: GameState) -> Dictionary:
	for room in dorms():
		if not owns_dorm(String(room["id"]), state):
			return room
	return {}


## Places for beds in the rooms you have.
static func bed_places(state: GameState) -> int:
	return rooms_owned(state).size() * beds_per_room()


## HOW MANY BEDS YOU HAVE: what came with your rooms plus the single beds,
## never more than the rooms hold. It is also how many players you may keep.
static func beds(state: GameState) -> int:
	var have := 0
	for room in rooms_owned(state):
		have += int(room["beds"])
	if state != null:
		have += maxi(0, state.count(BEDS_BOUGHT))
	return mini(have, bed_places(state))


## How many beds stand in each room you have, in order: [10, 2]. Beds fill
## room 1 first.
static func beds_by_room(state: GameState) -> Array[int]:
	var out: Array[int] = []
	var left := beds(state)
	var per := beds_per_room()
	for room in rooms_owned(state):
		var here := mini(left, per)
		out.append(here)
		left -= here
	return out


## The room you have the most of - kept for anything that names "your dorm".
static func current_dorm(state: GameState) -> Dictionary:
	var owned := rooms_owned(state)
	return owned[-1] if not owned.is_empty() else {}


## Buy one SINGLE BED. Returns {"ok", "why"}.
static func buy_bed(state: GameState) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	if beds(state) >= bed_places(state):
		var nxt := next_room(state)
		return {"ok": false, "why": "every room is full - buy %s first" % nxt["name"]
			if not nxt.is_empty() else "every room is full"}
	var db := _db()
	var price := db.tune_int("dorm_bed_price", 25) if db != null else 25
	var spent := _spend(price, db.tune_text("dorm_bed_currency", "coins") if db != null else "coins", state)
	if spent != "":
		return {"ok": false, "why": spent}
	state.add_count(BEDS_BOUGHT, 1)
	return {"ok": true, "why": "A new bed. %d beds now." % beds(state)}


## Buy a ROOM. Only the next one in order can be bought. Returns {"ok", "why"}.
static func buy_dorm(id_text: String, state: GameState) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	var room: Dictionary = {}
	for one in dorms():
		if String(one["id"]) == id_text:
			room = one
			break
	if room.is_empty():
		return {"ok": false, "why": "there is no such room"}
	if owns_dorm(id_text, state):
		return {"ok": false, "why": "you already have it"}
	var nxt := next_room(state)
	if String(nxt.get("id", "")) != id_text:
		return {"ok": false, "why": "buy %s first" % nxt.get("name", "the rooms before it")}
	if not DialogueGrammar.test(String(room["requires"]), state):
		return {"ok": false, "why": DialogueGrammar.describe(String(room["requires"]))}
	var spent := _spend(int(room["price"]), String(room["currency"]), state)
	if spent != "":
		return {"ok": false, "why": spent}
	state.set_flag(DORM_PREFIX + id_text.to_lower(), true)
	return {"ok": true, "why": "%s. Room for %d beds now - buy them one at a time." % [
		room["name"], bed_places(state)]}


## A save from before the rooms bought a whole dorm (the Lean-To ...). Give
## it the same number of beds, in rooms, once, for free.
static func _move_legacy(state: GameState) -> void:
	if state == null or state.has_flag(LEGACY_MOVED):
		return
	var wanted := 0
	for old_id in LEGACY_DORMS:
		if state.has_flag(DORM_PREFIX + String(old_id)):
			wanted = maxi(wanted, int(LEGACY_DORMS[old_id]))
	state.set_flag(LEGACY_MOVED, true)
	if wanted <= 0:
		return
	var per := beds_per_room()
	var included := 0
	var places := 0
	for room in dorms():
		if places >= wanted:
			break
		if int(room["price"]) > 0:
			state.set_flag(DORM_PREFIX + String(room["id"]).to_lower(), true)
		included += int(room["beds"])
		places += per
	state.set_count(BEDS_BOUGHT, maxi(state.count(BEDS_BOUGHT), wanted - included))
	print("[rooms] An old dorm became rooms: %d beds." % wanted)


# =============================================================
#  THE TROPHY ROOM
# =============================================================

static func trophies() -> Array[Dictionary]:
	_load()
	return _trophies


static func won(entry: Dictionary, state: GameState) -> bool:
	return DialogueGrammar.test(String(entry["won_when"]), state)


static func trophies_won(state: GameState) -> int:
	var many := 0
	for one in trophies():
		if won(one, state):
			many += 1
	return many


# =============================================================
#  THE TRAINING GROUND
# =============================================================

static func training() -> Array[Dictionary]:
	_load()
	return _training


static func trained(id_text: String, state: GameState) -> bool:
	if state == null:
		return false
	return state.has_flag(TRAINED_PREFIX + id_text.to_lower())


## Take a training. Spends, sets the flag, and runs the Effect.
static func train(id_text: String, state: GameState) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	var entry: Dictionary = {}
	for one in training():
		if String(one["id"]) == id_text:
			entry = one
			break
	if entry.is_empty():
		return {"ok": false, "why": "there is no such training"}
	if trained(id_text, state):
		return {"ok": false, "why": "already taken"}
	if not DialogueGrammar.test(String(entry["needs"]), state):
		return {"ok": false, "why": DialogueGrammar.describe(String(entry["needs"]))}

	var spent := _spend(int(entry["cost"]), String(entry["currency"]), state)
	if spent != "":
		return {"ok": false, "why": spent}

	state.set_flag(TRAINED_PREFIX + id_text.to_lower(), true)
	Progression.run_actions(String(entry["effect"]), state)
	return {"ok": true, "why": "%s. %s" % [entry["name"],
		DialogueGrammar.describe(String(entry["effect"]))]}


# =============================================================
#  THE CLUB HOUSE — data/Upgrades.csv (round AN)
#
#  Three states, and the screen draws all three:
#      locked     the achievement is not earned yet
#      for_sale   earned (and Needs holds) — a price and a Buy button
#      bought     yours; the Effect has run once
# =============================================================

static func upgrades() -> Array[Dictionary]:
	_load()
	return _upgrades


static func find_upgrade(id_text: String) -> Dictionary:
	for one in upgrades():
		if String(one["id"]).to_lower() == id_text.to_lower():
			return one
	return {}


static func owns_upgrade(id_text: String, state: GameState) -> bool:
	if state == null:
		return false
	return state.has_flag(UPGRADE_PREFIX + id_text.to_lower())


## "locked", "for_sale" or "bought".
static func upgrade_state(entry: Dictionary, state: GameState) -> String:
	if owns_upgrade(String(entry["id"]), state):
		return "bought"
	# A KEY YOU ALREADY CARRY — from an Adventure, a story, the Dev screen —
	# is not for sale twice.
	if String(entry.get("kind", "")) == "key" and state != null and state.count(String(entry["id"])) > 0:
		return "bought"
	var by := String(entry["achievement"])
	if by != "" and not AchievementBook.earned(by, state):
		return "locked"
	if not DialogueGrammar.test(String(entry["needs"]), state):
		return "locked"
	return "for_sale"


## What still stands between you and the right to buy it, in words.
static func upgrade_lock_words(entry: Dictionary, state: GameState) -> String:
	var by := String(entry["achievement"])
	if by != "" and not AchievementBook.earned(by, state):
		for one in AchievementBook.rows():
			if String(one["id"]).to_lower() == by.to_lower():
				return "Earn the achievement %s: %s" % [one["name"], one["description"]]
		return "Earn the achievement '%s'." % by
	# A KEY waits on an unlock name; say which ACHIEVEMENT hands it out,
	# because "Needs Dorms" is not a thing you can go and do.
	for part in String(entry["needs"]).split(";", false):
		var clean := String(part).strip_edges()
		if not clean.to_lower().begins_with("unlocked:"):
			continue
		var wanted := MenuSupport.normalise(clean.substr(clean.find(":") + 1))
		if state != null and state.is_unlocked(clean.substr(clean.find(":") + 1).strip_edges()):
			continue
		for one in AchievementBook.rows():
			for handed in one["unlocks"]:
				if MenuSupport.normalise(String(handed)) == wanted:
					return "Earn the achievement %s: %s" % [one["name"], one["description"]]
	return DialogueGrammar.describe(String(entry["needs"]))


## The upgrades an achievement puts on sale — for the achievement board.
static func upgrades_from(achievement_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for one in upgrades():
		if String(one["achievement"]).to_lower() == achievement_id.to_lower():
			out.append(one)
	return out


## Buy one. Spends, sets the flag, and runs the Effect. Returns {"ok", "why"}.
static func buy_upgrade(id_text: String, state: GameState) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	var entry := find_upgrade(id_text)
	if entry.is_empty():
		return {"ok": false, "why": "there is no such upgrade"}
	match upgrade_state(entry, state):
		"bought":
			return {"ok": false, "why": "you already have it"}
		"locked":
			return {"ok": false, "why": upgrade_lock_words(entry, state)}
	var spent := _spend(int(entry["cost"]), String(entry["currency"]), state)
	if spent != "":
		return {"ok": false, "why": spent}
	state.set_flag(UPGRADE_PREFIX + String(entry["id"]).to_lower(), true)
	Progression.run_actions(String(entry["effect"]), state)
	return {"ok": true, "why": "%s. %s" % [entry["name"], entry["description"]]}


# =============================================================
#  THE BREWERS (round AN) — a Training.csv row with Kind = brewer
# =============================================================

## The brewer training row, or {} if Training.csv has none.
static func brewer_training() -> Dictionary:
	for one in training():
		if String(one["kind"]) == "brewer":
			return one
	return {}


## Train one of your recruits as a brewer. Returns {"ok", "why"}.
static func train_brewer(name_text: String, state: GameState) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	var entry := brewer_training()
	if entry.is_empty():
		return {"ok": false, "why": "Training.csv has no row with Kind = brewer"}
	if not RecruitBook.is_recruit(name_text, state):
		return {"ok": false, "why": "%s is not one of your players" % name_text}
	if BrewerBook.is_brewer(name_text, state):
		return {"ok": false, "why": "%s is a brewer already" % name_text}
	# A Match or Adventure Player is locked in his role: only retraining moves him.
	if PlayerRoles.locked(name_text, state, CardDatabase.get_db()):
		return train_role(name_text, PlayerRoles.BREWER, state)
	if not DialogueGrammar.test(String(entry["needs"]), state):
		return {"ok": false, "why": DialogueGrammar.describe(String(entry["needs"]))}
	var spent := _spend(int(entry["cost"]), String(entry["currency"]), state)
	if spent != "":
		return {"ok": false, "why": spent}
	BrewerBook.make(name_text, state)
	var eff := BrewerBook.efficiency(name_text, state)
	return {"ok": true, "why": "%s is a brewer now: efficiency %d, %d%% at a machine. He will not play again." % [
		name_text, eff, BrewerBook.success_for(eff)]}


## Train one of your players for a role: match, adventure or brewer
## (player_roles.gd). Returns {"ok", "why"}.
##
## An untrained player pays the role's own price. A player who already has a
## role is locked in it (role_lock) until Quereinsteiger opens, and then pays
## the retrain row's fee instead (Training.csv Kind = retrain).
static func train_role(name_text: String, role_text: String, state: GameState) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	var db := CardDatabase.get_db()
	if not RecruitBook.is_recruit(name_text, state):
		return {"ok": false, "why": "%s is not one of your players" % name_text}
	var mine := PlayerRoles.role(name_text, state, db)
	if not PlayerRoles.locked(name_text, state, db):
		if role_text == PlayerRoles.BREWER:
			return train_brewer(name_text, state)
		if mine == PlayerRoles.BREWER:
			return {"ok": false, "why": "%s is a brewer and will not play again" % name_text}
	if mine == role_text:
		return {"ok": false, "why": "%s is a %s already" % [name_text, PlayerRoles.label(role_text)]}
	var entry := PlayerRoles.training_row(role_text)
	if entry.is_empty():
		return {"ok": false, "why": "Training.csv has no row with Kind = %s" % PlayerRoles.KIND_OF.get(role_text, role_text)}
	if not DialogueGrammar.test(String(entry["needs"]), state):
		return {"ok": false, "why": DialogueGrammar.describe(String(entry["needs"]))}
	var price := entry
	if PlayerRoles.locked(name_text, state, db):
		price = PlayerRoles.retrain_row()
		if price.is_empty():
			return {"ok": false, "why": "%s is a %s for good" % [name_text, PlayerRoles.label(mine)]}
		if not DialogueGrammar.test(String(price["needs"]), state):
			return {"ok": false, "why": "%s is a %s until you unlock %s" % [
				name_text, PlayerRoles.label(mine), price["name"]]}
	var spent := _spend(int(price["cost"]), String(price["currency"]), state)
	if spent != "":
		return {"ok": false, "why": spent}
	if mine == PlayerRoles.BREWER:
		BrewerBook.unmake(name_text, state)
	if role_text == PlayerRoles.BREWER:
		BrewerBook.make(name_text, state)
		PlayerRoles.set_role(name_text, PlayerRoles.NEW, state)
		var eff := BrewerBook.efficiency(name_text, state)
		return {"ok": true, "why": "%s is a brewer now: efficiency %d, %d%% at a machine." % [
			name_text, eff, BrewerBook.success_for(eff)]}
	PlayerRoles.set_role(name_text, role_text, state)
	print("[roles] %s is a %s now." % [name_text, PlayerRoles.label(role_text)])
	return {"ok": true, "why": "%s is a %s now: only %ss take him." % [
		name_text, PlayerRoles.label(role_text), PlayerRoles.team_label(role_text)]}


# =============================================================
#  PAYING
# =============================================================

## Take the money. Returns "" when it worked, or why it did not.
##
## One place, because a dorm and a training pay the same way and the day
## somebody adds a third room it should not be a third copy of this.
static func _spend(price: int, currency_id: String, state: GameState) -> String:
	if price <= 0:
		return ""
	var money := ShopBook.currency(currency_id)
	if money.is_empty():
		return "'%s' is not a row of Currencies.csv" % currency_id
	var have := state.count(String(money["counter"]))
	if have < price:
		return "%d %s, and you have %d" % [price, money["name"], have]
	state.add_count(String(money["counter"]), -price)
	return ""
