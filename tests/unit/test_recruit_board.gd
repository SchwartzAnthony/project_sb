extends GutTest

# =============================================================
#  THE RECRUITMENT BOARD'S LIFECYCLE  (round AI, GUT)
#
#  A pretend save in memory - nothing on disk is touched.
# =============================================================

var db: CardDatabase
var state: GameState


func before_each() -> void:
	db = CardDatabase.get_db()
	RecruitBoard.forget()
	state = GameState.new()
	state.set_count("coins", 1000)


func _first_open() -> int:
	var list := RecruitBoard.offers(state, db)
	for i in list.size():
		if String(list[i]["state"]) == "open":
			return i
	return -1


func test_a_new_board_has_someone_on_it() -> void:
	assert_true(_first_open() >= 0)


func test_names_on_the_board_are_all_different() -> void:
	var seen := {}
	for e in RecruitBoard.offers(state, db):
		if String(e["name"]) != "":
			assert_false(seen.has(e["name"]), "two men called %s" % e["name"])
			seen[e["name"]] = true


func test_signing_costs_the_price_and_empties_the_place() -> void:
	var i := _first_open()
	var cost := int((RecruitBoard.offers(state, db)[i]["row"] as Dictionary)["cost"])
	var r := RecruitBoard.sign(i, state, db)
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_eq(state.count("coins"), 1000 - cost)
	assert_eq(String(RecruitBoard.offers(state, db)[i]["state"]), "signed")


func test_the_same_place_cannot_be_signed_twice() -> void:
	var i := _first_open()
	RecruitBoard.sign(i, state, db)
	var coins := state.count("coins")
	assert_false(bool(RecruitBoard.sign(i, state, db)["ok"]))
	assert_eq(state.count("coins"), coins, "a refused signing must not take money")


func test_a_match_puts_new_men_up_and_frees_the_old_names() -> void:
	var before: Array = []
	for e in RecruitBoard.offers(state, db):
		before.append(e["name"])
	state.add_count("matches_played", 1)
	var after: Array = []
	for e in RecruitBoard.offers(state, db):
		after.append(e["name"])
	assert_ne(before, after)
	for n in before:
		if String(n) != "" and not after.has(n):
			assert_false(NameBook.held(state).has(n), "%s left the board but his name is still held" % n)


func test_releasing_a_recruit_frees_his_bed() -> void:
	var i := _first_open()
	var name_text := String(RecruitBoard.offers(state, db)[i]["name"])
	var free_before := RecruitBoard.beds_free(state, db)
	RecruitBoard.sign(i, state, db)
	assert_eq(RecruitBoard.beds_free(state, db), free_before - 1)
	assert_true(bool(RecruitBoard.release(name_text, state)["ok"]))
	assert_eq(RecruitBoard.beds_free(state, db), free_before)
	assert_false(RecruitBook.is_recruit(name_text, state))
