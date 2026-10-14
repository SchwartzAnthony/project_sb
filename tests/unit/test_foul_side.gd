extends GutTest

# =============================================================
#  FOULS ON YOUR OWN SIDE  (14 Oct, GUT)
#
#  foul_chance and foul_heat land on the OTHER side, as before. With
#  Target `side` they land on YOUR side, and a minus Value lowers them.
# =============================================================

func _ability(effect: String, target: String, value: int, scope: String = "match") -> AbilityData:
	var a := AbilityData.new()
	a.id = "TEST_FOUL"
	a.effect = effect
	a.target = target
	a.value = value
	a.scope = scope
	return a


func _engine() -> AbilityEngine:
	var e := AbilityEngine.new(CardDatabase.get_db())
	e.begin_match()
	return e


func test_foul_chance_still_lands_on_the_other_side() -> void:
	var e := _engine()
	e._referee_effect(_ability("foulchance", "self", 10), null, false)
	assert_eq(e.foul_shift(true), 10.0)
	assert_eq(e.foul_shift(false), 0.0)


func test_target_side_changes_your_own_foul_chance() -> void:
	var e := _engine()
	e._referee_effect(_ability("foulchance", "side", -15), null, false)
	assert_eq(e.foul_shift(false), -15.0)
	assert_eq(e.foul_shift(true), 0.0)


func test_the_away_side_with_target_side_changes_the_away_side() -> void:
	var e := _engine()
	e._referee_effect(_ability("foulchance", "side", 20), null, true)
	assert_eq(e.foul_shift(true), 20.0)
	assert_eq(e.foul_shift(false), 0.0)


func test_foul_heat_with_target_side_lands_on_your_own_bar() -> void:
	var e := _engine()
	e._referee_effect(_ability("foulheat", "side", 2), null, false)
	assert_eq(float(e._heat_add[false]), 2.0)
	assert_eq(float(e._heat_add[true]), 0.0)


func test_the_card_text_says_whose_fouls() -> void:
	assert_string_contains(_ability("foulchance", "side", -5)._what_words(), "you")
	assert_string_contains(_ability("foulchance", "opponent", 5)._what_words(), "they")
