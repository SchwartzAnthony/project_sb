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
	var picks := {"malthouse": "stir", "mill": "rhythm", "lautering": "colour",
		"boiling": "fire", "cooling": "hold", "bottling": "conveyor"}
	for section in BreweryBook.sections():
		var game := BreweryMinigame.game_for(String(section["id"]))
		assert_false(game.is_empty(), "%s has a BreweryGames.csv row" % section["id"])
		assert_eq(String(game["kind"]), String(picks.get(section["id"], "")), "%s is Anthony's pick" % section["id"])
		assert_true(float(game["seconds"]) >= 5.0 and float(game["seconds"]) <= 15.0,
			"%s takes 5-15 seconds" % section["id"])


func _game(section: String, forgiving: bool, success := 100) -> BreweryMinigame:
	var view := BreweryMinigame.new()
	view.game = BreweryMinigame.game_for(section)
	view.chance = success
	view.forgiving = forgiving
	add_child_autofree(view)
	view.set_process(false)
	return view


## Play it with the good hand until it is over, as fast as the frames go.
func _bot(view: BreweryMinigame) -> void:
	var guard := 0
	while not view._over and guard < 3000:
		view.bot_step(1.0 / 60.0)
		guard += 1


func test_a_good_hand_wins_every_game_in_time() -> void:
	for section in BreweryBook.sections():
		for success in [100, 85]:
			var view := _game(String(section["id"]), false, success)
			_bot(view)
			assert_true(view._won, "%s at %d%%: %s" % [section["id"], success, view._status.text if view._status else ""])


func test_a_trained_brewer_has_it_easier() -> void:
	var fire := _game("boiling", false, 100)
	var fire_green := _game("boiling", false, 40)
	assert_gt(fire.fire_half(), fire_green.fire_half(), "a wider gold at the kettle")
	var bottles := _game("bottling", false, 100)
	var bottles_green := _game("bottling", false, 40)
	assert_gt(bottles.pour_tolerance(), bottles_green.pour_tolerance(), "more room at the fill line")
	var row := BreweryMinigame.game_for("cooling")
	assert_gt(BreweryMinigame.zone_for(row, 100), BreweryMinigame.zone_for(row, 40))


func test_stop_stirring_and_it_clumps() -> void:
	var view := _game("malthouse", false)
	for i in 600:
		view.tick(1.0 / 60.0)
	assert_true(view._over and not view._won, "standing still clumps the mash")


func test_the_same_side_twice_jams_the_mill() -> void:
	var view := _game("mill", false)
	view.side("L")
	var ground := float(view.s["ground"])
	view.side("L")
	assert_gt(float(view.s["jam"]), 0.0, "jammed")
	assert_lt(float(view.s["ground"]), ground, "a jam loses a little")
	view.side("R")
	assert_lt(float(view.s["ground"]), ground, "no grinding while jammed")


func test_cloudy_wort_spoils_the_lauter() -> void:
	var view := _game("lautering", false)
	view.press()
	for i in 1200:
		view.tick(1.0 / 60.0)
		if view._over:
			break
	assert_true(view._over and not view._won, "holding the tap open through the cloud")


func test_hold_wins_in_the_gold_and_spills_over_the_top() -> void:
	var view := _game("cooling", false)
	view.press()
	var guard := 0
	while not view.in_zone() and guard < 2000:
		view.tick(0.01)
		guard += 1
	view.release()
	assert_true(view._won, "let go in the gold")

	var spill := _game("cooling", false)
	spill.press()
	for i in 400:
		spill.tick(0.01)
	assert_true(spill._over and not spill._won, "held past the top")


func test_an_overflowing_bottle_spoils_it() -> void:
	var view := _game("bottling", false)
	view.press()
	for i in 400:
		view.tick(0.01)
	assert_true(view._over and not view._won)


func test_the_tutorial_game_cannot_be_lost() -> void:
	var view := _game("bottling", true)
	view.press()
	for i in 400:
		view.tick(0.01)      # overflows
	assert_false(view._over, "a miss starts it again")
	_bot(view)
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
