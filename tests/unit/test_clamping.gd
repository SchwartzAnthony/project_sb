extends GutTest

# =============================================================
#  RESOURCE CLAMPING AND NULL SAFETY  (round AI, GUT)
#
#  Keeper stamina, coins and recruitment places never underflow, and the
#  books do not crash when handed nothing.
# =============================================================

var db: CardDatabase


func before_each() -> void:
	db = CardDatabase.get_db()


func test_keeper_stamina_stays_between_zero_and_max() -> void:
	var keeper := GoalieUnit.new()
	keeper.max_stamina = 20
	keeper.current_stamina = 5
	keeper.adjust_stamina(-50)
	assert_eq(keeper.current_stamina, 0)
	keeper.adjust_stamina(500)
	assert_eq(keeper.current_stamina, 20)
	keeper.free()


func test_shot_odds_are_a_percentage_for_any_input() -> void:
	for st in [0, 1, 25, 100]:
		for p in [0, 1, 10, 99, 1000]:
			assert_between(ShotOdds.chance(st, 25, p), 0.0, 100.0, "stamina %d power %d" % [st, p])


func test_a_new_board_with_no_coins_refuses_and_stays_at_zero() -> void:
	var state := GameState.new()
	var list := RecruitBoard.offers(state, db)
	for i in list.size():
		if String(list[i]["state"]) == "open" and int((list[i]["row"] as Dictionary)["cost"]) > 0:
			assert_false(bool(RecruitBoard.sign(i, state, db)["ok"]))
	assert_eq(state.count("coins"), 0)
	assert_false(bool(RecruitBoard.reroll(state, db)["ok"]))
	assert_eq(state.count("coins"), 0)


func test_signing_a_place_that_does_not_exist_is_refused() -> void:
	var state := GameState.new()
	state.set_count("coins", 100)
	for i in [-1, 99]:
		assert_false(bool(RecruitBoard.sign(i, state, db)["ok"]))
	assert_eq(state.count("coins"), 100)


func test_books_handed_nothing_do_not_crash() -> void:
	assert_eq(RecruitBoard.offers(null, db).size(), 0)
	assert_eq(RecruitBook.names(null).size(), 0)
	assert_false(RecruitBook.is_recruit("anyone", null))
	assert_eq(ShopBook.purse("coins", null), 0)
	assert_false(bool(ShopBook.buy("anything", null)["ok"]))
	assert_eq(Referee.fouls_by(null), 0)


func test_releasing_someone_who_is_not_a_recruit_changes_nothing() -> void:
	var state := GameState.new()
	assert_false(bool(RecruitBoard.release("Nobody Atall", state)["ok"]))


func test_engine_pools_and_counters_never_go_negative() -> void:
	var e := AbilityEngine.new(db)
	e.begin_match()
	assert_eq(e.pool(false, "ore"), 0)
	e.add_to_pool(false, "ore", 2)
	assert_eq(e.pool(false, "ore"), 2)
	var c := PlayerData.new()
	c.player_name = "Counterman"
	c.tier = "I"
	c.unit_type = "Normal"
	c.player_type = "Normal"
	e.sync_field([c], [])
	assert_eq(e.counter(c, false, "burn"), 0)
	e.put_counter(c, false, "burn", 2)
	assert_eq(e.counter(c, false, "burn"), 2)
