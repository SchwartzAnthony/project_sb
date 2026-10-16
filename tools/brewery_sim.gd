extends SceneTree

# =============================================================
#  ONE BATCH PER ELEMENT, START TO BOTTLE  (Anthony, 14 Oct)
#
#  "Run the Brewery as a simulation ... I have all of the basic ingredients,
#   go through all the mini games, and see what it produces (and if it
#   produces anything at all)."
#
#      godot --headless --script res://tools/brewery_sim.gd
#
#  For every element card the Brew Kettle takes, with 1 card and with the
#  most (data/ElementOdds.csv) (BreweryResources.csv, the
#  One Of row): a new game, every section open, the starting stock, then
#  each machine in order through the same call the Brewery screen makes
#  after a mini-game - BrewerBook.work() with the game WON. The cellar is
#  waited out turn by turn. The Bottling Machine fills its first size.
#  Then every bottle is opened the way a match opens one, and many more
#  bottles are poured to show the odds of each beer for that element.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const POURS := 1000


func _initialize() -> void:
	var db := CardDatabase.get_db()
	var brews := BrewDB.get_db()
	var sections := BreweryBook.sections()
	var kettle := ""
	for one in sections:
		if not BreweryBook.choice_taken(String(one["id"])).is_empty():
			kettle = String(one["id"])
	if kettle == "":
		print("No machine takes an element card. Nothing to simulate.")
		quit(1)
		return
	var cards: Array = BreweryBook.choice_taken(kettle)["one_of"]
	print("")
	print("=== THE BREWERY, ONE BATCH PER ELEMENT ===")
	for problem in BreweryBook.problems():
		print("  ! %s" % problem)
	# EVERY COUNT FROM 1 TO THE MOST (Anthony, 15 Oct: "each at different %").
	var counts := range(1, BreweryBook.max_element_cards() + 1)
	for card in cards:
		for many_cards in counts:
			_one_batch(String(card), int(many_cards), kettle, sections, db, brews)
	print("")
	print("=== SUMMARY: share of bottles that came out as the element's own beer ===")
	print("  %-18s %s" % ["cards in the kettle", "  ".join(counts.map(func(n): return "%5d" % n))])
	for card in cards:
		var line: Array[String] = []
		for many_cards in counts:
			line.append("%4d%%" % int(_summary.get("%s@%d" % [card, many_cards], 0)))
		print("  %-18s %s" % [BreweryBook.card_name(String(card)), "  ".join(line)])
	quit(0)


var _summary := {}


func _open_everything(state: GameState, sections: Array[Dictionary]) -> void:
	for one in sections:
		for term in String(one["needs"]).split(";", false):
			var t := String(term).strip_edges()
			if t.begins_with("unlocked:"):
				state.unlock(t.substr(9))
			elif t.begins_with("count:"):
				var bits := t.substr(6).split(">=")
				if bits.size() == 2:
					state.set_count(bits[0], maxi(state.count(bits[0]), int(bits[1])))


func _one_batch(card: String, many_cards: int, kettle: String, sections: Array[Dictionary],
		db: CardDatabase, brews: BrewDB) -> void:
	var state := GameState.new()
	BreweryBook.stock_a_new_game(state, true)
	_open_everything(state, sections)
	state.set_count(BreweryBook.counter_for(card), BreweryBook.max_element_cards())
	var element := BreweryBook.element_of_card(card)
	print("")
	print("--- %d x %s (element: %s, %d%% a bottle) ---" % [many_cards, BreweryBook.card_name(card),
		element, BreweryBook.element_chance(many_cards)])
	var bottle_item := ""
	for one in sections:
		var id_text := String(one["id"])
		var output := {}
		var sizes := BreweryBook.sizes_for(id_text, state)
		if not sizes.is_empty():
			output = {"counter": sizes[0]["item"], "many": sizes[0]["many"]}
		# roll 0 = the mini-game was WON (brewery_screen.gd does the same)
		var result := BrewerBook.work(id_text, state, db, 0, output, card if id_text == kettle else "", many_cards)
		if not bool(result["ok"]):
			print("  %-18s STOPPED: %s" % [one["name"], result["why"]])
			return
		var turns := 0
		if bool(result.get("waiting", false)):
			while BreweryBook.busy(id_text, state) > 0 and turns < 20:
				BreweryBook.advance_turn(state)
				turns += 1
		var made := String(result["made"])
		print("  %-18s won the mini-game -> %d %s%s%s" % [one["name"], int(result["many"]),
			BreweryBook.card_name(made) if not bool(result.get("item", false)) else made,
			"  (element %s)" % result["element"] if String(result.get("element", "")) != "" else "",
			"  after %d turn(s) in the cellar" % turns if turns > 0 else ""])
		if bool(result.get("item", false)):
			bottle_item = made
	if bottle_item == "":
		var last := String(sections[-1]["makes"])
		bottle_item = BreweryBook.counter_for(last)
	var many := state.count(bottle_item)
	print("  In the bag: %d x %s, element on them: %s" % [many, bottle_item,
		", ".join(BreweryBook.elements_on(bottle_item, state))])
	var use := ""
	for row in MenuSupport.read_csv("res://data/Items.csv"):
		if MenuSupport.field(row, "ID").strip_edges() == bottle_item:
			use = MenuSupport.field(row, "Use").strip_edges()
	if not use.begins_with("brew:pool:"):
		print("  The %s does not pour a pool (Use = '%s')." % [bottle_item, use])
		return
	var pool := use.substr(10)
	var opened: Array[String] = []
	for i in many:
		# the same order as a match: read the bottle's element, pour, then
		# the bottle (and its element) leaves the bag
		var beer := brews.pick_from_pool(pool, state, BreweryBook.bottle_element(bottle_item, state))
		BreweryBook.open_bottle(bottle_item, state)
		state.add_count(bottle_item, -1)
		opened.append(String(brews.find(beer).get("name", beer)) if beer != "" else "NOTHING")
	print("  Opened them: %s" % ", ".join(opened))
	var tally := {}
	for i in POURS:
		var beer := brews.pick_from_pool(pool, state, "%s@%d" % [element, many_cards])
		tally[beer] = int(tally.get(beer, 0)) + 1
	print("  Odds over %d bottles of this element:" % POURS)
	var own := 0
	for beer in tally.keys():
		if String(brews.find(String(beer)).get("element", "")).to_lower() == element.to_lower():
			own += int(tally[beer])
	_summary["%s@%d" % [card, many_cards]] = roundi(100.0 * own / POURS)
	var keys := tally.keys()
	keys.sort_custom(func(a, b): return int(tally[a]) > int(tally[b]))
	for beer in keys:
		var entry := brews.find(String(beer))
		print("    %3d%%  %s [%s]  (Element: %s)" % [roundi(100.0 * tally[beer] / POURS), String(entry.get("name", beer)), beer,
			String(entry.get("element", "")) if String(entry.get("element", "")) != "" else "any"])
