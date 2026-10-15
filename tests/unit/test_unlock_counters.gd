extends GutTest

# =============================================================
#  THE NEW UNLOCK COUNTERS  (Anthony, 15 Oct)
#
#  Stats.csv rows fed by the facts a finished match now reports: its mode,
#  how many of each class played, and how many different classes.
# =============================================================

var state: GameState


func before_each() -> void:
	state = GameState.new()


func _end(facts: Dictionary) -> void:
	StatsRules.get_rules().record("match_ended", facts, state)


func test_a_season_win_counts_twice() -> void:
	_end({"result": "win", "conceded": "1", "mode": "season", "classes": "2"})
	assert_eq(state.count("season_matches"), 1)
	assert_eq(state.count("season_wins"), 1)


func test_a_quick_match_is_not_a_season_game() -> void:
	_end({"result": "win", "conceded": "0", "mode": "quick", "classes": "1"})
	assert_eq(state.count("season_matches"), 0)
	assert_eq(state.count("season_wins"), 0)


func test_three_lorelei_win() -> void:
	_end({"result": "win", "conceded": "2", "mode": "season", "class_lorelei": "2", "classes": "3"})
	assert_eq(state.count("wins_with_3_lorelei"), 0, "two is not enough")
	_end({"result": "win", "conceded": "2", "mode": "season", "class_lorelei": "3", "classes": "3"})
	assert_eq(state.count("wins_with_3_lorelei"), 1)


func test_clean_win_with_four_classes() -> void:
	_end({"result": "win", "conceded": "1", "mode": "season", "classes": "4"})
	assert_eq(state.count("clean_wins_4_classes"), 0, "not clean")
	_end({"result": "win", "conceded": "0", "mode": "season", "classes": "3"})
	assert_eq(state.count("clean_wins_4_classes"), 0, "only three classes")
	_end({"result": "win", "conceded": "0", "mode": "season", "classes": "4"})
	assert_eq(state.count("clean_wins_4_classes"), 1)
