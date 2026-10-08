extends GutTest

# =============================================================
#  THE TUTORIAL  (round AN, GUT)
#
#  The Head Coach's stops in data/MatchTalk.csv pick the right row by
#  moment, Play Maker number and Tier; every scene they name exists; Koch's
#  Beer Courage counts the plain players before him; the starting team is a
#  full, legal team.
# =============================================================


func before_each() -> void:
	DialogueDB.reload_files()
	MatchTalk.reload()


func test_every_tutorial_stop_has_its_scene() -> void:
	var names := DialogueDB.get_db().scene_names()
	for row in MenuSupport.read_csv(MatchTalk.FILE):
		if MenuSupport.field(row, "Mode").strip_edges() != "tutorial":
			continue
		var scene := MenuSupport.field(row, "Scene").strip_edges()
		assert_true(names.has(scene), "MatchTalk.csv %s: Dialogue.csv has no scene %s" % [
			MenuSupport.field(row, "ID"), scene])


func test_round_and_tier_pick_the_row() -> void:
	var r1 := MatchTalk.row_for("cards_shown", "tutorial", null, {"round": "1", "tier": "I"})
	assert_eq(String(r1.get("scene", "")), "tut-tier1")
	assert_string_contains(String(r1.get("highlight", "")), "card:first")
	var r2 := MatchTalk.row_for("cards_shown", "tutorial", null, {"round": "2", "tier": "I"})
	assert_eq(String(r2.get("scene", "")), "tut-exhaust")
	var none := MatchTalk.row_for("cards_shown", "tutorial", null, {"round": "1", "tier": "III"})
	assert_true(none.is_empty(), "no stop for Tier III")
	var other_mode := MatchTalk.row_for("cards_shown", "friendly", null, {"round": "1", "tier": "I"})
	assert_true(other_mode.is_empty(), "the tutorial's stops stay in the tutorial")
	# Three cycles (Anthony, 8 Oct): Koch plays to the final whistle, no swap.
	var swap := MatchTalk.row_for("cards_shown", "tutorial", null, {"round": "9", "tier": "star"})
	assert_true(swap.is_empty(), "no star swap in a three-cycle tutorial")
	assert_eq(int(MatchMode.get_db().find("tutorial").get("cycles", 0)), 3)


func test_time_outs_after_cycle_one_and_two() -> void:
	# After cycle 1 (the switch counts as Play Maker 3): the beer, his star
	# ability, and he stays on.
	var first := String(MatchTalk.row_for("star_switch", "tutorial", null, {"round": "3"}).get("do", ""))
	assert_string_contains(first, "pub:tut-timeout-inspiration")
	assert_string_contains(first, "ability:Koch=TUT_KOCH_BEER")
	assert_string_contains(first, "keep_star")
	# After cycle 2: the Earth Brew, the Bergmännlein, a new ability.
	var second := String(MatchTalk.row_for("star_switch", "tutorial", null, {"round": "6"}).get("do", ""))
	assert_string_contains(second, "pub:tut-timeout-cursed")
	assert_string_contains(second, "class:Koch=Bergmännlein")
	assert_string_contains(second, "ability:Koch=TUT_KOCH_EARTH/TUT_KOCH_EARTH_DEF")
	# Then his new card comes up with its abilities lit (Anthony, 8 Oct).
	assert_string_contains(second, "show_card:Koch=tut-koch-new-card")
	assert_not_null(DialogueDB.get_db().opening_line("tut-koch-new-card", null))
	assert_string_contains(second, "keep_star")
	# After cycle 3 he is swapped as usual.
	assert_true(MatchTalk.row_for("star_switch", "tutorial", null, {"round": "9"}).is_empty())
	for id in ["TUT_KOCH_BEER", "TUT_KOCH_EARTH", "TUT_KOCH_EARTH_DEF"]:
		assert_not_null(CardDatabase.get_db().get_ability(id), id)


func test_earth_courage_drains_the_enemy_keeper() -> void:
	# Anthony, 8 Oct: 5 stamina off their keeper when Koch attacks, 3 when he defends.
	var db := CardDatabase.get_db()
	var atk := db.get_ability("TUT_KOCH_EARTH")
	var def := db.get_ability("TUT_KOCH_EARTH_DEF")
	assert_eq(CardDatabase._normalise(atk.trigger), "onattack")
	assert_eq(CardDatabase._normalise(atk.effect), "drainstamina")
	assert_eq(atk.value, 5)
	assert_eq(CardDatabase._normalise(def.trigger), "ondefend")
	assert_eq(CardDatabase._normalise(def.effect), "drainstamina")
	assert_eq(def.value, 3)
	assert_true(atk.hits_goalie() and def.hits_goalie())


func test_the_opening_pub_has_no_transformation() -> void:
	var line := DialogueDB.get_db().opening_line("prologue", null)
	var moods: Array[String] = []
	while line != null:
		moods.append(line.mood)
		line = DialogueDB.get_db().line_after(line, null)
	assert_false(moods.has("bergmaennlein"), "Koch only turns at the second TIME OUT")


func _card(tier: String, power: int, star: bool = false) -> PlayerData:
	var card := PlayerData.new()
	card.tier = tier
	card.base_power_left = power
	card.base_power_right = power
	card.player_type = "Star" if star else "Normal"
	card.player_name = "%s%d" % [tier, power]
	return card


func test_beer_courage_counts_the_plain_players_before_him() -> void:
	var engine := AbilityEngine.new(CardDatabase.get_db())
	var koch := _card("IV", 3, true)
	var lineup: Array = [_card("I", 0), _card("II", 1), _card("III", 2, true), koch]
	engine.round_lineups(lineup, [])
	# Tier I and II are plain and before him; the Tier III Star does not count.
	assert_eq(engine._plain_played_before(koch, false), 2)
	assert_eq(engine._plain_played_before(lineup[0], false), 0)


func test_starting_team_is_a_full_ladder() -> void:
	var db := CardDatabase.get_db()
	var picked := SquadSheet.selection_from(db.tune_text("starting_team", "StartingTeam.csv"), db, null, false)
	assert_not_null(picked)
	var count := picked.star_bundle.size()
	for tier_key in picked.regulars.keys():
		count += (picked.regulars[tier_key] as Array).size()
	assert_eq(count, 12, "twelve players, three per Tier")


func test_a_fresh_keeper_lets_in_ten_percent_at_most() -> void:
	# Anthony, 8 Oct: full stamina never above 10%, whatever the shot.
	ShotOdds.forget()
	assert_true(ShotOdds.chance(30, 30, 22) <= 10.0)
	assert_true(ShotOdds.chance(0, 30, 0) >= 99.0, "an empty keeper is still an open goal")


func test_the_kleiner_fass() -> void:
	var item := AdventureDB.get_db().item("kleiner_fass")
	assert_false(item.is_empty(), "Items.csv kleiner_fass")
	assert_eq(AdventureDB.brew_in_use(item), "kleiner_fass")
	var brew := BrewDB.get_db().find("kleiner_fass")
	assert_eq(String(brew.get("attack", "")), "TUT_FASS_COURAGE")
	assert_eq(String(brew.get("defend", "")), "TUT_FASS_COURAGE")
	var ability := CardDatabase.get_db().get_ability("TUT_FASS_COURAGE")
	assert_eq(CardDatabase._normalise(ability.effect), "addpowerpertiermate")
	var row := MatchTalk.row_for("cards_shown", "tutorial", null, {"round": "4", "tier": "I"})
	assert_eq(String(row.get("scene", "")), "tut-fass")
	assert_string_contains(String(row.get("do", "")), "drink_lesson:first=kleiner_fass")
