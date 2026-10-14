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
## ============ IF THIS ELEMENT, THEN THIS BEER (Anthony, 12 Oct) ============
##
## "I have the one pick element, so I need an 'if' this element then this
## beer output."
##
## A BreweryResources.csv row with a `One Of` column is not one thing but a
## choice: `element` lists the five element cards (Items.csv fire,
## water_element, earth_element, air_element, no_element). The Brew Kettle
## takes `element:1`, so the player picks ONE of the cards they own.
##
## The card's Name says which element it is: "Fire Element" is Fire,
## "Passion Element" is Passion (the same rule the System Builder uses). That
## word rides along with the batch - brew, barrel in the cellar, bottle in the
## bag - kept as one readable line per counter:
##     brew_elements_brew         = "fire,fire,water"   (oldest first)
##     brew_elements_small_bottle = "fire,fire,fire,fire,fire,fire"
## When a bottle is opened, its beer is picked only from the Brews.csv pool
## rows whose Element is that element, or blank. See BrewDB.pick_from_pool().
const ELEMENTS_PREFIX := "brew_elements_"
##
## ============ MORE CARDS, MORE ELEMENT BOTTLES (Anthony, 14 Oct) ============
##
## "You add as many elements as possible to increase the % chance of getting
##  that. 1 fire element has a 20% chance for a fire bottle, adding all 6
##  gives all bottles a 100%. When the chance misses it just becomes
##  different variants of the passion brews."
##
## The kettle takes 1 to N cards of ONE element (N = the last row of
## data/ElementOdds.csv). The batch carries "fire@3" - the element and how
## many cards went in. At the Bottling Machine EVERY bottle rolls on its own
## against ElementOdds.csv: a hit is a Fire bottle, a miss is the element in
## Tuning.csv `element_miss_becomes` (passion). After that each bottle in the
## bag is plainly "fire" or "passion". A word with no "@" (an older save) is
## a sure thing.
const ODDS_FILE := "res://data/ElementOdds.csv"
## The bottle rolls. Tests seed it: BreweryBook.dice.seed = 1
static var dice := RandomNumberGenerator.new()

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
			# ROUND AN: the GameState counter it is kept in. Blank = res_<id>.
			# A bag item's ID here makes the resource THAT item: the bottles
			# the Bottling Machine fills is a small_bottle in the bag.
			"counter": MenuSupport.field(row, "Counter").strip_edges().to_lower(),
			# ROUND AN (12 Oct): `fire|water_element|...` = the player picks
			# ONE of these cards. Empty for an ordinary resource.
			"one_of": _list_of(MenuSupport.field(row, "One Of")),
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


## "fire|water_element" -> ["fire", "water_element"]
static func _list_of(text: String) -> Array[String]:
	var out: Array[String] = []
	for part in text.split("|", false):
		var clean := String(part).strip_edges().to_lower()
		if clean != "" and not out.has(clean):
			out.append(clean)
	return out


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

	# A One Of card must be a bag item (Items.csv) or a resource row.
	var item_ids: Dictionary = {}
	for row in MenuSupport.read_csv("res://data/Items.csv"):
		item_ids[MenuSupport.field(row, "ID").strip_edges().to_lower()] = true
	for res in _resources:
		for member in res["one_of"]:
			if not known.has(member) and not item_ids.has(member):
				_problems.append("'%s' has '%s' in its One Of, which is not a row of Items.csv or BreweryResources.csv." % [res["id"], member])

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
	# ROUND AN: BreweryResources.csv `Counter` names a different one - the
	# bottle is the bag's small_bottle.
	_load()
	var key := id_text.to_lower()
	var is_row := false
	for res in _resources:
		if String(res["id"]) != key:
			continue
		is_row = true
		if String(res.get("counter", "")) != "":
			return String(res["counter"])
	# A One Of card that is not a resource row is a bag item: its own ID.
	if not is_row:
		for res in _resources:
			if (res["one_of"] as Array).has(key):
				return key
	return COUNTER_PREFIX + key


## How many you have. For a One Of row (the element), every card of it you
## own added up.
static func stock(id_text: String, state: GameState) -> int:
	if state == null:
		return 0
	var res := resource(id_text)
	if not res.is_empty() and not (res["one_of"] as Array).is_empty():
		var total := 0
		for member in res["one_of"]:
			total += state.count(counter_for(String(member)))
		return total
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
##
## A One Of row's Start is given as that many of EACH of its cards, and it has
## its own flag, so a save made before the row existed still gets them once.
static func stock_a_new_game(state: GameState) -> void:
	if state == null:
		return
	if not state.has_flag(STOCKED_FLAG):
		state.set_flag(STOCKED_FLAG, true)
		for res in resources():
			if int(res["start"]) > 0 and (res["one_of"] as Array).is_empty():
				state.set_count(counter_for(String(res["id"])), int(res["start"]))
	for res in resources():
		if (res["one_of"] as Array).is_empty() or int(res["start"]) <= 0:
			continue
		var flag := STOCKED_FLAG + "_" + String(res["id"])
		if state.has_flag(flag):
			continue
		state.set_flag(flag, true)
		for member in res["one_of"]:
			var counter := counter_for(String(member))
			if state.count(counter) <= 0:
				state.set_count(counter, int(res["start"]))


# =============================================================
#  IF THIS ELEMENT, THEN THIS BEER  (round AN, 12 Oct)
# =============================================================

## % chance a bottle comes out the element, for each number of cards put in.
## [20, 36, 52, 68, 84, 100] = 1 card 20%, 6 cards 100%.
static func element_odds() -> Array[int]:
	var out: Array[int] = []
	var rows := MenuSupport.read_csv(ODDS_FILE)
	rows.sort_custom(func(a, b): return MenuSupport.field_int(a, "Cards", 0) < MenuSupport.field_int(b, "Cards", 0))
	for row in rows:
		var cards := MenuSupport.field_int(row, "Cards", 0)
		if cards <= 0:
			continue
		while out.size() < cards:
			out.append(clampi(MenuSupport.field_int(row, "Chance", 100), 0, 100))
	return out


## The most element cards the kettle takes at once. No odds file = 1.
static func max_element_cards() -> int:
	return maxi(1, element_odds().size())


## % chance per bottle with this many cards in. 0 cards = a sure thing.
static func element_chance(cards: int) -> int:
	if cards <= 0:
		return 100
	var odds := element_odds()
	if odds.is_empty():
		return 100
	return odds[mini(cards, odds.size()) - 1]


## What a bottle becomes when its roll misses (Tuning.csv element_miss_becomes).
static func element_miss() -> String:
	return CardDatabase.get_db().tune_text("element_miss_becomes", "passion").strip_edges().to_lower()


## "fire@3" -> {"element": "fire", "cards": 3}. "fire" -> cards 0 (sure).
static func split_tag(tag: String) -> Dictionary:
	var bits := tag.split("@")
	var cards := 0
	if bits.size() > 1 and String(bits[1]).is_valid_int():
		cards = int(String(bits[1]))
	return {"element": String(bits[0]).strip_edges().to_lower(), "cards": cards}


## One bottle's roll: the element, or the miss element.
static func roll_bottle(tag: String) -> String:
	var bits := split_tag(tag)
	var element := String(bits["element"])
	if element == "":
		return ""
	if dice.randi_range(1, 100) <= element_chance(int(bits["cards"])):
		return element
	return element_miss()

## The One Of row a section takes (the Brew Kettle's `element`), or {}.
static func choice_taken(section_id: String) -> Dictionary:
	var one := section(section_id)
	if one.is_empty():
		return {}
	for id_text in one["takes"]:
		var res := resource(String(id_text))
		if not res.is_empty() and not (res["one_of"] as Array).is_empty():
			return res
	return {}


## The display name of a One Of card: its resource row, else its Items.csv row.
static func card_name(card_id: String) -> String:
	var res := resource(card_id)
	if not res.is_empty():
		return String(res["name"])
	for row in MenuSupport.read_csv("res://data/Items.csv"):
		if MenuSupport.field(row, "ID").strip_edges().to_lower() == card_id.to_lower():
			return MenuSupport.field(row, "Name", card_id).strip_edges()
	return card_id


## WHICH ELEMENT A CARD IS. "Fire Element" -> "fire", "Passion Element" ->
## "passion". A name that does not end in Element is the whole name.
static func element_of_card(card_id: String) -> String:
	var name_text := card_name(card_id).strip_edges()
	if name_text.to_lower().ends_with(" element"):
		name_text = name_text.substr(0, name_text.length() - 8)
	return name_text.strip_edges().to_lower()


## The cards the player could put in right now: [{"id", "name", "element",
## "have"}], only the ones they own at least `many` of.
static func choices_for(section_id: String, state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var group := choice_taken(section_id)
	if group.is_empty() or state == null:
		return out
	var many := int(section(section_id)["takes"].get(String(group["id"]), 1))
	for member in group["one_of"]:
		var have := state.count(counter_for(String(member)))
		if have >= many:
			out.append({"id": String(member), "name": card_name(String(member)),
				"element": element_of_card(String(member)), "have": have})
	return out


## The elements riding on a counter, oldest first. "" = made with none.
static func elements_on(counter: String, state: GameState) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	for piece in state.text(ELEMENTS_PREFIX + counter.to_lower()).split(",", true):
		out.append(String(piece).strip_edges().to_lower())
	if out.size() == 1 and out[0] == "":
		out.clear()
	# Bottles can leave the bag in other ways (sold, given away). Never keep
	# more elements than there are things - the oldest go first.
	var held := state.count(counter)
	while out.size() > maxi(0, held):
		out.remove_at(0)
	return out


static func _write_elements(counter: String, list: Array[String], state: GameState) -> void:
	state.set_text(ELEMENTS_PREFIX + counter.to_lower(), ",".join(list))


## Call BEFORE the counter goes up: remembers `many` new things of `element`.
static func _push_element(counter: String, element: String, many: int, state: GameState) -> void:
	if state == null or many <= 0:
		return
	var list := elements_on(counter, state)
	if element == "" and list.is_empty():
		return     # nothing to remember, and nothing older to keep in line
	# Things already held that came with no element (bought, a reward) stay
	# in front, as blanks, so the new ones line up behind them.
	while list.size() < state.count(counter):
		list.insert(0, "")
	for i in many:
		list.append(element)
	_write_elements(counter, list, state)


## The same for things that each carry their own element (rolled bottles).
static func _push_elements(counter: String, words: Array[String], state: GameState) -> void:
	if state == null or words.is_empty():
		return
	var list := elements_on(counter, state)
	if list.is_empty() and words.all(func(w): return w == ""):
		return
	while list.size() < state.count(counter):
		list.insert(0, "")
	list.append_array(words)
	_write_elements(counter, list, state)


## Call BEFORE the counter goes down: the element of the oldest one.
static func _pop_element(counter: String, state: GameState) -> String:
	var list := elements_on(counter, state)
	if list.is_empty():
		return ""
	var held := state.count(counter)
	# Older untagged ones in front of the list are used up first.
	if held > list.size():
		return ""
	var first := list[0]
	list.remove_at(0)
	_write_elements(counter, list, state)
	return first


## THE ELEMENT OF THE NEXT BOTTLE OF THIS ITEM you would open. Does not use it.
static func bottle_element(item_id: String, state: GameState) -> String:
	if state == null or item_id == "":
		return ""
	var list := elements_on(item_id, state)
	if list.is_empty() or state.count(item_id) > list.size():
		return ""
	return list[0]


## A bottle of this item was opened: forget its element.
static func open_bottle(item_id: String, state: GameState) -> String:
	return _pop_element(item_id, state)


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
		var bits := clean.split(":")
		out.append({
			"many": maxi(0, int(bits[0])),
			"turns": maxi(0, int(bits[1])),
			# ROUND AN (12 Oct): the element the batch was brewed with.
			"element": String(bits[2]).strip_edges().to_lower() if bits.size() > 2 else "",
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["turns"]) < int(b["turns"]))
	return out


static func _write_jobs(section_id: String, list: Array, state: GameState) -> void:
	if state == null:
		return
	var parts: Array[String] = []
	for job in list:
		var element := String(job.get("element", ""))
		parts.append("%d:%d:%s" % [int(job["many"]), int(job["turns"]), element] if element != ""
			else "%d:%d" % [int(job["many"]), int(job["turns"])])
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
##
## `output` (round AN, the bottle sizes): {"counter": item ID, "many": n}
## puts that many of that item in the bag instead of the section's Makes -
## the Bottling Machine filling small bottles, large bottles or a keg. Only
## for a machine with no lagering wait (BottleSizes.csv).
##
## `pick` (round AN, 12 Oct): the card put in for a One Of take - the element
## card in the Brew Kettle. Blank or not owned = the first card you own. The
## result's "element" says which element the batch carries.
static func work(section_id: String, state: GameState, spoiled: bool = false,
		output: Dictionary = {}, pick: String = "", pick_many: int = 1) -> Dictionary:
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

	# ---- the element card put in (a One Of take) ----
	var element := ""
	var group := choice_taken(section_id)
	var chosen := ""
	if not group.is_empty():
		for choice in choices_for(section_id, state):
			if chosen == "" or String(choice["id"]) == pick.to_lower():
				chosen = String(choice["id"])
		element = element_of_card(chosen)
	var cards_in := 0
	if chosen != "":
		var takes_many := int(one["takes"].get(String(group["id"]), 1))
		cards_in = clampi(maxi(pick_many, takes_many), takes_many,
			maxi(takes_many, mini(max_element_cards(), state.count(counter_for(chosen)))))
		element = "%s@%d" % [element, cards_in]

	# ---- spend it, except the tools ----
	for id_text in one["takes"]:
		var res := resource(String(id_text))
		var many_taken := int(one["takes"][id_text])
		if not res.is_empty() and not (res["one_of"] as Array).is_empty():
			if not bool(res["kept"]) and chosen != "":
				state.add_count(counter_for(chosen), -cards_in)
			continue
		if not res.is_empty() and bool(res["kept"]):
			continue     # equipment. Needed, not used up.
		# What went in before carries its element on (brew -> barrel -> bottle).
		var counter := counter_for(String(id_text))
		for i in many_taken:
			var carried := _pop_element(counter, state)
			if element == "":
				element = carried
		add_stock(String(id_text), -many_taken, state)
	out["element"] = String(split_tag(element)["element"])
	out["cards"] = int(split_tag(element)["cards"])
	out["element_chance"] = element_chance(out["cards"]) if element != "" else 0

	var makes := String(one["makes"])
	var many := int(one["how_many"])
	out["ok"] = true
	if not output.is_empty() and not spoiled:
		# THE BOTTLES ROLL, one by one (ElementOdds.csv).
		var bottles: Array[String] = []
		for i in int(output["many"]):
			bottles.append(roll_bottle(element))
		_push_elements(String(output["counter"]), bottles, state)
		out["bottles"] = bottles
		state.add_count(String(output["counter"]), int(output["many"]))
		out["made"] = String(output["counter"])
		out["many"] = int(output["many"])
		out["item"] = true
		return out
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
		_push_element(counter_for(makes), element, many, state)
		add_stock(makes, many, state)
		return out

	var list := jobs(section_id, state)
	list.append({"many": many, "turns": wait, "element": element})
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
		var counter := counter_for(String(one["makes"]))
		for job in list:
			var left := int(job["turns"]) - 1
			if left > 0:
				still_going.append({"many": int(job["many"]), "turns": left,
					"element": String(job.get("element", ""))})
			else:
				_push_element(counter, String(job.get("element", "")), int(job["many"]), state)
				state.add_count(counter, int(job["many"]))
				out_now += int(job["many"])
		_write_jobs(id_text, still_going, state)
		if out_now > 0:
			came_out.append({"section": one["name"], "made": one["makes"], "many": out_now})
	return came_out


# =============================================================
#  THE BOTTLE SIZES  (round AN - Anthony, 8 Oct)
#
#  "The basic three beers, small bottle, large bottle and a keg."
#
#  data/BottleSizes.csv, one row per size a machine can fill:
#    Section   the BrewerySections.csv ID (bottling)
#    Item      the Items.csv ID that goes in the bag
#    Many      how many one batch fills (6 small bottles, 3 large, 1 keg)
#    Requires  the condition language. Blank = always offered
#  A machine with rows here asks which size before its mini-game. Only for
#  a machine with no lagering wait.
# =============================================================

const SIZES_FILE := "res://data/BottleSizes.csv"


## The sizes this machine offers right now: [{"item", "name", "many"}].
static func sizes_for(section_id: String, state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key := section_id.to_lower()
	for row in MenuSupport.read_csv(SIZES_FILE):
		if MenuSupport.field(row, "Section").strip_edges().to_lower() != key:
			continue
		if not DialogueGrammar.test(MenuSupport.field(row, "Requires").strip_edges(), state):
			continue
		var item := MenuSupport.field(row, "Item").strip_edges()
		if item == "":
			continue
		out.append({"item": item, "many": maxi(1, MenuSupport.field_int(row, "Many", 1)),
			"name": String(AdventureDB.get_db().item(item).get("name", item))})
	return out
