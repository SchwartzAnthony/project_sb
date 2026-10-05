extends GutTest

# =============================================================
#  SHOP INTEGRITY  (round AI, GUT)
#
#  Sturmball has no shared unit pool and no unit levels. Its shops are:
#    the Traveling Brewer's cart  (data/Shop.csv)   - limited stock
#    Belial's ore shop            (data/OreShop.csv) - in a match, for Ore
#    the recruitment board        (test_recruit_board.gd)
#  These check that buying takes the thing off the shelf and the price out
#  of the purse - and never more than once.
# =============================================================

var db: CardDatabase


func before_each() -> void:
	db = CardDatabase.get_db()
	ShopBook.forget()


## A limited-stock row, and a pretend save that is allowed to buy it (its
## Requires - "unlocked:Traveling Brewer" - is unlocked first).
func _limited_row() -> Dictionary:
	for entry in ShopBook.shelf():
		if int(entry["stock"]) > 0 and not ShopBook.currency(String(entry["currency"])).is_empty() \
				and String(entry["requires"]).begins_with("unlocked:"):
			return entry
	return {}


func _save_for(entry: Dictionary) -> GameState:
	var state := GameState.new()
	state.unlock(String(entry["requires"]).substr(9).strip_edges())
	return state


func test_buying_from_the_cart_takes_one_off_the_stock() -> void:
	var entry := _limited_row()
	if entry.is_empty():
		pending("no limited-stock row on the cart that a new save can buy")
		return
	var state := _save_for(entry)
	var money := ShopBook.currency(String(entry["currency"]))
	state.set_count(String(money["counter"]), 100000)
	var before := ShopBook.left_on_the_cart(entry, state)
	var r := ShopBook.buy(String(entry["id"]), state)
	assert_true(bool(r["ok"]), String(r["why"]))
	assert_eq(ShopBook.left_on_the_cart(entry, state), before - 1)


func test_a_sold_out_row_cannot_be_bought_and_costs_nothing() -> void:
	var entry := _limited_row()
	if entry.is_empty():
		pending("no limited-stock row")
		return
	var state := _save_for(entry)
	var money := ShopBook.currency(String(entry["currency"]))
	state.set_count(String(money["counter"]), 100000)
	for i in int(entry["stock"]):
		ShopBook.buy(String(entry["id"]), state)
	var purse := state.count(String(money["counter"]))
	var r := ShopBook.buy(String(entry["id"]), state)
	assert_false(bool(r["ok"]))
	assert_eq(ShopBook.left_on_the_cart(entry, state), 0)
	assert_eq(state.count(String(money["counter"])), purse, "a refused sale must not take money")


func test_not_enough_money_is_refused_without_going_negative() -> void:
	var entry := _limited_row()
	if entry.is_empty():
		pending("no limited-stock row")
		return
	var state := _save_for(entry)
	var r := ShopBook.buy(String(entry["id"]), state)
	if int(entry["price"]) > 0:
		assert_false(bool(r["ok"]))
	var money := ShopBook.currency(String(entry["currency"]))
	assert_true(state.count(String(money["counter"])) >= 0)


func test_the_ore_shop_takes_the_ore_and_never_goes_below_zero() -> void:
	var e := AbilityEngine.new(db)
	e.begin_match()
	var miner := PlayerData.new()
	miner.player_name = "Testminer"
	miner.tier = "II"
	miner.unit_type = "Bergmännlein"
	miner.element = "Earth"
	miner.base_power_left = 2
	miner.base_power_right = 2
	miner.player_type = "Normal"
	e.sync_field([miner], [])
	e.set_ultimates(false, ["Belial"])
	assert_eq(e.shop_items(miner, false).size(), 0, "no Ore, nothing for sale")
	e.add_to_pool(false, "ore", 3)
	var items := e.shop_items(miner, false)
	if items.is_empty():
		pending("OreShop.csv has nothing at 3 Ore or less")
		return
	var item: Dictionary = items[0]
	e.shop_buy(miner, false, item)
	assert_eq(e.pool(false, "ore"), 3 - int(item["cost"]))
	for i in 5:
		e.shop_buy(miner, false, item)
	assert_true(e.pool(false, "ore") >= 0, "Ore must never go below zero")
