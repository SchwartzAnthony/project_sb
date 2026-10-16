extends GutTest

# =============================================================
#  STAR ELEMENTAL BREWS  (Anthony, 16 Oct)
#
#  A boss drops a Star Element (100%, then half as likely every win). At the
#  Pub, Mix drink: Star Element + a bottle of that element = a Star Brew.
#  The right Tier drinks it and is a Star for good. Passion makes a plain
#  Star, whose Passion beers roll his attack and defend at random.
#  A pretend save in memory.
# =============================================================

var db: CardDatabase
var state: GameState


func before_each() -> void:
	db = CardDatabase.get_db()
	state = GameState.new()


func after_each() -> void:
	TransformBook.restore_all()
	RecruitBook.remove_all(db)
	BrewDB.restore_all()


func _recruit(name_text: String, tier: String, power: int) -> PlayerData:
	RecruitBook.enlist(name_text, tier, power, "m", state)
	TransformBook.apply_all(db, state)
	for card in db.players:
		if card.player_name == name_text:
			return card
	return null


## The card as the database has it NOW (apply_all makes new recruit cards).
func _now(name_text: String) -> PlayerData:
	TransformBook.apply_all(db, state)
	for card in db.players:
		if card.player_name == name_text:
			return card
	return null


func test_the_final_whistle_keeps_the_brewery_texts() -> void:
	state.set_text(BreweryBook.ELEMENTS_PREFIX + "small_bottle", "passion,passion")
	state.set_text(BreweryBook.JOBS_PREFIX + "cooling", "1:3:fire")
	state.set_text(BrewerBook.KEY, "Hias")
	state.set_text(BrewDB.TEMP_PREFIX + "johannes", "plain_power")
	BrewDB.clear_temporary(state)
	assert_eq(state.text(BrewDB.TEMP_PREFIX + "johannes"), "", "the poured beer wears off")
	assert_eq(state.text(BreweryBook.ELEMENTS_PREFIX + "small_bottle"), "passion,passion")
	assert_eq(state.text(BreweryBook.JOBS_PREFIX + "cooling"), "1:3:fire")
	assert_eq(state.text(BrewerBook.KEY), "Hias")


func test_the_boss_star_element_fades_by_half_each_win() -> void:
	var rows: Array = AdventureDB.get_db().drops.get("kingdrops", [])
	var star_row: Dictionary = {}
	for row in rows:
		if String(row["item"]) == "star_water_element":
			star_row = row
	assert_false(star_row.is_empty(), "the Marsh King drops the Star Water Element")
	assert_eq(float(star_row["next_time"]), 0.5)
	var first := AdventureDB.get_db().roll("king_drops", state, 0.3)
	assert_eq(int(first.get("star_water_element", 0)), 1, "100% the first time")
	assert_eq(state.count("drops_rolled_kingdrops"), 1)
	var got := 0
	for i in 400:
		state.set_count("drops_rolled_kingdrops", 1)
		got += int(AdventureDB.get_db().roll("king_drops", state).get("star_water_element", 0))
	assert_between(got, 150, 250, "about 50%% the second time (%d of 400)" % got)


func test_mix_drink_needs_a_star_element_and_a_bottle_of_that_element() -> void:
	assert_ne(StarBrewBook.mix_refusal("water", state), "", "nothing to mix")
	state.add_count("star_water_element", 1)
	assert_ne(StarBrewBook.mix_refusal("water", state), "", "no Water bottle")
	state.add_count("small_bottle", 2)
	BreweryBook._push_element("small_bottle", "passion", 1, state)
	BreweryBook._push_element("small_bottle", "water", 1, state)
	var made := StarBrewBook.mix("water", state)
	assert_true(bool(made["ok"]), str(made))
	assert_eq(state.count("star_water_brew"), 1)
	assert_eq(state.count("star_water_element"), 0)
	assert_eq(state.count("small_bottle"), 1, "one bottle used")
	assert_eq(BreweryBook.elements_on("small_bottle", state), ["passion"] as Array[String],
		"the Water one was taken, the Passion one kept")


func test_the_right_tier_becomes_a_water_star_for_good() -> void:
	var card := _recruit("Test Johannes", "II", 2)
	assert_not_null(card)
	state.add_count("star_water_brew", 1)
	var drank := StarBrewBook.drink(card, "water", state, db)
	assert_true(bool(drank["ok"]), str(drank))
	assert_eq(state.count("star_water_brew"), 0)
	assert_true(RecruitBook.is_plain_star("Test Johannes", state), "a Star")
	card = _now("Test Johannes")
	assert_eq(card.unit_type, "Lorelei")
	assert_true(card.is_star())
	assert_eq(card.player_name, "Test Johannes", "keeps his own name")
	assert_ne(card.attack_ability_id, "", "the Star's abilities")


func test_the_wrong_tier_can_never_become_that_star() -> void:
	var one := _recruit("Test Sepp", "I", 1)
	state.add_count("star_water_brew", 1)
	state.add_count("star_fire_brew", 1)
	assert_false(bool(StarBrewBook.drink(one, "water", state, db)["ok"]), "Water Stars are Tier II")
	var two := _recruit("Test Vroni", "II", 2)
	assert_false(bool(StarBrewBook.drink(two, "fire", state, db)["ok"]), "Fire Stars are Tier IV")
	assert_eq(state.count("star_water_brew"), 1, "nothing spent")
	assert_eq(state.count("star_fire_brew"), 1)


func test_passion_makes_a_plain_star_who_rolls_his_passion_beers() -> void:
	var card := _recruit("Test Wiggerl", "II", 1)
	state.add_count("star_passion_brew", 1)
	assert_true(bool(StarBrewBook.drink(card, "passion", state, db)["ok"]))
	card = _now("Test Wiggerl")
	assert_true(card.is_star())
	assert_eq(card.unit_type, "Normal", "plain: no class")
	assert_true(StarBrewBook.is_plain(card, state))
	assert_false(StarBrewBook.roll(card, state), "no Passion beers yet, no abilities")

	var passion: Array[String] = []
	for entry in BrewDB.get_db().brews:
		if CardDatabase._normalise(String(entry.get("element", ""))) == "passion" \
				and String(entry["attack"]) != "" and String(entry["defend"]) != "":
			passion.append(String(entry["id"]))
	assert_gt(passion.size(), 1, "his Passion beers have abilities")
	StarBrewBook.add_passion(card, passion[0], state)
	StarBrewBook.add_passion(card, passion[1], state)
	var pool := StarBrewBook.abilities_of(card, state)
	assert_eq(pool.size(), 4)
	var seen_two_attacks := false
	for i in 80:
		assert_true(StarBrewBook.roll(card, state))
		assert_true(pool.has(card.brew_attack_ability))
		assert_true(pool.has(card.brew_defend_ability))
		var atk_ids := [String(BrewDB.get_db().find(passion[0])["attack"]),
			String(BrewDB.get_db().find(passion[1])["attack"])]
		if atk_ids.has(card.brew_attack_ability) and atk_ids.has(card.brew_defend_ability):
			seen_two_attacks = true
	assert_true(seen_two_attacks, "fully random: two attack abilities can land together")
	BrewDB.clear_temporary(state)
	assert_eq(StarBrewBook.mix_of(card, state).size(), 0, "they wear off at the final whistle")


func test_a_star_card_shows_when_he_can_become_one() -> void:
	var card := _recruit("Test Kathi", "II", 3)
	card.brew_element = "Water"
	assert_eq(StarBrewBook.hint(card, state, db), "Can become a Water Star")
	card.brew_element = "Fire"
	assert_eq(StarBrewBook.hint(card, state, db), "", "Fire needs Tier IV")
	card.brew_element = ""
