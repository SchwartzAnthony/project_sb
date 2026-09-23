class_name ShopBook
extends RefCounted

# =============================================================
#  THE TRAVELING BREWER — data/Shop.csv and data/Currencies.csv
#
#  ============ WHAT YOU ASKED FOR ============
#
#  "The Traveling Brewer sells brews at premium prices. The currency comes
#   from winning matches, and there are separate currencies per mode."
#
#  Three sentences, three files, and none of them needed a new idea:
#
#      Currencies.csv   what money there is, which MODE pays it, and how
#                       much a win, a draw and a loss are worth
#      Shop.csv         what he has, what it costs and in which money
#      GameState        holds the money in ordinary counters, so
#                       `count:coins>=200` already works everywhere
#
#  ============ WHY HE MATTERS MORE THAN A SHOP USUALLY DOES ============
#
#  tools/brewery_check.gd plays ten real fixtures and reports that the
#  Brewery runs out of HOPS — they only arrive when you win — and that wort
#  backs up nineteen deep behind the boiling copper waiting for them.
#
#  The Brewer is the answer to that, and he is priced to be an answer you do
#  not like: a sack of hops costs about a win and a half. He is there for the
#  week you need them, not instead of the Brewery.
#
#  ============ WHAT A ROW SELLS ============
#
#      res:hops     a Brewery material. `How Many` of them
#      brew:fire    a RECIPE — it unlocks that row of Brews.csv by name,
#                   exactly as a talent or an achievement would, and the Pub
#                   can pour it from then on
#
#  Anything else in `Sells` is handed to the ordinary effects language, so
#  `unlock:Something` and `flag:x` work there too and a shelf can sell a
#  thing this file has never heard of.
#
#  ============ STOCK ============
#
#  `Stock` is how many he has EVER, not per visit. Once the sack of hops is
#  bought three times it is gone from his cart for good — which is what makes
#  a shop a decision rather than a tap. Leave it blank for unlimited.
# =============================================================

const SHOP_FILE := "res://data/Shop.csv"
const CURRENCY_FILE := "res://data/Currencies.csv"

## How many of a row you have already bought. `bought_hops_sack`.
const BOUGHT_PREFIX := "bought_"

static var _shelf: Array[Dictionary] = []
static var _money: Array[Dictionary] = []
static var _problems: Array[String] = []
static var _loaded := false


static func forget() -> void:
	_shelf = []
	_money = []
	_problems = []
	_loaded = false


# =============================================================
#  READING THE TWO FILES
# =============================================================

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_shelf = []
	_money = []
	_problems = []

	var seen: Dictionary = {}
	for row in MenuSupport.read_csv(CURRENCY_FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		_money.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			# The counter it lives in. Defaults to the id, so a currency
			# called `coins` is the `coins` counter the game already had.
			"counter": MenuSupport.field(row, "Counter", id_text).strip_edges(),
			"mode": MenuSupport.field(row, "Earned In").strip_edges(),
			"win": MenuSupport.field_int(row, "Win", 0),
			"draw": MenuSupport.field_int(row, "Draw", 0),
			"loss": MenuSupport.field_int(row, "Loss", 0),
			"icon": MenuSupport.field(row, "Icon").strip_edges(),
		})
		seen[_squash(id_text)] = true

	for row in MenuSupport.read_csv(SHOP_FILE):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		var currency := MenuSupport.field(row, "Currency").strip_edges()
		_shelf.append({
			"id": id_text,
			"name": MenuSupport.field(row, "Name", id_text).strip_edges(),
			"sells": MenuSupport.field(row, "Sells").strip_edges(),
			"how_many": maxi(1, MenuSupport.field_int(row, "How Many", 1)),
			"price": maxi(0, MenuSupport.field_int(row, "Price", 0)),
			"currency": currency,
			# Blank stock is unlimited. -1 says so out loud rather than
			# leaving a 0 that reads as "sold out".
			"stock": MenuSupport.field_int(row, "Stock", -1),
			"requires": MenuSupport.field(row, "Requires").strip_edges(),
			"art": MenuSupport.field(row, "Art").strip_edges(),
		})
		if currency != "" and not seen.has(_squash(currency)):
			_problems.append("'%s' is priced in '%s', which is not a row of Currencies.csv — nobody can ever pay for it."
				% [id_text, currency])
		if int(_shelf[-1]["price"]) <= 0:
			_problems.append("'%s' costs nothing. A free shelf is not a shop." % id_text)
		if String(_shelf[-1]["sells"]) == "":
			_problems.append("'%s' sells nothing — its Sells column is empty." % id_text)

	if _shelf.is_empty():
		print("[shop] No Shop.csv — the Traveling Brewer has an empty cart.")
	else:
		print("[shop] %d row(s) on the cart, %d currency(ies)." % [_shelf.size(), _money.size()])
	for problem in _problems:
		print("[shop] %s" % problem)


static func problems() -> Array[String]:
	_load()
	return _problems


static func shelf() -> Array[Dictionary]:
	_load()
	return _shelf


static func currencies() -> Array[Dictionary]:
	_load()
	return _money


static func currency(id_text: String) -> Dictionary:
	for one in currencies():
		if _squash(String(one["id"])) == _squash(id_text):
			return one
	return {}


static func _squash(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


# =============================================================
#  MONEY
# =============================================================

static func purse(currency_id: String, state: GameState) -> int:
	var one := currency(currency_id)
	if one.is_empty() or state == null:
		return 0
	return state.count(String(one["counter"]))


## What a finished match pays, and into which purse.
##
## `mode_id` is the MatchModes.csv id — a currency whose `Earned In` names a
## different mode is not paid, which is the whole of "separate currencies per
## mode". A blank `Earned In` is paid in every mode.
##
## Returns what was paid: [{"name", "amount"}, ...], for the gains panel.
static func pay_out(mode_id: String, outcome: String, state: GameState) -> Array[Dictionary]:
	var paid: Array[Dictionary] = []
	if state == null:
		return paid
	for one in currencies():
		var wanted := String(one["mode"])
		if wanted != "" and _squash(wanted) != _squash(mode_id):
			continue
		var amount := int(one["win"])
		if outcome == "draw":
			amount = int(one["draw"])
		elif outcome == "loss":
			amount = int(one["loss"])
		if amount == 0:
			continue
		state.add_count(String(one["counter"]), amount)
		paid.append({"name": one["name"], "amount": amount})
	return paid


# =============================================================
#  BUYING
# =============================================================

static func sold(row_id: String, state: GameState) -> int:
	if state == null:
		return 0
	return state.count(BOUGHT_PREFIX + row_id.to_lower())


static func left_on_the_cart(entry: Dictionary, state: GameState) -> int:
	var stock := int(entry["stock"])
	if stock < 0:
		return -1        # unlimited
	return maxi(0, stock - sold(String(entry["id"]), state))


## What he will show you: everything whose Requires passes. A sold-out row
## stays on the list and says SOLD OUT, because a thing that vanishes is a
## thing you think you imagined.
static func on_offer(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in shelf():
		if DialogueGrammar.test(String(entry["requires"]), state):
			out.append(entry)
	return out


## Buy one. Returns {"ok": bool, "why": String}.
static func buy(row_id: String, state: GameState) -> Dictionary:
	if state == null:
		return {"ok": false, "why": "no save"}
	var entry: Dictionary = {}
	for one in shelf():
		if String(one["id"]) == row_id:
			entry = one
			break
	if entry.is_empty():
		return {"ok": false, "why": "he does not sell that"}
	if not DialogueGrammar.test(String(entry["requires"]), state):
		return {"ok": false, "why": "he will not sell you that yet"}

	var left := left_on_the_cart(entry, state)
	if left == 0:
		return {"ok": false, "why": "sold out"}

	var money := currency(String(entry["currency"]))
	if money.is_empty():
		return {"ok": false, "why": "'%s' is not a currency" % entry["currency"]}
	var price := int(entry["price"])
	var have := state.count(String(money["counter"]))
	if have < price:
		return {"ok": false, "why": "%d %s, and you have %d"
			% [price, money["name"], have]}

	state.add_count(String(money["counter"]), -price)
	state.add_count(BOUGHT_PREFIX + row_id.to_lower(), 1)
	return {"ok": true, "why": _hand_over(entry, state)}


## Give the thing. `res:<id>` is a Brewery material, `brew:<id>` unlocks a
## recipe by name, anything else goes to the ordinary effects language.
static func _hand_over(entry: Dictionary, state: GameState) -> String:
	var sells := String(entry["sells"])
	var many := int(entry["how_many"])
	var colon := sells.find(":")
	var kind := sells.substr(0, colon).strip_edges().to_lower() if colon > 0 else ""
	var rest := sells.substr(colon + 1).strip_edges() if colon > 0 else sells

	match kind:
		"res", "resource", "material":
			BreweryBook.add_stock(rest, many, state)
			var res := BreweryBook.resource(rest)
			var name_text := String(res["name"]) if not res.is_empty() else rest
			return "%d %s into the store." % [many, name_text]
		"brew", "recipe":
			# THE RECIPE IS UNLOCKED BY NAME, the way every brew is. The row
			# of Brews.csv asks for `unlocked:<its Name>` and neither half
			# knows about the other.
			var brews := BrewDB.get_db()
			var found := brews.find(rest) if brews != null else {}
			var label := String(found["name"]) if not found.is_empty() else rest
			state.unlock(label)
			return "The Pub can pour the %s from now on." % label
		_:
			Progression.run_actions(sells, state)
			return "Bought."
