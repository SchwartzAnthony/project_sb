extends GutTest

# =============================================================
#  GREY ITEMS  (Anthony, 15 Oct)
#
#  "Make all old items into grey items, and they can be sold at the
#   Traveling Merchant." Items.csv Sell Price, paid in Groschen.
# =============================================================


func test_reed_is_grey_and_has_a_price() -> void:
	var reed := AdventureDB.get_db().item("reed")
	assert_eq(String(reed["kind"]), "grey")
	assert_gt(int(reed["sell"]), 0)


func test_selling_pays_groschen_and_takes_the_item() -> void:
	var state := GameState.new()
	var price := int(AdventureDB.get_db().item("reed")["sell"])
	state.set_count("reed", 5)
	state.set_count("coins", 0)
	var one := ShopBook.sell("reed", state, 1)
	assert_true(bool(one["ok"]))
	assert_eq(state.count("reed"), 4)
	assert_eq(state.count("coins"), price)
	ShopBook.sell("reed", state, 0)
	assert_eq(state.count("reed"), 0, "sell all")
	assert_eq(state.count("coins"), price * 5)


func test_the_merchant_lists_only_what_you_hold() -> void:
	var state := GameState.new()
	assert_eq(ShopBook.sellable(state).size(), 0)
	state.set_count("bog_iron", 2)
	var list := ShopBook.sellable(state)
	assert_eq(list.size(), 1)
	assert_eq(String(list[0]["id"]), "bog_iron")


func test_a_normal_item_is_not_bought() -> void:
	var state := GameState.new()
	state.set_count("field_bandage", 3)
	assert_false(bool(ShopBook.sell("field_bandage", state)["ok"]))
	assert_eq(state.count("field_bandage"), 3)


func test_wheat_sells_at_the_merchant() -> void:
	var state := GameState.new()
	state.set_count("res_wheat", 3)
	state.set_count("coins", 0)
	var ids := ShopBook.sellable(state).map(func(one): return String(one["id"]))
	assert_has(ids, "res_wheat")
	assert_true(bool(ShopBook.sell("res_wheat", state, 0)["ok"]))
	assert_eq(state.count("res_wheat"), 0)
	assert_gt(state.count("coins"), 0)


func test_collected_never_goes_down() -> void:
	var state := GameState.new()
	state.add_count("res_wheat", 20)
	state.add_count("res_wheat", -15)
	state.add_count("res_wheat", 12)
	assert_eq(state.count("res_wheat"), 17)
	assert_eq(state.count("collected_res_wheat"), 32)


func test_the_brewery_store_is_in_the_bag() -> void:
	var state := GameState.new()
	state.set_count("res_hops", 4)
	var names: Array = AdventureDB.get_db().bag(state)["resources"].map(func(one): return String(one["name"]))
	assert_has(names, "Hops")
