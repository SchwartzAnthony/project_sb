extends SceneTree

# =============================================================
#  THE NINE DOORS, AND THE THREE ROOMS THAT HAVE SPREADSHEETS
#
#  The base is nine buildings now and every one of them opens a window over
#  it rather than cutting to a new scene. Two things can go wrong with that
#  and neither is visible in a spreadsheet:
#
#      a building whose Action names a screen that does not exist
#      a room whose contents can never be reached or never be paid for
#
#      godot --headless --script res://tools/rooms_check.gd
#
#  WHAT IT DOES
#
#      1. every building, its door, and whether that door goes anywhere
#      2. the Dorms, the Trophies and the Training priced IN WINS, the same
#         way tools/shop_check.gd prices the cart — because "200 coins"
#         means nothing beside a season that pays 225
#      3. anything BaseRooms can see wrong in the three spreadsheets
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const SEASON := 10


func _initialize() -> void:
	var problems := 0
	var state := GameState.new()

	print("")
	print("=== The base ===")
	for problem in BaseRooms.problems():
		print("  ! %s" % problem)
		problems += 1

	var base := BaseDB.get_db()
	print("")
	print("  %-22s %-26s %s" % ["building", "opens", "how"])
	for entry in base.buildings:
		var action := String(entry["action"]).strip_edges()
		var how := "nothing — it only talks"
		var opens := ""
		if action.begins_with("window:"):
			how = "a window over the base"
			opens = action.substr(7).strip_edges()
		elif action.begins_with("goto:"):
			how = "A WHOLE NEW SCENE"
			opens = action.substr(5).strip_edges()
		else:
			how = action if action != "" else how

		if opens != "":
			var path := ScenePaths.for_name(opens)
			if not ResourceLoader.exists(path):
				print("  %-22s ! '%s' is not a screen — the door leads nowhere."
					% [entry["name"], opens])
				problems += 1
				continue
			if path == ScenePaths.MAIN_MENU and opens.to_lower() != "menu":
				print("  %-22s ! '%s' is not a word ScenePaths knows, so it falls back to the main menu."
					% [entry["name"], opens])
				problems += 1
				continue
		print("  %-22s %-26s %s" % [entry["name"], opens, how])

	# ============ WHAT A SEASON PAYS, AND WHAT THE ROOMS COST ============
	for fixture in SEASON:
		ShopBook.pay_out(MatchMode.DEFAULT_ID, "win" if fixture % 2 == 0 else "loss", state)
	var purse := state.count("coins")
	print("")
	print("  A season of %d fixtures, half won, pays %d coins." % [SEASON, purse])

	print("")
	print("  === THE DORMS ===")
	for dorm in BaseRooms.dorms():
		print("  %-18s %2d beds included   %-12s %s" % [dorm["name"], int(dorm["beds"]),
			"free" if int(dorm["price"]) == 0 else "%d %s" % [int(dorm["price"]), dorm["currency"]],
			_in_seasons(int(dorm["price"]), String(dorm["currency"]), purse)])

	print("")
	print("  === THE TRAINING GROUND ===")
	for entry in BaseRooms.training():
		print("  %-22s %-10s %-12s %s" % [entry["name"], entry["kind"],
			"%d %s" % [int(entry["cost"]), entry["currency"]],
			_in_seasons(int(entry["cost"]), String(entry["currency"]), purse)])

	# EVERY MINI-GAME SHOULD NAME A REAL SECTION, or it buys a vat in a
	# building that does not exist.
	for entry in BaseRooms.training():
		if String(entry["kind"]) != "minigame":
			continue
		var section := String(entry["section"])
		if section == "" or BreweryBook.section(section).is_empty():
			print("  ! '%s' is a mini-game for section '%s', which is not a row of BrewerySections.csv."
				% [entry["name"], section])
			problems += 1

	print("")
	print("  === THE TROPHY ROOM ===")
	for cup in BaseRooms.trophies():
		print("  %-26s %s" % [cup["name"],
			DialogueGrammar.describe(String(cup["won_when"]))])

	print("")
	if problems == 0:
		print("=== ALL GOOD ===")
	else:
		print("=== %d PROBLEM(S) ===" % problems)
	quit(0)


## "1.3 seasons" — the only unit a price is readable in.
func _in_seasons(price: int, currency_id: String, purse: int) -> String:
	if price <= 0:
		return ""
	var money := ShopBook.currency(currency_id)
	if money.is_empty():
		return "! '%s' is not a currency" % currency_id
	if String(money["counter"]) != "coins" or purse <= 0:
		return ""
	return "%.1f seasons" % (float(price) / float(purse))
