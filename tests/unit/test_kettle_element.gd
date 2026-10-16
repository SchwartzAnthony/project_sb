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
var _pools: Dictionary = {}

## The tests below are about the three plain beers. Anthony's own beers
## (his System Builder save, merged 16 Oct) sit in the plain pool too, so they
## step out of it while these run.
const TEST_BEERS := ["plain_goalie", "plain_power", "plain_keeper", "keg_goalie", "kleiner_fass"]


func before_each() -> void:
	state = GameState.new()
	BreweryBook.forget()
	BreweryBook.stock_a_new_game(state, true)
	for entry in BrewDB.get_db().brews:
		if not TEST_BEERS.has(String(entry["id"])) and String(entry.get("pool", "")) != "":
			_pools[String(entry["id"])] = entry["pool"]
			entry["pool"] = ""
	Progression.run_actions("unlock:Boiling;unlock:Cooling;unlock:Bottling;"
		+ "count:boiling_key+1;count:cooling_key+1;count:bottling_key+1", state)


func after_each() -> void:
	# Put back any Brews.csv Element a test changed in memory.
	for id_text in _was:
		BrewDB.get_db().find(String(id_text))["element"] = _was[id_text]
	_was.clear()
	for id_text in _pools:
		BrewDB.get_db().find(String(id_text))["pool"] = _pools[id_text]
	_pools.clear()


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
	assert_eq(BreweryBook.stock("element", state), 30, "six of each (Start 6)")


func test_an_old_save_still_gets_the_cards_once() -> void:
	var old := GameState.new()
	old.set_flag(BreweryBook.STOCKED_FLAG, true)     # stocked before 12 Oct
	BreweryBook.stock_a_new_game(old, true)
	assert_eq(old.count("fire"), 6)
	old.set_count("fire", 0)
	BreweryBook.stock_a_new_game(old, true)
	assert_eq(old.count("fire"), 0, "handed out once, not every visit")


func test_the_element_goes_kettle_to_barrel_to_bottle() -> void:
	Progression.run_actions("count:res_wort+1;count:res_hops+1", state)
	var made := BreweryBook.work("boiling", state, false, {}, "water_element", 6)
	assert_true(bool(made["ok"]), str(made))
	assert_eq(String(made["element"]), "water")
	assert_eq(int(made["cards"]), 6)
	assert_eq(state.count("water_element"), 0, "all six cards went in (Kept = no)")
	assert_eq(BreweryBook.elements_on(BreweryBook.counter_for("brew"), state), ["water@6"] as Array[String])

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
	assert_eq(BreweryBook.elements_on("small_bottle", state),
		["water", "water", "water", "water", "water", "water"] as Array[String], "6 cards = 100%")


func test_a_bottle_only_gives_beers_of_its_element() -> void:
	_set_element("plain_goalie", "Fire")
	_set_element("plain_power", "Water")
	# plain_keeper stays blank: a Fire bottle has a Fire beer, so never it.
	Progression.run_actions("count:res_barrel+1", state)
	state.set_text(BreweryBook.ELEMENTS_PREFIX + BreweryBook.counter_for("barrel"), "fire")
	BreweryBook.work("bottling", state, false, {"counter": "small_bottle", "many": 6})
	var seen: Dictionary = {}
	for i in 40:
		seen[AdventureDB.brew_in_use({"id": "small_bottle", "use": "brew:pool:plain"}, state)] = true
	assert_true(seen.has("plain_goalie"), "the Fire beer comes out")
	assert_false(seen.has("plain_power"), "the Water beer never does")
	assert_false(seen.has("plain_keeper"), "a beer with no element does not (14 Oct)")


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


# =============================================================
#  MORE CARDS, MORE ELEMENT BOTTLES  (Anthony, 14 Oct)
# =============================================================

func test_the_odds_table_reads_20_to_100() -> void:
	assert_eq(BreweryBook.element_odds(), [20, 36, 52, 68, 84, 100] as Array[int])
	assert_eq(BreweryBook.max_element_cards(), 6)
	assert_eq(BreweryBook.element_chance(1), 20)
	assert_eq(BreweryBook.element_chance(9), 100, "more than the table = the last row")


func test_one_card_makes_about_one_in_five_fire_bottles() -> void:
	BreweryBook.dice.seed = 7
	var fire := 0
	var passion := 0
	for i in 2000:
		var one := BreweryBook.roll_bottle("fire@1")
		if one == "fire":
			fire += 1
		elif one == "passion":
			passion += 1
	assert_eq(fire + passion, 2000, "a miss is a Passion bottle")
	assert_between(fire, 330, 470, "about 20%% Fire (%d of 2000)" % fire)


func test_an_old_word_with_no_count_is_a_sure_thing() -> void:
	for i in 50:
		assert_eq(BreweryBook.roll_bottle("earth"), "earth")


func test_the_kettle_spends_the_cards_and_never_more_than_you_have() -> void:
	Progression.run_actions("count:res_wort+1;count:res_hops+1", state)
	state.set_count("fire", 3)
	var made := BreweryBook.work("boiling", state, false, {}, "fire", 6)
	assert_eq(int(made["cards"]), 3, "only three to put in")
	assert_eq(int(made["element_chance"]), 52)
	assert_eq(state.count("fire"), 0)


func test_a_large_bottle_batch_rolls_each_bottle() -> void:
	BreweryBook.dice.seed = 3
	Progression.run_actions("count:res_barrel+1", state)
	state.set_text(BreweryBook.ELEMENTS_PREFIX + BreweryBook.counter_for("barrel"), "air@3")
	var bottled := BreweryBook.work("bottling", state, false, {"counter": "large_bottle", "many": 3})
	assert_eq((bottled["bottles"] as Array).size(), 3)
	for word in bottled["bottles"]:
		assert_true(word == "air" or word == "passion", word)
	assert_eq(BreweryBook.elements_on("large_bottle", state).size(), 3)


func test_a_passion_bottle_pours_a_passion_beer() -> void:
	_set_element("plain_goalie", "Passion")
	_set_element("plain_power", "Fire")
	var seen: Dictionary = {}
	for i in 40:
		seen[BrewDB.get_db().pick_from_pool("plain", state, "passion")] = true
	assert_eq(seen.keys(), ["plain_goalie"])


func test_a_class_beer_with_no_abilities_lends_the_class_card() -> void:
	var db := CardDatabase.get_db()
	var role: PlayerData = null
	for other in db.players:
		if other != null and not other.is_star() and CardDatabase._normalise(other.unit_type) == CardDatabase._normalise("Lorelei"):
			role = other
			break
	assert_not_null(role, "a Lorelei card to borrow")
	var drinker := PlayerData.new()
	drinker.player_name = "Test Johannes"
	drinker.unit_type = "Normal"
	drinker.tier = role.tier
	drinker.base_power_left = role.base_power_left
	var beer := {"becomes": "Lorelei", "attack": "", "defend": "", "drinks": 0}
	var lent := BrewDB.class_card_for(drinker, beer)
	assert_not_null(lent)
	assert_eq(CardDatabase._normalise(lent.unit_type), CardDatabase._normalise("Lorelei"))
	assert_eq(lent.base_power_left, drinker.base_power_left)
	beer["attack"] = "BRAND_SCORCH"
	assert_null(BrewDB.class_card_for(drinker, beer), "a beer with its own ability keeps it")


func test_the_lent_card_is_random_among_the_sets_and_holds_all_match() -> void:
	var db := CardDatabase.get_db()
	var drinker := PlayerData.new()
	drinker.player_name = "Test Stephan"
	drinker.unit_type = "Normal"
	var beer := {"id": "test_lorelei", "becomes": "Lorelei", "attack": "", "defend": "", "drinks": 0}
	# a Tier and Power where more than one set has a Lorelei card
	var options: Array[PlayerData] = []
	for tier_text in ["I", "II", "III", "IV"]:
		for power in 6:
			drinker.tier = tier_text
			drinker.base_power_left = power
			options = TransformBook.choices(drinker, beer, db)
			if options.size() > 1:
				break
		if options.size() > 1:
			break
	assert_gt(options.size(), 1, "some Tier and Power has a card in several sets")
	var seen: Dictionary = {}
	for i in 60:
		var fresh := GameState.new()
		var lent := BrewDB.class_card_for(drinker, beer, fresh)
		assert_eq(lent.get_tier_clean(), drinker.get_tier_clean())
		assert_eq(lent.base_power_left, drinker.base_power_left)
		assert_eq(BrewDB.class_card_for(drinker, beer, fresh), lent, "the same card all match")
		seen[lent.player_name] = true
	assert_gt(seen.size(), 1, "a random one of the sets")


func test_a_lent_card_shows_as_name_and_card_name() -> void:
	var drinker := PlayerData.new()
	drinker.player_name = "Johannes"
	assert_eq(drinker.shown_name(), "Johannes")
	drinker.brew_alias = "Tobias"
	assert_eq(drinker.shown_name(), "Johannes : (Tobias)")
	assert_eq(NamePlate.short_name(drinker), "Johannes : (Tobias)")
	drinker.clear_brew()
	assert_eq(drinker.shown_name(), "Johannes")
