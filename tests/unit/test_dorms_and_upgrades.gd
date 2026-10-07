extends GutTest

# =============================================================
#  THE DORMS AND THE CLUB HOUSE  (round AN, GUT)
#
#  The Dorms are where every player rests (data/Resting.csv); the Club House
#  sells the upgrades an achievement gives you the right to buy
#  (data/Upgrades.csv). A pretend save in memory - nothing on disk is touched.
# =============================================================

var db: CardDatabase
var state: GameState
var _was_on: Variant


func before_each() -> void:
	db = CardDatabase.get_db()
	RecoveryBook.forget()
	BaseRooms.forget()
	state = GameState.new()
	state.set_count("coins", 2000)
	_was_on = db.tuning.get("recovery", null)
	db.tuning["recovery"] = "true"


func after_each() -> void:
	if _was_on == null:
		db.tuning.erase("recovery")
	else:
		db.tuning["recovery"] = _was_on
	db.apply_bonuses_from(null)


func _two_cards() -> Array:
	return [db.players[0], db.players[1]]


# ---- THE DORMS ----------------------------------------------

func test_the_three_activities_are_in_the_spreadsheet() -> void:
	for id_text in ["match", "adventure", "adventure_down", "brew"]:
		assert_false(RecoveryBook.cause(id_text).is_empty(), "Resting.csv has no '%s' row" % id_text)


func test_a_match_sends_the_players_to_the_dorms() -> void:
	var cards := _two_cards()
	RecoveryBook.after_match(cards, state, db)
	for card in cards:
		assert_true(RecoveryBook.is_tired(card, state), "%s should be in bed" % card.player_name)
		assert_eq(RecoveryBook.why_words(card, state), "Back from a match")
	assert_eq(RecoveryBook.in_the_dorms(db, state).size(), 2)


func test_a_brew_means_a_longer_sleep() -> void:
	var sober: PlayerData = db.players[0]
	var brewed: PlayerData = db.players[1]
	state.set_text(BrewDB.TEMP_PREFIX + BrewDB.card_key(brewed), "fire_brew")
	RecoveryBook.after_match([sober, brewed], state, db)
	var extra := int(RecoveryBook.cause("brew")["extra"])
	assert_eq(RecoveryBook.turns_left(brewed, state),
		RecoveryBook.rest_for(brewed, "match", [], db, state) + extra)
	assert_eq(RecoveryBook.why_words(brewed, state), "Sleeping off a brew")


func test_an_adventure_sends_the_party_and_the_fallen_stay_longer() -> void:
	var walker: PlayerData = db.players[0]
	var fallen: PlayerData = db.players[1]
	RecoveryBook.after_adventure([walker, fallen], [fallen], state, db)
	assert_true(RecoveryBook.is_tired(walker, state))
	assert_eq(RecoveryBook.why_words(walker, state), "Back from an Adventure")
	assert_eq(RecoveryBook.why_words(fallen, state), "Carried home from an Adventure")


func test_an_adventure_wakes_the_players_who_stayed_home() -> void:
	var sleeper: PlayerData = db.players[2]
	state.set_count(RecoveryBook.key_for(sleeper), 2)
	RecoveryBook.after_adventure([db.players[0]], [], state, db)
	assert_eq(RecoveryBook.turns_left(sleeper, state), 1)


func test_nobody_goes_to_bed_while_recovery_is_off() -> void:
	db.tuning["recovery"] = "false"
	RecoveryBook.after_match(_two_cards(), state, db)
	assert_eq(RecoveryBook.in_the_dorms(db, state).size(), 0)


func test_feather_beds_shorten_every_rest_but_never_below_one() -> void:
	var card: PlayerData = db.players[0]
	var before := RecoveryBook.rest_for(card, "match", [], db, state)
	state.set_count("tune_rest_less", 1)
	var after := RecoveryBook.rest_for(card, "match", [], db, state)
	assert_eq(after, maxi(1, before - 1))
	state.set_count("tune_rest_less", 99)
	assert_eq(RecoveryBook.rest_for(card, "match", [], db, state), 1)


# ---- THE CLUB HOUSE -----------------------------------------

func test_there_are_upgrades_and_no_problems_with_them() -> void:
	assert_gt(BaseRooms.upgrades().size(), 0)
	for problem in BaseRooms.problems():
		assert_false(problem.begins_with("Upgrade"), problem)


func test_an_upgrade_is_locked_until_its_achievement_is_earned() -> void:
	var beds := BaseRooms.find_upgrade("feather_beds")
	assert_eq(BaseRooms.upgrade_state(beds, state), "locked")
	assert_false(bool(BaseRooms.buy_upgrade("feather_beds", state)["ok"]))
	assert_eq(state.count("coins"), 2000, "a refused upgrade must not take money")


func test_earning_the_achievement_only_grants_the_right_to_buy() -> void:
	state.set_flag(AchievementBook.EARNED_PREFIX + "ten_matches", true)
	var beds := BaseRooms.find_upgrade("feather_beds")
	assert_eq(BaseRooms.upgrade_state(beds, state), "for_sale")
	assert_eq(state.count("tune_rest_less"), 0, "earning it must not hand it over")


func test_buying_spends_the_money_and_runs_the_effect_once() -> void:
	state.set_flag(AchievementBook.EARNED_PREFIX + "ten_matches", true)
	var cost := int(BaseRooms.find_upgrade("feather_beds")["cost"])
	var r := BaseRooms.buy_upgrade("feather_beds", state)
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_eq(state.count("coins"), 2000 - cost)
	assert_eq(state.count("tune_rest_less"), 1)
	assert_false(bool(BaseRooms.buy_upgrade("feather_beds", state)["ok"]), "bought twice")
	assert_eq(state.count("tune_rest_less"), 1)


func test_the_second_vat_achievement_no_longer_gives_the_vat_away() -> void:
	for row in AchievementBook.rows():
		if String(row["id"]) == "second_vat":
			assert_false(String(row["reward"]).contains("batches_cooling"))
	assert_false(BaseRooms.find_upgrade("second_vat").is_empty())
