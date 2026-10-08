extends GutTest

# =============================================================
#  THE MATCH MAKER, THE HIDDEN TABS AND THE SONG BIRD  (round AN, GUT)
#
#  Play Match offers 3, 2 and 1 cycle friendlies (Normal, Test, Quick), each a real
#  MatchModes.csv row of the right length. The bag shows no Keys tab and
#  Team Build no Talents tab, both from Tuning.csv.
# =============================================================


func before_each() -> void:
	CardDatabase.get_db()


func test_match_maker_offers_three_two_and_one_cycle_in_that_order() -> void:
	var picks := MatchMaker.options(null)
	var modes: Array[String] = []
	for option in picks:
		modes.append(String(option["mode"]))
	assert_eq(modes, ["friendly", "friendly_test", "friendly_cycle"] as Array[String])


func test_each_length_is_the_right_match() -> void:
	var book := MatchMode.get_db()
	var two := book.find("friendly_test")
	var full := book.find("friendly")
	var one := book.find("friendly_cycle")
	assert_eq(float(two["timer"]), 60.0)
	assert_eq(int(two["cycles"]), 2)
	assert_eq(float(full["timer"]), 90.0)
	assert_eq(int(full["cycles"]), 3)
	assert_eq(int(one["cycles"]), 1)
	assert_false(bool(one["rotation"]), "one cycle means one Star")
	for row in [two, full, one]:
		assert_false(bool(row["records"]), "a friendly never goes in the table")
		assert_eq(String(row["opponent"]), "scratch")


func test_the_bag_has_no_keys_tab() -> void:
	assert_eq(InventoryScreen.shown_tabs(), ["items", "resources"] as Array[String])


func test_team_build_has_no_talents_tab() -> void:
	assert_eq(TeamBuildScreen.shown_tabs(), ["Star Hall", "Your Teams"] as Array[String])


func test_no_song_means_no_song_time() -> void:
	assert_eq(AudioDirector.song_time(null), Vector2(-1.0, 0.0))
