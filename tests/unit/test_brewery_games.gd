extends GutTest

# =============================================================
#  THE BREWING MINI-GAMES, PLAIN BEER AND THE TUTORIAL BREWERY  (round AN)
#
#  A pretend save in memory - nothing on disk is touched.
# =============================================================

var state: GameState


func before_each() -> void:
	state = GameState.new()
	BreweryBook.forget()
	BreweryMinigame.reload()
	Guide.reload()


func test_every_machine_has_a_game() -> void:
	for section in BreweryBook.sections():
		var game := BreweryMinigame.game_for(String(section["id"]))
		assert_false(game.is_empty(), "%s has a BreweryGames.csv row" % section["id"])
		assert_true(String(game["kind"]) in ["bar", "hold", "mash"], "%s kind" % section["id"])
		assert_true(float(game["seconds"]) >= 5.0 and float(game["seconds"]) <= 15.0,
			"%s takes 5-15 seconds" % section["id"])


func test_a_trained_brewer_gets_more_gold() -> void:
	var row := BreweryMinigame.game_for("boiling")
	assert_gt(BreweryMinigame.zone_for(row, 100), BreweryMinigame.zone_for(row, 55))
	assert_gt(BreweryMinigame.zone_for(row, 55), BreweryMinigame.zone_for(row, 40))
	var mash := BreweryMinigame.game_for("mill")
	assert_lt(BreweryMinigame.clicks_for(mash, 100), BreweryMinigame.clicks_for(mash, 40))


func _game(section: String, forgiving: bool) -> BreweryMinigame:
	var view := BreweryMinigame.new()
	view.game = BreweryMinigame.game_for(section)
	view.chance = 100
	view.forgiving = forgiving
	add_child_autofree(view)
	view.set_process(false)
	return view


func test_hold_wins_in_the_gold_and_spills_over_the_top() -> void:
	var view := _game("malthouse", false)
	watch_signals(view)
	view.press()
	var guard := 0
	while not view.in_zone() and guard < 2000:
		view.tick(0.01)
		guard += 1
	view.release()
	assert_true(view._won, "let go in the gold")

	var spill := _game("malthouse", false)
	spill.press()
	for i in 400:
		spill.tick(0.01)
	assert_true(spill._over and not spill._won, "held past the top")


func test_the_tutorial_game_cannot_be_lost() -> void:
	var view := _game("bottling", true)
	view._pos = 0.0
	view._zone_start = 0.5
	view.press()          # a miss
	assert_false(view._over, "a miss starts it again")
	for i in 3:
		view._pos = view._zone_start + 0.01
		view.press()
	assert_true(view._won)


func test_mash_fills_with_clicks() -> void:
	var view := _game("mill", false)
	for i in BreweryMinigame.clicks_for(view.game, 100):
		view.press()
	assert_true(view._won)


func test_bottles_are_plain_beer_in_the_bag() -> void:
	assert_eq(BreweryBook.counter_for("bottle"), "small_bottle")
	assert_eq(BreweryBook.counter_for("malt"), "res_malt")


func test_the_basic_three_beers() -> void:
	var sizes := BreweryBook.sizes_for("bottling", state)
	var items: Array = sizes.map(func(one: Dictionary) -> String: return String(one["item"]))
	assert_eq(items, ["small_bottle", "large_bottle", "keg"])
	assert_eq(sizes.map(func(one: Dictionary) -> int: return int(one["many"])), [6, 3, 1])
	var adventure := AdventureDB.get_db()
	for item in items:
		assert_true(String(adventure.item(String(item)).get("use", "")).begins_with("brew:pool:"), "%s is plain beer" % item)
	state.set_flag("tut_brewery", true)
	assert_eq(BreweryBook.sizes_for("bottling", state).size(), 1, "the tutorial only bottles small bottles")


func test_plain_beer_is_a_good_and_a_bad_side_and_never_on_tap() -> void:
	var brews := BrewDB.get_db()
	var db := CardDatabase.get_db()
	for entry in brews.available_for(state):
		assert_eq(String(entry.get("pool", "")), "", "%s is not poured at the Pub" % entry["id"])
	for i in 20:
		var id_text := AdventureDB.brew_in_use({"use": "brew:pool:plain"}, state)
		assert_ne(id_text, "")
		var entry := brews.find(id_text)
		assert_not_null(db.get_ability(String(entry["attack"])), "%s attack" % id_text)
		assert_not_null(db.get_ability(String(entry["defend"])), "%s defend" % id_text)
		assert_false(DrunkBook.needs_drunk(entry), "plain beer takes hold sober")


func test_the_keg_has_its_own_pool() -> void:
	for i in 20:
		var id_text := AdventureDB.brew_in_use({"use": "brew:pool:keg"}, state)
		assert_true(id_text in ["keg_goalie", "plain_power", "plain_keeper"], id_text)


func test_the_tutorial_only_pours_the_goalie_pair() -> void:
	state.set_flag("in_tutorial", true)
	for i in 20:
		assert_eq(AdventureDB.brew_in_use({"use": "brew:pool:plain"}, state), "plain_goalie")


func test_the_tutorial_brewery_steps_line_up() -> void:
	var dialogue := DialogueDB.get_db()
	for scene in ["tut-brewery-hanna", "tut-brewery-skip", "tut-brewery-done"]:
		assert_true(dialogue.scene_names().has(scene), "Dialogue.csv has %s" % scene)
	# Step 1's Then opens both machines, step 2 hands over the barrel.
	state.set_flag("tut_brewery", true)
	BreweryBook.stock_a_new_game(state)
	Progression.run_actions("unlock:Malthouse;unlock:Bottling;count:malthouse_key+1;count:bottling_key+1", state)
	assert_true(BreweryBook.can_work("malthouse", state))
	assert_true(BrewerBook.work("malthouse", state, CardDatabase.get_db(), 0)["ok"])
	assert_eq(BreweryBook.stock("malt", state), 1)
	Progression.run_actions("count:res_barrel+1", state)
	var small := BreweryBook.sizes_for("bottling", state)[0]
	assert_true(BrewerBook.work("bottling", state, CardDatabase.get_db(), 0,
		{"counter": small["item"], "many": small["many"]})["ok"])
	assert_eq(state.count("small_bottle"), 6, "a barrel is six small bottles")
	assert_eq(BreweryBook.stock("barrel", state), 0, "the barrel was used")
