extends GutTest

# =============================================================
#  WHAT ANTHONY'S BOARDS NEEDED BEYOND THE CSVs  (merged 16 Oct)
# =============================================================

var state: GameState


func before_each() -> void:
	state = GameState.new()


func test_single_beds_wait_for_extra_beds() -> void:
	assert_false(BaseRooms.beds_for_sale(state))
	assert_false(bool(BaseRooms.buy_bed(state)["ok"]))
	state.unlock("Extra Beds")
	assert_true(BaseRooms.beds_for_sale(state))


func test_drops_get_likelier_further_in() -> void:
	var db := AdventureDB.get_db()
	db.drops["testtable"] = [{"item": "reed", "amount": 1, "chance": 0.0, "requires": ""}]
	assert_true(db.roll("testtable", state).is_empty(), "0% stays 0%")
	assert_eq(int(db.roll("testtable", state, 1.0).get("reed", 0)), 1, "plus 100% always drops")
	db.drops.erase("testtable")


func test_a_run_remembers_anyone_knocked_out() -> void:
	var run := AdventureRun.new()
	assert_false(run.anyone_knocked_out)
	var card := PlayerData.new()
	card.tier = "I"
	run.hurt(card, 999, CardDatabase.get_db())
	assert_true(run.anyone_knocked_out)


func test_the_new_bosses_have_bounties() -> void:
	var ids: Array = []
	for row in MenuSupport.read_csv("res://data/Bounties.csv"):
		ids.append(MenuSupport.field(row, "ID"))
	assert_true(ids.has("hill_watcher"))
	assert_true(ids.has("frost_wight"))
