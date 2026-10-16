extends GutTest

# =============================================================
#  THE MAIN EMBLEM  (Anthony, 15 Oct)
#
#  The Star picked before kick-off is the Main: only its Emblem turns
#  Ultimate, and once it has, it stays. Other Stars bring a Temporary
#  Emblem that stays on its Basic side.
# =============================================================

var state: GameState


func before_each() -> void:
	state = GameState.new()
	EmblemBook.new_match(state)


## Two Stars whose Emblems turn over on a counter.
func _two_stars() -> Array:
	var out := []
	for key in ClassBook.classes():
		var entry: ClassBook.ClassEntry = ClassBook.classes()[key]
		for star in entry.stars:
			var badge := EmblemBook.for_star(star)
			if badge != null and not EmblemBook._counter_in(badge.turns_on).is_empty():
				out.append(star)
				break
		if out.size() == 2:
			break
	return out


func _fill(star: PlayerData) -> void:
	var found := EmblemBook._counter_in(EmblemBook.for_star(star).turns_on)
	state.set_count(String(found["counter"]), int(found["need"]))


func test_set_main_marks_only_that_star() -> void:
	var stars := _two_stars()
	assert_eq(stars.size(), 2, "two Stars with Emblems")
	EmblemBook.set_main(stars[0], state)
	assert_true(EmblemBook.is_main(EmblemBook.for_star(stars[0]), state))
	assert_false(EmblemBook.is_main(EmblemBook.for_star(stars[1]), state))


func test_a_temporary_emblem_stays_basic() -> void:
	var stars := _two_stars()
	EmblemBook.set_main(stars[0], state)
	_fill(stars[1])
	EmblemBook.settle(stars, state)
	assert_false(EmblemBook.is_up(EmblemBook.for_star(stars[1]), state), "Temporary never turns over")


func test_the_main_turns_over_and_keeps_it_after_a_goal() -> void:
	var stars := _two_stars()
	EmblemBook.set_main(stars[0], state)
	_fill(stars[0])
	EmblemBook.settle(stars, state)
	var badge := EmblemBook.for_star(stars[0])
	assert_true(EmblemBook.is_up(badge, state), "Main turns Ultimate")
	EmblemBook.reset_after_goal(state)
	assert_true(EmblemBook.is_up(badge, state), "and stays Ultimate after a goal")


func test_a_class_without_an_unlock_row_is_open() -> void:
	assert_true(EmblemBook.class_open("NoSuchClass", state))
