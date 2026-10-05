extends GutTest

# =============================================================
#  RULE ENFORCEMENT - FOULS AND CARDS  (round AI, GUT)
#
#  "Foul accumulation properly results in a card trigger rather than
#   dropping the state." Each test sets the referee up from nothing, does
#  one thing, and checks one rule.
#
#      godot --headless -s addons/gut/gut_cmdln.gd
# =============================================================

var db: CardDatabase


func before_each() -> void:
	db = CardDatabase.get_db()
	Referee.forget()
	Referee.clear_heat()


func test_more_triggers_never_lower_the_foul_chance() -> void:
	var before := -1.0
	for t in range(0, 15):
		var chance := float(FoulBook.odds_at(t)["chance"])
		assert_true(chance >= before, "foul chance at %d triggers (%.1f) is below the one before (%.1f)" % [t, chance, before])
		before = chance


func test_a_foul_he_misses_fills_the_bar_and_is_not_lost() -> void:
	if not Referee.on(db):
		pending("referee system is off in Tuning.csv")
		return
	var before := Referee.heat(false, db)
	Referee.got_away_with_it(false, db)
	assert_gt(Referee.heat(false, db), before, "an unseen foul must still raise the referee's bar")


func test_fouls_pile_up_until_the_bar_is_full() -> void:
	if not Referee.on(db):
		pending("referee system is off")
		return
	for i in 50:
		Referee.got_away_with_it(true, db)
	assert_true(Referee.is_full(true, db), "fifty unseen fouls must fill the bar")
	assert_eq(Referee.heat(true, db), 1.0, "the bar never goes past full")


func test_a_full_bar_makes_him_see_more_than_an_empty_one() -> void:
	if not Referee.on(db):
		pending("referee system is off")
		return
	var empty := Referee.notice_chance(false, 0, db)
	for i in 50:
		Referee.got_away_with_it(false, db)
	assert_gt(Referee.notice_chance(false, 0, db), empty)


func test_a_whistle_empties_the_bar() -> void:
	if not Referee.on(db) or String(Referee.on_duty(db)["empties_on"]) == "never":
		pending("this referee never empties his bar")
		return
	for i in 5:
		Referee.got_away_with_it(false, db)
	Referee.whistled(false, db)
	assert_eq(Referee.heat(false, db), 0.0)


func test_a_mans_own_fouls_are_remembered_and_raise_the_card_chance() -> void:
	var man := Node.new()
	assert_eq(Referee.fouls_by(man), 0)
	Referee.record_foul(man)
	Referee.record_foul(man)
	assert_eq(Referee.fouls_by(man), 2, "each foul by the same man is counted")
	assert_true(Referee.card_bump(false, 2, db) >= Referee.card_bump(false, 0, db),
		"a repeat offender is never LESS likely to be booked")
	man.free()


func test_bookings_only_ever_add_to_the_red_chance() -> void:
	assert_eq(Referee.red_bonus(0, db), 0.0, "no yellows = no extra red")
	assert_true(Referee.red_bonus(2, db) >= Referee.red_bonus(1, db))


func test_a_rolled_verdict_is_always_one_of_four_words() -> void:
	seed(1)
	for t in range(0, 12):
		for i in 50:
			var v := FoulBook.roll(t, 0.0)
			assert_true(v in ["", "free kick", "yellow", "red"], "unknown verdict '%s'" % v)


func test_a_hundred_percent_foul_is_always_called() -> void:
	seed(2)
	for i in 100:
		assert_ne(FoulBook.roll(5, 100.0), "", "a 100% foul must always happen")


func test_odds_are_clamped_between_0_and_100() -> void:
	for t in [0, 3, 50, 1000]:
		var o := FoulBook.odds_at(t)
		for k in ["chance", "yellow", "red"]:
			assert_between(float(o[k]), 0.0, 100.0, "%s at %d triggers" % [k, t])
