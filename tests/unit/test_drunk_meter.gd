extends GutTest

# =============================================================
#  THE DRUNK METER  (round AN, GUT)
#
#  Every drink fills the meter by its Inspiration %; below Tipsy no elemental
#  or inspirational brew takes hold; at Inspired he plays as a Star with the
#  star ability. A pretend save in memory - nothing on disk is touched.
# =============================================================

var db: CardDatabase
var brews: BrewDB
var state: GameState
var plain: PlayerData


func before_each() -> void:
	db = CardDatabase.get_db()
	brews = BrewDB.get_db()
	DrunkBook.reload_files()
	state = GameState.new()
	state.set_count("reed", 50)
	plain = null
	for card in db.players:
		if card != null and not card.is_star() and card.unit_type == "Lorelei":
			plain = card
			break


func after_each() -> void:
	BrewDB.restore_all()


func test_the_spreadsheets_are_clean() -> void:
	assert_eq(DrunkBook.problems(), [] as Array[String])
	assert_true(DrunkBook.threshold("brews") > 0, "a level must gate the brews")
	assert_true(DrunkBook.threshold("star") > DrunkBook.threshold("brews"))


func test_a_plain_beer_fills_the_meter_by_its_inspiration() -> void:
	var helles := brews.find("helles")
	assert_false(helles.is_empty())
	assert_true(DrunkBook.is_plain(helles))
	BrewDB.pour(plain, helles, false, state)
	assert_eq(DrunkBook.meter(plain, state), int(helles["inspiration"]))
	assert_eq(BrewDB.brew_id_for(plain, state), "", "a plain beer never sits on the card")


func test_a_sober_player_is_refused_an_elemental_brew() -> void:
	var fire := brews.find("fire")
	assert_ne(DrunkBook.refusal(plain, fire, state), "")
	BrewDB.pour(plain, fire, false, state)
	assert_eq(BrewDB.brew_id_for(plain, state), "", "nothing poured on a sober player")
	assert_eq(state.count("reed"), 50, "and nothing paid")


func test_tipsy_lets_the_brew_take_hold() -> void:
	DrunkBook.set_meter(plain, DrunkBook.threshold("brews"), state)
	var fire := brews.find("fire")
	assert_eq(DrunkBook.refusal(plain, fire, state), "")
	BrewDB.pour(plain, fire, false, state)
	assert_eq(BrewDB.brew_id_for(plain, state), "fire")
	assert_gt(DrunkBook.meter(plain, state), DrunkBook.threshold("brews"), "the brew fills the meter too")


func test_a_brew_already_on_a_sobered_player_does_nothing() -> void:
	state.set_text(BrewDB.TEMP_PREFIX + BrewDB.card_key(plain), "fire")
	brews.apply_all(db, state)
	assert_eq(plain.brew_id, "", "too sober - no overlay")
	DrunkBook.set_meter(plain, 100, state)
	brews.apply_all(db, state)
	assert_eq(plain.brew_id, "fire")


func test_inspired_plays_as_a_star_with_kochs_ability() -> void:
	DrunkBook.set_meter(plain, DrunkBook.threshold("star"), state)
	brews.apply_all(db, state)
	assert_true(plain.drunk_star)
	assert_true(plain.shows_star())
	assert_false(plain.is_star(), "the printed answer is untouched for the team sheet")
	assert_eq(plain.active_attack_ability(), "TUT_KOCH_BEER")
	assert_eq(plain.active_defend_ability(), "TUT_KOCH_BEER")
	BrewDB.restore_all()
	assert_false(plain.drunk_star)


func test_a_brew_ability_beats_the_star_one() -> void:
	DrunkBook.set_meter(plain, 100, state)
	state.set_text(BrewDB.TEMP_PREFIX + BrewDB.card_key(plain), "fire")
	brews.apply_all(db, state)
	assert_true(plain.drunk_star)
	assert_eq(plain.active_attack_ability(), String(brews.find("fire")["attack"]))


func test_a_bottle_can_be_weaker_than_the_brew() -> void:
	var fire := brews.find("fire")
	assert_eq(DrunkBook.inspiration(fire, {"inspiration": "15"}), 15)
	assert_eq(DrunkBook.inspiration(fire, {"inspiration": ""}), int(fire["inspiration"]))


func test_a_star_needs_fewer_turning_beers() -> void:
	var earth := brews.find("turn_earth")
	assert_eq(TransformBook.drinks_needed_for(plain, earth, state), 3)
	DrunkBook.set_meter(plain, DrunkBook.threshold("star"), state)
	assert_eq(TransformBook.drinks_needed_for(plain, earth, state), 1)


func test_the_whistle_sobers_everyone_up() -> void:
	DrunkBook.set_meter(plain, 80, state)
	DrunkBook.sober_up(state, db)
	assert_eq(DrunkBook.meter(plain, state), maxi(0, 80 - db.tune_int("drunk_sober_per_match", 100)))
