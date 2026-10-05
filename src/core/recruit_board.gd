class_name RecruitBoard
extends RefCounted

# =============================================================
#  THE RECRUITMENT BOARD  (round AH, phase P3 - your Q123 a)
#
#  ============ WHAT IT IS ============
#
#  A board in the Club House with a few NAMED plain players on it. Sign one
#  for coins and he joins the base under his own name (recruit_book.gd). At
#  the Pub he can be brewed into a class and keeps the name.
#
#  The board is filled again after every match you play (`matches_played`
#  in Stats.csv went up). A man you did not sign goes, and his name is free.
#
#  ============ data/RecruitBoard.csv - one row per place on the board ============
#
#    Slot       a number, just to keep the rows in order
#    Tier       I, II, III or IV
#    Powers     the powers he may have, drawn at random: "0 1 2". Each needs
#               a plain card at that tier and power to copy (BasicTeam.csv -
#               see recruit_plain_class in Tuning.csv).
#    Cost       what signing him costs
#    Currency   which purse it comes out of (data/Currencies.csv): coins
#    Requires   the condition language. Blank = always. A place whose
#               Requires is not met is shown LOCKED with what it needs.
#
#  ============ Tuning.csv ============
#
#    recruit_board              false hides the board
#    recruit_beds_kept          beds kept for your team: you may hold
#                               (beds - this) recruits. The Dorms sell beds.
#    recruit_board_reroll_cost  coins to fill the board again now; 0 = no button
#
#  ============ WHERE IT LIVES IN THE SAVE ============
#
#    recruit_board       "I|1|Johannes;II|3|Lukas;-"   one entry per Slot,
#                        "-" = signed, "" = locked
#    recruit_board_at    matches_played when it was filled
#  The names on the board are HELD (names_held) so nobody else gets them
#  while they are up; they are given back when the board is filled again.
# =============================================================

const FILE := "res://data/RecruitBoard.csv"
const KEY := "recruit_board"
const AT := "recruit_board_at"
const MATCHES := "matches_played"

static var _rows: Array[Dictionary] = []
static var _problems: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_rows = []
	_problems = []
	_loaded = false


static func on(db: CardDatabase) -> bool:
	return db != null and db.tune_bool("recruit_board", true) and RecruitBook.on(db)


static func rows() -> Array[Dictionary]:
	if _loaded:
		return _rows
	_loaded = true
	_rows = []
	_problems = []
	var db := CardDatabase.get_db()
	for row in MenuSupport.read_csv(FILE):
		var tier := MenuSupport.field(row, "Tier").strip_edges().to_upper()
		if tier == "":
			continue
		var slot := MenuSupport.field(row, "Slot", str(_rows.size() + 1)).strip_edges()
		if not (tier in ["I", "II", "III", "IV"]):
			_problems.append("Slot %s: Tier '%s' is not I, II, III or IV - skipping it" % [slot, tier])
			continue
		var powers: Array[int] = []
		for piece in MenuSupport.field(row, "Powers", "0").replace(",", " ").split(" ", false):
			if not String(piece).is_valid_int():
				_problems.append("Slot %s: '%s' in Powers is not a number" % [slot, piece])
				continue
			var p := int(piece)
			if db != null and RecruitBook.template_for(tier, p, db) == null:
				_problems.append("Slot %s: there is no plain card at Tier %s Power %d to copy - leaving %d out" % [slot, tier, p, p])
				continue
			powers.append(p)
		if powers.is_empty():
			_problems.append("Slot %s: no power it can have - skipping it" % slot)
			continue
		_rows.append({
			"slot": slot,
			"tier": tier,
			"powers": powers,
			"cost": maxi(0, int(MenuSupport.field_float(row, "Cost", 0.0))),
			"currency": MenuSupport.field(row, "Currency", "coins").strip_edges(),
			"requires": MenuSupport.field(row, "Requires").strip_edges(),
		})
	for problem in _problems:
		print("[recruit board] %s" % problem)
	return _rows


static func problems() -> Array[String]:
	rows()
	return _problems


## What is on the board now: one entry per row of the file -
## {row, name, tier, power, state} with state "open", "signed" or "locked".
## Fills it again first if a match has been played since.
static func offers(state: GameState, db: CardDatabase) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or db == null:
		return out
	if state.text(KEY) == "" or state.count(AT) != state.count(MATCHES):
		refill(state, db)
	var pieces := state.text(KEY).split(";")
	var all := rows()
	for i in all.size():
		var row: Dictionary = all[i]
		var piece := String(pieces[i]) if i < pieces.size() else ""
		var entry := {"row": row, "name": "", "tier": row["tier"], "power": 0, "state": "locked"}
		if not DialogueGrammar.test(String(row["requires"]), state):
			out.append(entry)
			continue
		if piece == "-":
			entry["state"] = "signed"
		else:
			var bits := piece.split("|")
			if bits.size() >= 3 and String(bits[1]).is_valid_int():
				entry["power"] = int(bits[1])
				entry["name"] = String(bits[2])
				entry["state"] = "open"
		out.append(entry)
	return out


## Put new men up. Anybody still on it leaves and his name is free again.
static func refill(state: GameState, db: CardDatabase) -> void:
	_give_back_names(state)
	var pieces: Array[String] = []
	for row in rows():
		if not DialogueGrammar.test(String(row["requires"]), state):
			pieces.append("")
			continue
		var powers: Array[int] = row["powers"]
		var power: int = powers.pick_random()
		var who := NameBook.take(state, db)
		pieces.append("%s|%d|%s" % [row["tier"], power, who])
	state.set_text(KEY, ";".join(pieces))
	state.set_count(AT, state.count(MATCHES))


static func _give_back_names(state: GameState) -> void:
	for piece in state.text(KEY).split(";"):
		var bits := String(piece).split("|")
		if bits.size() >= 3:
			NameBook.give_back(String(bits[2]), state)


## How many more recruits there is a bed for.
static func beds_free(state: GameState, db: CardDatabase) -> int:
	var kept := db.tune_int("recruit_beds_kept", 9) if db != null else 9
	return BaseRooms.beds(state) - kept - RecruitBook.names(state).size()


## Sign the man in place `index`. Returns {"ok", "why"}.
static func sign(index: int, state: GameState, db: CardDatabase) -> Dictionary:
	var list := offers(state, db)
	if index < 0 or index >= list.size():
		return {"ok": false, "why": "Nobody is up there."}
	var entry: Dictionary = list[index]
	if String(entry["state"]) != "open":
		return {"ok": false, "why": "That place on the board is empty."}
	if beds_free(state, db) <= 0:
		return {"ok": false, "why": "No bed for him. The Dorms sell more beds; releasing a recruit frees one."}
	var row: Dictionary = entry["row"]
	var cur := ShopBook.currency(String(row["currency"]))
	var cost := int(row["cost"])
	if cost > 0:
		if cur.is_empty():
			return {"ok": false, "why": "Currency '%s' is not in data/Currencies.csv." % row["currency"]}
		if state.count(String(cur["counter"])) < cost:
			return {"ok": false, "why": "Not enough %s: he costs %d." % [cur["name"], cost]}
	# His name was held by the board - free it so he can be signed under it.
	NameBook.give_back(String(entry["name"]), state)
	var given := RecruitBook.recruit("%s%d=%s" % [entry["tier"], int(entry["power"]), entry["name"]], state, db)
	if given == "":
		NameBook.hold(String(entry["name"]), state)
		return {"ok": false, "why": "He could not be signed - see the Output panel."}
	if cost > 0:
		state.add_count(String(cur["counter"]), -cost)
	var pieces := state.text(KEY).split(";")
	if index < pieces.size():
		pieces[index] = "-"
	state.set_text(KEY, ";".join(pieces))
	return {"ok": true, "why": "%s signs for you: Tier %s, P:%d. Take him to the Pub to brew him into a class." % [given, entry["tier"], int(entry["power"])]}


## Fill the board again now, for `recruit_board_reroll_cost` coins.
static func reroll(state: GameState, db: CardDatabase) -> Dictionary:
	var cost := db.tune_int("recruit_board_reroll_cost", 10)
	if cost <= 0:
		return {"ok": false, "why": "Filling the board again is switched off (recruit_board_reroll_cost)."}
	var cur := ShopBook.currency("coins")
	if cur.is_empty() or state.count(String(cur["counter"])) < cost:
		return {"ok": false, "why": "Not enough coins: a new board costs %d." % cost}
	state.add_count(String(cur["counter"]), -cost)
	refill(state, db)
	return {"ok": true, "why": "New faces on the board."}


## Let a recruit go: he leaves the base, his bed and his name are free.
static func release(name_text: String, state: GameState) -> Dictionary:
	if not RecruitBook.is_recruit(name_text, state):
		return {"ok": false, "why": "%s is not one of your recruits." % name_text}
	SquadBook.release(name_text, state)
	RecruitBook.release(name_text, state)
	return {"ok": true, "why": "%s has packed his bag and gone." % name_text}
