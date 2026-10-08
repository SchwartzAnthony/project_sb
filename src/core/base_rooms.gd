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
#  So the FIRST dorm is free and holds twelve; the rest are bought. Every
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
		_dorms.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			# BEDS IS THE TOTAL, not what this row adds. Reading down the
			# column tells you the whole story of your squad size.
			"beds": maxi(0, MenuSupport.field_int(row, "Beds", 0)),
			"price": maxi(0, MenuSupport.field_int(row, "Price", 0)),
			"currency": MenuSupport.field(row, "Currency").strip_edges(),
			"requires": MenuSupport.field(row, "Requires").strip_edges(),
		})
	_dorms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["beds"]) < int(b["beds"]))

	if _dorms.is_empty():
		_problems.append("No Dorms.csv rows, so there is no bed for anybody. Write at least a free first row.")
	elif int(_dorms[0]["price"]) > 0:
		_problems.append("The smallest dorm costs %d. A new game can never buy its first bed — the first row has to be free."
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
#  THE DORMS — how many players you may keep
# =============================================================

static func dorms() -> Array[Dictionary]:
	_load()
	return _dorms


static func owns_dorm(id_text: String, state: GameState) -> bool:
	if state == null:
		return false
	return state.has_flag(DORM_PREFIX + id_text.to_lower())


## HOW MANY BEDS YOU HAVE. The free first row, plus the biggest one bought.
##
## Not a sum: `Beds` is the total a dorm gives, so buying the Long House
## after the Lean-To replaces it rather than stacking on top of it. That is
## what makes the column readable — you can see your squad size at a glance
## instead of adding up.
static func beds(state: GameState) -> int:
	var most := 0
	for dorm in dorms():
		if int(dorm["price"]) == 0 or owns_dorm(String(dorm["id"]), state):
			most = maxi(most, int(dorm["beds"]))
	return most


## The dorm you are living in right now.
static func current_dorm(state: GameState) -> Dictionary:
	var best: Dictionary = {}
	for dorm in dorms():
		if int(dorm["price"]) == 0 or owns_dorm(String(dorm["id"]), state):
			if best.is_empty() or int(dorm["beds"]) > int(best["beds"]):
				best = dorm
	return best


## Buy one. Returns {"ok", "why"}.
static func buy_dorm(id_text: String, state: GameState) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	var dorm: Dictionary = {}
	for one in dorms():
		if String(one["id"]) == id_text:
			dorm = one
			break
	if dorm.is_empty():
		return {"ok": false, "why": "there is no such dorm"}
	if owns_dorm(id_text, state):
		return {"ok": false, "why": "you already have it"}
	if int(dorm["beds"]) <= beds(state):
		return {"ok": false, "why": "%s is no bigger than what you have" % dorm["name"]}
	if not DialogueGrammar.test(String(dorm["requires"]), state):
		return {"ok": false, "why": DialogueGrammar.describe(String(dorm["requires"]))}

	var spent := _spend(int(dorm["price"]), String(dorm["currency"]), state)
	if spent != "":
		return {"ok": false, "why": spent}
	state.set_flag(DORM_PREFIX + id_text.to_lower(), true)
	return {"ok": true, "why": "%s. Room for %d now." % [dorm["name"], int(dorm["beds"])]}


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
