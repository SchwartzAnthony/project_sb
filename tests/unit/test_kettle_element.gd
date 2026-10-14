extends GutTest

# =============================================================
#  IF THIS ELEMENT, THEN THIS BEER  (round AN, Anthony 12 Oct)
#
#  The element card put in the Brew Kettle rides along to the bottle, and the
#  bottle only gives the beers of that element (or of none).
#  A pretend save in memory - nothing on disk is touched.
# =============================================================

var state: GameState
var _was: Dictionary = {}


func before_each() -> void:
	state = GameState.new()
	BreweryBook.forget()
	BreweryBook.stock_a_new_game(state)
	Progression.run_actions("unlock:Boiling;unlock:Cooling;unlock:Bottling;"
		+ "count:boiling_key+1;count:cooling_key+1;count:bottling_key+1", state)


func after_each() -> void:
	# Put back any Brews.csv Element a test changed in memory.
	for id_text in _was:
		BrewDB.get_db().find(String(id_text))["element"] = _was[id_text]
	_was.clear()


func _set_element(brew_id: String, element: String) -> void:
	var entry := BrewDB.get_db().find(brew_id)
	if not _was.has(brew_id):
		_was[brew_id] = entry["element"]
	entry["element"] = element


func test_every_save_gets_one_of_each_element_card() -> void:
	var picks := BreweryBook.choices_for("boiling", state)
	assert_eq(picks.size(), 5, "five element cards to pick from")
	var words: Array = []
	for pick in picks:
		words.append(pick["element"])
	assert_eq(words, ["fire", "water", "earth", "air", "passion"])
	assert_eq(BreweryBook.stock("element", state), 5)


func test_an_old_save_still_gets_the_cards_once() -> void:
	var old := GameState.new()
	old.set_flag(BreweryBook.STOCKED_FLAG, true)     # stocked before 12 Oct
	BreweryBook.stock_a_new_game(old)
	assert_eq(old.count("fire"), 1)
	old.set_count("fire", 0)
	BreweryBook.stock_a_new_game(old)
	assert_eq(old.count("fire"), 0, "handed out once, not every visit")


func test_the_element_goes_kettle_to_barrel_to_bottle() -> void:
	Progression.run_actions("count:res_wort+1;count:res_hops+1", state)
	var made := BreweryBook.work("boiling", state, false, {}, "water_element")
	assert_true(bool(made["ok"]), str(made))
	assert_eq(String(made["element"]), "water")
	assert_eq(state.count("water_element"), 1, "the card is kept (Kept = yes)")
	assert_eq(BreweryBook.elements_on(BreweryBook.counter_for("brew"), state), ["water"] as Array[String])

	Progression.run_actions("count:res_yeast+1", state)
	var vat := BreweryBook.work("cooling", state)
	assert_eq(String(vat["element"]), "water", "the vat knows what it is lagering")
	for i in 5:
		BreweryBook.advance_turn(state)
	assert_eq(BreweryBook.stock("barrel", state), 1)

	var bottled := BreweryBook.work("bottling", state, false, {"counter": "small_bottle", "many": 6})
	assert_eq(String(bottled["element"]), "water")
	assert_eq(state.count("small_bottle"), 6)
	assert_eq(BreweryBook.bottle_element("small_bottle", state), "water")


func test_a_bottle_only_gives_beers_of_its_element() -> void:
	_set_element("plain_goalie", "Fire")
	_set_element("plain_power", "Water")
	# plain_keeper stays blank: it comes out whatever went in.
	Progression.run_actions("count:res_barrel+1", state)
	state.set_text(BreweryBook.ELEMENTS_PREFIX + BreweryBook.counter_for("barrel"), "fire")
	BreweryBook.work("bottling", state, false, {"counter": "small_bottle", "many": 6})
	var seen: Dictionary = {}
	for i in 40:
		seen[AdventureDB.brew_in_use({"id": "small_bottle", "use": "brew:pool:plain"}, state)] = true
	assert_true(seen.has("plain_goalie"), "the Fire beer comes out")
	assert_false(seen.has("plain_power"), "the Water beer never does")
	assert_true(seen.has("plain_keeper"), "a beer with no element still can")


func test_a_bought_bottle_gives_any_beer() -> void:
	_set_element("plain_goalie", "Fire")
	state.add_count("small_bottle", 3)
	assert_eq(BreweryBook.bottle_element("small_bottle", state), "")
	var seen: Dictionary = {}
	for i in 60:
		seen[AdventureDB.brew_in_use({"id": "small_bottle", "use": "brew:pool:plain"}, state)] = true
	assert_true(seen.has("plain_goalie") and seen.has("plain_power"))


func test_opening_bottles_uses_the_oldest_first() -> void:
	state.add_count("small_bottle", 2)     # two bought, no element
	Progression.run_actions("count:res_barrel+1", state)
	state.set_text(BreweryBook.ELEMENTS_PREFIX + BreweryBook.counter_for("barrel"), "earth")
	BreweryBook.work("bottling", state, false, {"counter": "small_bottle", "many": 6})
	assert_eq(state.count("small_bottle"), 8)
	for i in 2:
		assert_eq(BreweryBook.open_bottle("small_bottle", state), "")
		state.add_count("small_bottle", -1)
	assert_eq(BreweryBook.bottle_element("small_bottle", state), "earth")
	assert_eq(BreweryBook.open_bottle("small_bottle", state), "earth")
