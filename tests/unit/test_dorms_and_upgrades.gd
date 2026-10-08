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
	assert_eq(RecoveryBook.in_the_dorms(db, state).size(), 2)
	for card in cards:
		assert_true(RecoveryBook.is_tired(card, state), "%s should be in bed" % card.player_name)
		assert_eq(RecoveryBook.why_words(card, state), "Back from a match")


func test_a_pub_brew_no_longer_costs_extra_rest() -> void:
	# Anthony, 8 Oct: Brew Players are the BREWERS. The Pub row is switched off.
	var brewed: PlayerData = db.players[1]
	state.set_text(BrewDB.TEMP_PREFIX + BrewDB.card_key(brewed), "fire_brew")
	RecoveryBook.after_match([brewed], state, db)
	assert_false(bool(RecoveryBook.cause("brew")["on"]))
	assert_eq(RecoveryBook.turns_left(brewed, state),
		RecoveryBook.rest_for(brewed, "match", [], db, state))


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


# ---- THE BREWERS (round AN) ---------------------------------

func _a_recruit(power: int) -> String:
	var name_text := "Brauer%d" % power
	RecruitBook.enlist(name_text, "I", power, "m", state)
	return name_text


func test_a_recruit_trained_as_a_brewer_is_no_card_any_more() -> void:
	state.unlock("Training Ground")
	var who := _a_recruit(2)
	var r := BaseRooms.train_brewer(who, state)
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_true(BrewerBook.is_brewer(who, state))
	for card in RecruitBook.cards(state, db):
		assert_ne(card.player_name, who, "a brewer must never be a card")
	assert_eq(BrewerBook.efficiency(who, state), 2)


func test_efficiency_is_the_chance_from_brewers_csv() -> void:
	assert_gt(BrewerBook.success_for(5), BrewerBook.success_for(0))
	assert_gt(BrewerBook.success_for(0), BrewerBook.success_alone())


func test_a_shift_sends_the_brewer_to_the_dorms_and_a_bad_roll_spoils_it() -> void:
	state.unlock("Training Ground")
	var who := _a_recruit(1)
	BaseRooms.train_brewer(who, state)
	var section := String(BreweryBook.sections()[0]["id"])
	UnlockProgress.satisfy({"parts": UnlockProgress.progress_of(
		String(BreweryBook.section(section)["needs"]), state)["parts"], "kind": "", "name": "", "key": ""}, state)
	for id_text in (BreweryBook.section(section)["takes"] as Dictionary).keys():
		BreweryBook.add_stock(String(id_text), 10, state)
	var made := String(BreweryBook.section(section)["makes"])
	var before := BreweryBook.stock(made, state)
	var r := BrewerBook.work(section, state, db, 100)     # 100 = always fails below 100%
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_eq(String(r["brewer"]), who)
	assert_true(bool(r["spoiled"]))
	assert_eq(BreweryBook.stock(made, state), before, "a spoiled batch makes nothing")
	assert_gt(RecoveryBook.turns_left_name(who, state), 0, "he rests after his shift")
	var sleepers := RecoveryBook.in_the_dorms(db, state)
	assert_true(sleepers.any(func(e: Dictionary) -> bool: return String(e["name"]) == who and bool(e["brewer"])))
	# Resting, so the next batch is worked by nobody.
	var again := BrewerBook.work(section, state, db, 1)
	assert_eq(String(again["brewer"]), "")


# ---- THE KEYS (round AN) ------------------------------------

func test_every_building_but_the_club_house_needs_its_key() -> void:
	for entry in BaseDB.get_db().buildings:
		var needs := String(entry["requires"])
		if String(entry["id"]) == "club_house":
			assert_false(needs.contains("_key"), "the Club House is where keys are bought")
		else:
			assert_true(needs.contains("_key"), "%s has no key" % entry["name"])


func test_a_key_is_for_sale_once_its_building_is_unlocked_and_opens_it() -> void:
	var dorms: Dictionary = {}
	for entry in BaseDB.get_db().buildings:
		if String(entry["id"]) == "dorms":
			dorms = entry
	assert_eq(BaseRooms.upgrade_state(BaseRooms.find_upgrade("dorms_key"), state), "locked")
	state.unlock("Dorms")
	assert_false(DialogueGrammar.test(String(dorms["requires"]), state), "no key, no door")
	var r := BaseRooms.buy_upgrade("dorms_key", state)
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_eq(state.count("dorms_key"), 1)
	assert_true(DialogueGrammar.test(String(dorms["requires"]), state))


func test_every_key_is_an_item_in_the_keys_tab() -> void:
	var items := {}
	for row in MenuSupport.read_csv("res://data/Items.csv"):
		items[MenuSupport.field(row, "ID")] = MenuSupport.field(row, "Tab")
	for entry in BaseRooms.upgrades():
		if String(entry["kind"]) == "key":
			assert_eq(String(items.get(String(entry["id"]), "")), "keys", "%s is not an item in the Keys tab" % entry["id"])


# ---- THE DEV SCREEN'S WAKE BUTTON ---------------------------

func test_wake_gets_one_player_out_of_bed() -> void:
	var cards := _two_cards()
	RecoveryBook.after_match(cards, state, db)
	RecoveryBook.wake(cards[0].player_name, state)
	assert_false(RecoveryBook.is_tired(cards[0], state))
	assert_true(RecoveryBook.is_tired(cards[1], state))


func test_a_rest_day_gets_everybody_one_fixture_nearer_fit() -> void:
	var card: PlayerData = db.players[0]
	state.set_count(RecoveryBook.key_for(card), 2)
	var r := RecoveryBook.rest_day(state, db)
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_eq(RecoveryBook.turns_left(card, state), 1)
