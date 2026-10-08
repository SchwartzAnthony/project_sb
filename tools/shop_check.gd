extends SceneTree

# =============================================================
#  THE TRAVELING BREWER, PRICED AGAINST A SEASON
#
#  "45 coins for a sack of hops" is a number that means nothing on its own.
#  It means something beside this one: A SEASON MATCH PAYS 40 FOR A WIN. So
#  that sack is a win and a bit, and the whole cart is about eleven wins.
#
#  That multiplication is the only thing worth checking about a shop, and it
#  is the thing a spreadsheet cannot show you.
#
#      godot --headless --script res://tools/shop_check.gd
#
#  WHAT IT DOES
#
#      1. every problem ShopBook can see in the two spreadsheets
#      2. the currencies, and WHICH MODE pays each one
#      3. the cart, with every price converted into WINS
#      4. A SEASON — ten fixtures of the real pay-out rows, half of them
#         won, and what the purse holds at the end of it
#      5. who opens each row, the same question the Brewery map asks
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const SEASON := 10


func _initialize() -> void:
	var problems := 0

	print("")
	print("=== The Traveling Brewer ===")
	for problem in ShopBook.problems():
		print("  ! %s" % problem)
		problems += 1

	var monies := ShopBook.currencies()
	if monies.is_empty():
		print("  No Currencies.csv — nothing can be bought at all.")
		quit(0)
		return

	# ============ 1. THE MONEY ============
	print("")
	print("  %-14s %-10s %-8s %-8s %-8s %s" % [
		"currency", "counter", "win", "draw", "loss", "paid in"])
	for money in monies:
		print("  %-14s %-10s %-8d %-8d %-8d %s" % [
			money["name"], money["counter"], int(money["win"]),
			int(money["draw"]), int(money["loss"]),
			"EVERY mode" if String(money["mode"]) == "" else String(money["mode"])])

	# A currency nothing pays is a currency nothing can be bought with.
	for money in monies:
		if int(money["win"]) == 0 and int(money["draw"]) == 0 and int(money["loss"]) == 0:
			# ROUND AN: an Items.csv item (Reed, Bog Iron) is carried home
			# from an Adventure - that is what hands it out.
			if not AdventureDB.get_db().item(String(money["counter"])).is_empty():
				print("  . '%s' is not paid by a match - it is carried home from an Adventure (Items.csv)." % money["name"])
				continue
			print("  ! '%s' is never paid by a match. Anything priced in it is unbuyable unless something else hands it out."
				% money["name"])
			problems += 1

	# ============ 2. THE CART, IN WINS ============
	print("")
	print("  === THE CART ===")
	print("  %-22s %-24s %-10s %-8s %s" % [
		"row", "gives", "price", "stock", "that is"])
	var whole_cart: Dictionary = {}
	for entry in ShopBook.shelf():
		var money := ShopBook.currency(String(entry["currency"]))
		var per_win := int(money["win"]) if not money.is_empty() else 0
		var price := int(entry["price"])
		var wins := "—" if per_win <= 0 else "%.1f wins" % (float(price) / float(per_win))
		var stock := int(entry["stock"])
		print("  %-22s %-24s %-10s %-8s %s" % [
			entry["id"], _gives(entry),
			"%d %s" % [price, entry["currency"]],
			"∞" if stock < 0 else str(stock), wins])
		if stock > 0:
			var key := String(entry["currency"])
			whole_cart[key] = int(whole_cart.get(key, 0)) + price * stock

	print("")
	for key in whole_cart:
		var money := ShopBook.currency(key)
		var per_win := int(money["win"]) if not money.is_empty() else 0
		print("  EVERYTHING HE HAS, in %s: %d%s" % [key, int(whole_cart[key]),
			"" if per_win <= 0 else "  (%.0f wins)" % (float(whole_cart[key]) / float(per_win))])

	# ============ 3. A SEASON ============
	#
	# The real pay-out rows, ten fixtures, half of them won — because
	# assuming you win every match flatters every price in the file.
	print("")
	print("  === A SEASON: %d fixtures, half won, half lost ===" % SEASON)
	var state := GameState.new()
	for fixture in SEASON:
		var outcome := "win" if fixture % 2 == 0 else "loss"
		ShopBook.pay_out(MatchMode.DEFAULT_ID, outcome, state)
	for money in monies:
		print("  %-14s %d after a season of SEASON matches"
			% [money["name"], state.count(String(money["counter"]))])
	print("  (a Quick Match season pays the other purse instead — that is the point of the column)")

	# ============ 4. WHO OPENS EACH ROW ============
	print("")
	print("  === WHO OPENS EACH ROW ===")
	for entry in ShopBook.shelf():
		var needs := String(entry["requires"])
		if needs == "":
			print("  %-22s on the cart from the first minute" % entry["id"])
			continue
		print("  %-22s %s" % [entry["id"], DialogueGrammar.describe(needs)])

	print("")
	if problems == 0:
		print("=== ALL GOOD ===")
	else:
		print("=== %d PROBLEM(S) ===" % problems)
	quit(0)


func _gives(entry: Dictionary) -> String:
	var sells := String(entry["sells"])
	var colon := sells.find(":")
	var kind := sells.substr(0, colon).strip_edges().to_lower() if colon > 0 else ""
	var rest := sells.substr(colon + 1).strip_edges() if colon > 0 else sells
	match kind:
		"res", "resource", "material":
			var res := BreweryBook.resource(rest)
			return "%d %s" % [int(entry["how_many"]),
				String(res["name"]) if not res.is_empty() else rest]
		"brew", "recipe":
			return "the %s recipe" % rest
		_:
			return sells
