class_name BrewerBook
extends RefCounted

# =============================================================
#  THE BREWERS — Brew Players (round AN)
#
#  ============ WHAT YOU SAID ============
#
#  "Brew Players are trained at the training hall to be only brewers. They
#   have the same number given to them as a power but that is their
#   efficiency and % of success when they work the machines."
#
#  So a brewer is one of YOUR players — a recruit — who has taken the
#  Brewer's Apprenticeship at the Training Ground (a Training.csv row with
#  Kind = brewer). From then on:
#
#      he is not a card any more   no match, no Adventure, no Pub
#      his power is his EFFICIENCY data/Brewers.csv turns it into a %
#      he works the machines       the fittest, most efficient one goes
#      then he rests               in the Dorms, Resting.csv row `brewer`
#
#  A machine with no free brewer can still be worked, at the `none` row's
#  chance. A batch that fails takes what it took and makes nothing.
#
#  `brewery_brewers` in Tuning.csv false = every batch works, as before.
#
#  ============ WHERE IT LIVES ============
#
#  In the save: `brewers` = "Johannes|Lukas", the same shape as `recruits`.
#  His tier and power stay in his recruit_<name> text — a brewer is still a
#  recruit, so his bed and his name are still his.
# =============================================================

const FILE := "res://data/Brewers.csv"
const KEY := "brewers"

static var _success: Dictionary = {}
static var _none := 40
static var _loaded := false


static func forget() -> void:
	_success = {}
	_none = 40
	_loaded = false


static func on(db: CardDatabase) -> bool:
	return db != null and db.tune_bool("brewery_brewers", true)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_success = {}
	for row in MenuSupport.read_csv(FILE):
		var key := MenuSupport.field(row, "Efficiency").strip_edges().to_lower()
		var chance := clampi(MenuSupport.field_int(row, "Success", 0), 0, 100)
		if key == "none":
			_none = chance
		elif key.is_valid_int():
			_success[int(key)] = chance


## Efficiency -> % of success. Above the last row, the last row.
static func success_for(efficiency: int) -> int:
	_load()
	if efficiency < 0:
		return _none
	if _success.has(efficiency):
		return int(_success[efficiency])
	var best := _none
	var best_at := -1
	for key in _success.keys():
		if int(key) <= efficiency and int(key) > best_at:
			best_at = int(key)
			best = int(_success[key])
	return best


## The chance with nobody at the machine.
static func success_alone() -> int:
	_load()
	return _none


# =============================================================
#  WHO THEY ARE
# =============================================================

static func names(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	for piece in state.text(KEY).split("|"):
		var clean := String(piece).strip_edges()
		# A released recruit takes his apron with him.
		if clean != "" and not out.has(clean) and RecruitBook.is_recruit(clean, state):
			out.append(clean)
	return out


static func is_brewer(name_text: String, state: GameState) -> bool:
	var wanted := CardDatabase._normalise(name_text)
	for held in names(state):
		if CardDatabase._normalise(held) == wanted:
			return true
	return false


static func _slot(name_text: String, state: GameState) -> PackedStringArray:
	if state == null:
		return PackedStringArray()
	return String(state.text(RecruitBook.PREFIX + CardDatabase._normalise(name_text))).split("|")


## His power, which for a brewer is his efficiency.
static func efficiency(name_text: String, state: GameState) -> int:
	var slot := _slot(name_text, state)
	if slot.size() >= 2 and String(slot[1]).is_valid_int():
		return int(String(slot[1]))
	return 0


static func tier(name_text: String, state: GameState) -> String:
	var slot := _slot(name_text, state)
	return String(slot[0]) if slot.size() >= 1 else ""


## Your recruits who could still be trained: not brewers already.
static func candidates(state: GameState) -> Array[String]:
	var out: Array[String] = []
	for name_text in RecruitBook.names(state):
		if not is_brewer(name_text, state):
			out.append(name_text)
	return out


## Make him a brewer. Called by BaseRooms.train_brewer(), which takes the
## money. Returns false if he cannot be one.
static func make(name_text: String, state: GameState) -> bool:
	if state == null or not RecruitBook.is_recruit(name_text, state) or is_brewer(name_text, state):
		return false
	var have := names(state)
	have.append(name_text)
	state.set_text(KEY, "|".join(have))
	print("[brewers] %s puts on the apron: efficiency %d, %d%% at a machine."
		% [name_text, efficiency(name_text, state), success_for(efficiency(name_text, state))])
	return true


## He takes the apron off again (Quereinsteiger retraining, round AN).
## Called by BaseRooms.train_role(), which takes the money.
static func unmake(name_text: String, state: GameState) -> void:
	if state == null:
		return
	var wanted := CardDatabase._normalise(name_text)
	var kept: Array[String] = []
	for held in names(state):
		if CardDatabase._normalise(held) != wanted:
			kept.append(held)
	state.set_text(KEY, "|".join(kept))
	print("[brewers] %s takes the apron off." % name_text)


## The fittest brewer with the highest efficiency, or "" if nobody is free.
static func pick(state: GameState) -> String:
	var best := ""
	var best_eff := -1
	for name_text in names(state):
		if RecoveryBook.turns_left_name(name_text, state) > 0:
			continue
		var eff := efficiency(name_text, state)
		if eff > best_eff:
			best = name_text
			best_eff = eff
	return best


## Who would work a machine right now, and his % - before anything is spent.
## The mini-game (brewery_minigame.gd) sizes its gold on this.
##     {"brewer": name or "", "chance": %}
static func chance_now(state: GameState, db: CardDatabase) -> Dictionary:
	if not on(db):
		return {"brewer": "", "chance": 100}
	var who := pick(state)
	return {"brewer": who,
		"chance": success_for(efficiency(who, state)) if who != "" else success_alone()}


# =============================================================
#  A SHIFT AT A MACHINE
# =============================================================

## Work a Brewery section WITH a brewer. What the Brewery screen calls.
## Same result as BreweryBook.work(), plus:
##     "brewer"   who worked it ("" = nobody was free)
##     "chance"   the % it had
##     "spoiled"  true = it failed: the inputs are gone, nothing was made
##     "rest"     how many fixtures he is in the Dorms for now
static func work(section_id: String, state: GameState, db: CardDatabase,
		roll: int = -1, output: Dictionary = {}) -> Dictionary:
	if not on(db):
		var plain := BreweryBook.work(section_id, state, false, output)
		plain["brewer"] = ""
		plain["chance"] = 100
		plain["spoiled"] = false
		plain["rest"] = 0
		return plain

	var who := pick(state)
	var chance := success_for(efficiency(who, state)) if who != "" else success_alone()
	var dice := roll if roll >= 0 else randi_range(1, 100)
	var spoiled := dice > chance
	var out := BreweryBook.work(section_id, state, spoiled, output)
	out["brewer"] = who
	out["chance"] = chance
	out["spoiled"] = spoiled and bool(out["ok"])
	out["rest"] = 0
	if bool(out["ok"]) and who != "" and db != null and db.tune_bool("recovery", false):
		out["rest"] = RecoveryBook.send_name_to_dorms(who, efficiency(who, state),
			"brewer", [], state, db)
	return out
