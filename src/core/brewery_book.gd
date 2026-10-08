class_name BreweryBook
extends RefCounted

# =============================================================
#  THE BREWERY — data/BrewerySections.csv and data/BreweryResources.csv
#
#  ============ WHAT YOU SAID IT IS ============
#
#  "The Brewery is a map with six sections. Each section must be unlocked.
#   At the top of the map there is a resources window and a brewery-materials
#   window."
#
#      1  MALTHOUSE   Maltster   Wheat + Water + Germs        -> Malt
#      2  MILL        Miller     Malt + Water + Hammer        -> Mash
#      3  LAUTERING   Lauterer   Mash + Filter                -> Wort
#      4  BOILING     Brewer     Wort + Hops + Boiler + Element -> Brew
#      5  COOLING     Cellarman  Brew + Yeast -> Barrel, LAGERED 1-3 turns
#      6  BOTTLING    Bottler    Barrel -> several Bottles -> the Pub
#
#  ============ WHAT THIS FILE IS, AND WHAT IT IS NOT ============
#
#  It is THE CHAIN, and nothing else. No map, no buildings, no mini-games.
#
#  That is deliberate and it is the order I would build anything of this
#  shape. A production chain is a thing you get wrong in the numbers, not in
#  the pictures: if six bottles from a barrel is the wrong number, no amount
#  of drawing the Bottler fixes it, and you will have drawn him twice. So the
#  chain goes in first, `tools/brewery_check.gd` walks it end to end and tells
#  you how many bottles a starting stock is worth, and THEN the map is built
#  on top of something already known to work.
#
#  The five brewing mini-games you described sit on top of the same rows when
#  they come. A mini-game decides HOW WELL a section runs; this file decides
#  what it costs and what it gives. Neither one needs the other to exist.
#
#  ============ WHERE THE MATERIALS LIVE ============
#
#  In GameState's counters, one per resource, named `res_<id>`. Not a new
#  store: `count:res_malt>=3` is already a condition the whole game can read,
#  so an achievement, a talent, a dialogue line and a Progression row can all
#  ask how much malt you have without a line of code being written for them.
#
#  ============ AND THE LAGERING ============
#
#  A barrel is not yours when you press the button. It sits in the cellar for
#  `Wait Min` to `Wait Max` turns, and a turn is a fixture — the same turn
#  RecoveryBook counts, advanced from the same place. A section lagers ONE
#  batch at a time, which is a simplification and a deliberate one: it makes
#  the cellar a decision ("do I start this now?") instead of a queue.
# =============================================================

const RESOURCES_FILE := "res://data/BreweryResources.csv"
const SECTIONS_FILE := "res://data/BrewerySections.csv"

## Every resource is a GameState counter with this in front of its ID.
const COUNTER_PREFIX := "res_"
## THE CELLAR, AS ONE READABLE LINE PER SECTION.
##
## `brew_jobs_cooling` = "6:3|6:1" means two vats working: six barrels in
## three turns and six more in one. A text rather than a pile of counters,
## because a save you can read in the inspector is a save you can debug —
## and because the number of vats is not fixed (see BATCHES below), so there
## is no fixed number of counters to make.
const JOBS_PREFIX := "brew_jobs_"

## HOW MANY VATS A SECTION HAS, ON TOP OF ITS `Batches` COLUMN.
##
## "The most basic foundation is there free, and everything that would make
## it easier or more can be unlocked later on." So the column is what you get
## for nothing, and `count:batches_cooling+1` — in an achievement's Reward, a
## talent's Effects, a building's Action, anywhere — adds a vat. Nothing new
## had to be invented to say that: it is the counter language the whole game
## already speaks.
const BATCHES_PREFIX := "batches_"
## Set the first time the opening stock is handed out, so it is handed out
## exactly once per save. See stock_a_new_game().
const STOCKED_FLAG := "brewery_stocked"

static var _resources: Array[Dictionary] = []
static var _sections: Array[Dictionary] = []
static var _problems: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_resources = []
	_sections = []
	_problems = []
	_loaded = false


# =============================================================
#  READING THE TWO SPREADSHEETS
# =============================================================

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_resources = []
	_sections = []
	_problems = []

	var seen: Dictionary = {}
	for row in MenuSupport.read_csv(RESOURCES_FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges().to_lower()
		if id_text == "":
			continue
		if seen.has(id_text):
			_problems.append("Two resources share the ID '%s'." % id_text)
			continue
		seen[id_text] = true
		_resources.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"kind": MenuSupport.field(row, "Kind", "raw").strip_edges().to_lower(),
			"kept": MenuSupport.field(row, "Kept").strip_edges().to_lower().begins_with("y"),
			"start": maxi(0, MenuSupport.field_int(row, "Start", 0)),
			"icon": MenuSupport.field(row, "Icon").strip_edges(),
		})

	var section_ids: Dictionary = {}
	for row in MenuSupport.read_csv(SECTIONS_FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges().to_lower()
		if id_text == "":
			continue
		if section_ids.has(id_text):
			_problems.append("Two sections share the ID '%s'." % id_text)
			continue
		section_ids[id_text] = true
		_sections.append({
			"order": MenuSupport.field_int(row, "Order", _sections.size() + 1),
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"worker": MenuSupport.field(row, "Worker").strip_edges(),
			"needs": MenuSupport.field(row, "Needs").strip_edges(),
			"takes": _cost_of(MenuSupport.field(row, "Takes")),
			"makes": MenuSupport.field(row, "Makes").strip_edges().to_lower(),
			"how_many": maxi(1, MenuSupport.field_int(row, "How Many", 1)),
			"batches": maxi(1, MenuSupport.field_int(row, "Batches", 1)),
			"wait_min": maxi(0, MenuSupport.field_int(row, "Wait Min", 0)),
			"wait_max": maxi(0, MenuSupport.field_int(row, "Wait Max", 0)),
			# WHERE IT STANDS ON THE MAP, as a fraction of the yard: 0 is the
			# left/top edge, 1 the right/bottom. The same 0..1 shape
			# Buildings.csv uses, so a number you already understand moves a
			# section without anybody measuring pixels.
			"x": clampf(MenuSupport.field_float(row, "X", 0.5), 0.0, 1.0),
			"y": clampf(MenuSupport.field_float(row, "Y", 0.5), 0.0, 1.0),
			"art": MenuSupport.field(row, "Art").strip_edges(),
			# ROUND AN: how big the machine is drawn, in pixels. 0 = Tuning.csv
			# brewery_machine_size. Lets the back row be smaller than the front.
			"size": MenuSupport.field_float(row, "Size", 0.0),
			# ROUND AN: nudge the machine sideways on its platform, in picture
			# pixels (+ = right). Blank = centred on its weight.
			"shift_x": MenuSupport.field_float(row, "Shift X", 0.0),
			# ...and up or down (+ = down, toward you).
			"shift_y": MenuSupport.field_float(row, "Shift Y", 0.0),
		})

	_sections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["order"]) < int(b["order"]))

	_check_the_chain()

	if _sections.is_empty():
		print("[brewery] No BrewerySections.csv — the Brewery map has nothing on it.")
	else:
		print("[brewery] %d section(s), %d resource(s)." % [_sections.size(), _resources.size()])
	for problem in _problems:
		print("[brewery] %s" % problem)


## "wheat:1;water:1;germs:1" -> {"wheat": 1, "water": 1, "germs": 1}
static func _cost_of(text: String) -> Dictionary:
	var out: Dictionary = {}
	for part in text.split(";", false):
		var clean := String(part).strip_edges()
		if clean == "":
			continue
		var colon := clean.find(":")
		var id_text := (clean.substr(0, colon) if colon > 0 else clean).strip_edges().to_lower()
		var many := 1
		if colon > 0:
			many = maxi(1, int(clean.substr(colon + 1).strip_edges()))
		if id_text != "":
			out[id_text] = int(out.get(id_text, 0)) + many
	return out


# =============================================================
#  THE CHECK THAT IS WORTH HAVING
#
#  A production chain has exactly one way of being broken that a spreadsheet
#  cannot show you: A SECTION FED BY SOMETHING NOTHING EVER MAKES. Every cell
#  looks right, every name is spelled correctly, and the map simply cannot be
#  started. So that is what this asks.
# =============================================================

static func _check_the_chain() -> void:
	var known: Dictionary = {}
	for res in _resources:
		known[res["id"]] = res

	# What exists by the time you reach each section: everything raw, plus
	# everything an earlier section has made.
	var available: Dictionary = {}
	for res in _resources:
		if String(res["kind"]) != "made":
			available[res["id"]] = true

	for section in _sections:
		var label := "%s (section %d)" % [section["name"], int(section["order"])]

		if section["takes"].is_empty():
			_problems.append("%s takes nothing at all — it would make its output out of thin air." % label)
		for id_text in section["takes"]:
			if not known.has(id_text):
				_problems.append("%s wants '%s', which is not a row of BreweryResources.csv." % [label, id_text])
				continue
			if not available.has(id_text):
				_problems.append("%s wants '%s', but nothing before it makes any. The chain cannot be started — move the section that makes it earlier, or make '%s' a raw resource." % [label, id_text, id_text])

		var makes := String(section["makes"])
		if makes == "":
			_problems.append("%s makes nothing. A section that produces nothing is a building you can walk to and not use." % label)
		elif not known.has(makes):
			_problems.append("%s makes '%s', which is not a row of BreweryResources.csv." % [label, makes])
		else:
			if String(known[makes]["kind"]) != "made":
				_problems.append("'%s' is made by %s, so its Kind should be `made` rather than `%s`." % [makes, section["name"], known[makes]["kind"]])
			available[makes] = true

		if String(section["needs"]) == "":
			_problems.append("%s has an empty Needs, so it is open from the first minute of the game. You said every section has to be unlocked." % label)

		if int(section["wait_max"]) < int(section["wait_min"]):
			_problems.append("%s has Wait Max below Wait Min." % label)

	# A raw resource nobody starts with and nothing makes is a dead end.
	for res in _resources:
		if String(res["kind"]) == "made" or bool(res["kept"]):
			continue
		if int(res["start"]) > 0:
			continue
		var wanted := false
		for section in _sections:
			if section["takes"].has(res["id"]):
				wanted = true
				break
		if wanted:
			_problems.append("Nothing gives you '%s' — its Start is 0 and no section makes it, but a section wants it. Give it a Start, or a reward somewhere has to hand it out." % res["id"])


# =============================================================
#  WHAT THE SCREENS ASK FOR
# =============================================================

static func resources() -> Array[Dictionary]:
	_load()
	return _resources


static func sections() -> Array[Dictionary]:
	_load()
	return _sections


static func problems() -> Array[String]:
	_load()
	return _problems


static func resource(id_text: String) -> Dictionary:
	for res in resources():
		if String(res["id"]) == id_text.to_lower():
			return res
	return {}


static func section(id_text: String) -> Dictionary:
	for one in sections():
		if String(one["id"]) == id_text.to_lower():
			return one
	return {}


## The GameState counter a resource is kept in. `count:res_malt>=3` works as
## a condition anywhere in the game because of this one line.
static func counter_for(id_text: String) -> String:
	return COUNTER_PREFIX + id_text.to_lower()


static func stock(id_text: String, state: GameState) -> int:
	if state == null:
		return 0
	return state.count(counter_for(id_text))


static func add_stock(id_text: String, many: int, state: GameState) -> void:
	if state == null or many == 0:
		return
	state.add_count(counter_for(id_text), many)


## The opening stock, from the Start column.
##
## IT HAPPENS ONCE AND IT LEAVES A FLAG SAYING SO. The first version only
## filled a resource whose count was zero, which reads as "once" and is not:
## spend your last germ, walk out of the Brewery, walk back in, and it hands
## you five more. A flag is the difference between "you start with this" and
## "this is free".
static func stock_a_new_game(state: GameState) -> void:
	if state == null or state.has_flag(STOCKED_FLAG):
		return
	state.set_flag(STOCKED_FLAG, true)
	for res in resources():
		if int(res["start"]) > 0:
			state.set_count(counter_for(String(res["id"])), int(res["start"]))


## WHICH ACHIEVEMENT OPENS THIS SECTION, as {"name", "description"}.
##
## A locked door with no sign on it is just a wall. "Needs Mill" tells a
## player nothing they can act on; "Clean Sheet — win a match without
## conceding" is a thing to go and do. The answer is not stored anywhere:
## it is found by asking Achievements.csv who hands out the name this
## section's Needs is waiting for, so moving the grant to a different
## achievement changes the sign with no edit here.
##
## ROUND AN: with a `state`, a section whose achievement you HAVE but whose key
## you have not bought says so instead — "Buy the Mill Key at the Club House".
static func opened_by(section_id: String, state: GameState = null) -> Dictionary:
	var one := section(section_id)
	if one.is_empty():
		return {}
	if state != null:
		var held_all := true
		var key_id := ""
		for part in String(one["needs"]).split(";", false):
			var clean := String(part).strip_edges()
			if clean.to_lower().begins_with("unlocked:") \
					and not state.is_unlocked(clean.substr(clean.find(":") + 1).strip_edges()):
				held_all = false
			if clean.to_lower().begins_with("count:") and clean.contains("_key"):
				key_id = clean.substr(6).get_slice(">", 0).strip_edges()
		if held_all and key_id != "" and state.count(key_id) <= 0:
			var upgrade := BaseRooms.find_upgrade(key_id)
			return {"name": "Needs its key",
				"description": "Buy the %s at the Club House." % String(upgrade.get("name", key_id.replace("_", " ")))}
	for part in String(one["needs"]).split(";", false):
		var clean := String(part).strip_edges()
		if not clean.to_lower().begins_with("unlocked:"):
			continue
		var wanted := _squash(clean.substr(clean.find(":") + 1))
		for row in AchievementBook.rows():
			for handed in row["unlocks"]:
				if _squash(String(handed)) == wanted:
					return {"name": row["name"], "description": row["description"]}
	return {}


## Lowercase, letters and digits only — the same rule GameState uses on an
## unlock name, so `Master Brewer` and `master_brewer` are one name.
static func _squash(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


# =============================================================
#  WORKING A SECTION
# =============================================================

## Is the building there at all? The ordinary unlock question, asked in the
## ordinary words — see achievement_book.gd.
static func is_open(section_id: String, state: GameState) -> bool:
	var one := section(section_id)
	if one.is_empty() or state == null:
		return false
	var needs := String(one["needs"])
	if needs == "":
		return true
	return DialogueGrammar.test(needs, state)


## What you are short of, in words a screen can print.
## Empty means you can work it.
static func missing(section_id: String, state: GameState) -> Array[String]:
	var out: Array[String] = []
	var one := section(section_id)
	if one.is_empty():
		return ["there is no such section"]
	for id_text in one["takes"]:
		var want := int(one["takes"][id_text])
		var have := stock(String(id_text), state)
		if have < want:
			var res := resource(String(id_text))
			var pretty := String(res["name"]) if not res.is_empty() else String(id_text)
			out.append("%s %d/%d" % [pretty, have, want])
	return out


## HOW MANY JOBS THIS SECTION CAN HAVE RUNNING AT ONCE.
##
## Its `Batches` column plus whatever has been unlocked. One for free, more
## earned — see BATCHES_PREFIX above.
static func batches_for(section_id: String, state: GameState) -> int:
	var one := section(section_id)
	var base := int(one["batches"]) if not one.is_empty() else 1
	if state == null:
		return base
	return maxi(1, base + state.count(BATCHES_PREFIX + section_id.to_lower()))


## What is in the cellar: [{"many": 6, "turns": 3}, ...], soonest first.
static func jobs(section_id: String, state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	for piece in state.text(JOBS_PREFIX + section_id.to_lower()).split("|", false):
		var clean := String(piece).strip_edges()
		var colon := clean.find(":")
		if colon <= 0:
			continue
		out.append({
			"many": maxi(0, int(clean.substr(0, colon))),
			"turns": maxi(0, int(clean.substr(colon + 1))),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["turns"]) < int(b["turns"]))
	return out


static func _write_jobs(section_id: String, list: Array, state: GameState) -> void:
	if state == null:
		return
	var parts: Array[String] = []
	for job in list:
		parts.append("%d:%d" % [int(job["many"]), int(job["turns"])])
	state.set_text(JOBS_PREFIX + section_id.to_lower(), "|".join(parts))


## How many vats are working right now.
static func busy(section_id: String, state: GameState) -> int:
	return jobs(section_id, state).size()


## IS EVERY VAT TAKEN? This is what stops you starting another batch — not
## "is anything in the cellar", which is a different question and was the
## right one only while there was exactly one vat.
static func is_full(section_id: String, state: GameState) -> bool:
	return busy(section_id, state) >= batches_for(section_id, state)


## Anything at all in the cellar?
static func is_waiting(section_id: String, state: GameState) -> bool:
	return busy(section_id, state) > 0


## Turns until the NEXT thing comes out, or 0 if nothing is in there.
static func turns_left(section_id: String, state: GameState) -> int:
	var list := jobs(section_id, state)
	return int(list[0]["turns"]) if not list.is_empty() else 0


static func can_work(section_id: String, state: GameState) -> bool:
	return is_open(section_id, state) and missing(section_id, state).is_empty() \
		and not is_full(section_id, state)


## Do the work. Spends what it takes, and either gives you the output now or
## puts it in the cellar to lager.
##
## Returns {"ok", "why", "made", "many", "waiting", "turns"}.
##
## `spoiled` (round AN, the brewers): the batch went wrong. Everything it takes
## is still spent, and nothing is made. BrewerBook.work() rolls for it.
static func work(section_id: String, state: GameState, spoiled: bool = false) -> Dictionary:
	var out: Dictionary = {"ok": false, "why": "", "made": "", "many": 0,
		"waiting": false, "turns": 0}
	var one := section(section_id)
	if one.is_empty():
		out["why"] = "there is no section called '%s'" % section_id
		return out
	if not is_open(section_id, state):
		out["why"] = "%s is not unlocked yet" % one["name"]
		return out
	if is_full(section_id, state):
		out["why"] = "every vat at the %s is taken — %d of %d working, next one out in %d turn(s)" % [
			one["name"], busy(section_id, state),
			batches_for(section_id, state), turns_left(section_id, state)]
		return out
	var short := missing(section_id, state)
	if not short.is_empty():
		out["why"] = "not enough: " + ", ".join(short)
		return out

	# ---- spend it, except the tools ----
	for id_text in one["takes"]:
		var res := resource(String(id_text))
		if not res.is_empty() and bool(res["kept"]):
			continue     # equipment. Needed, not used up.
		add_stock(String(id_text), -int(one["takes"][id_text]), state)

	var makes := String(one["makes"])
	var many := int(one["how_many"])
	out["ok"] = true
	if spoiled:
		out["made"] = makes
		out["many"] = 0
		out["why"] = "the batch is spoiled"
		return out
	out["made"] = makes
	out["many"] = many

	var wait := 0
	if int(one["wait_max"]) > 0:
		wait = randi_range(int(one["wait_min"]), int(one["wait_max"]))
	if wait <= 0:
		add_stock(makes, many, state)
		return out

	var list := jobs(section_id, state)
	list.append({"many": many, "turns": wait})
	_write_jobs(section_id, list, state)
	out["waiting"] = true
	out["turns"] = wait
	return out


## A turn has passed — one fixture. Anything that has finished lagering comes
## out of the cellar. Call it from the same place RecoveryBook.advance_turn()
## is called, so there is one answer to "what is a turn".
##
## Returns what came out: [{"section", "made", "many"}, ...]
static func advance_turn(state: GameState) -> Array[Dictionary]:
	var came_out: Array[Dictionary] = []
	if state == null:
		return came_out
	for one in sections():
		var id_text := String(one["id"])
		var list := jobs(id_text, state)
		if list.is_empty():
			continue
		# EVERY VAT TICKS, and the ones that reach zero come out. The single
		# job this replaced could only ever finish one thing per fixture,
		# which quietly capped the whole Brewery at one barrel a match
		# however many vats you had unlocked.
		var still_going: Array[Dictionary] = []
		var out_now := 0
		for job in list:
			var left := int(job["turns"]) - 1
			if left > 0:
				still_going.append({"many": int(job["many"]), "turns": left})
			else:
				out_now += int(job["many"])
		_write_jobs(id_text, still_going, state)
		if out_now > 0:
			add_stock(String(one["makes"]), out_now, state)
			came_out.append({"section": one["name"], "made": one["makes"], "many": out_now})
	return came_out
