class_name ClubhouseScreen
extends SceneRoom

# =============================================================
#  THE CLUB HOUSE — the Vereinsheim bar  (round AN, Anthony 10 Oct: look A)
#
#      the KEY RACK behind the bar    one key per Upgrades.csv Kind = key.
#                                     A key you own is off its hook; a key
#                                     you may not buy yet is grey with a
#                                     padlock. Click a lit one to buy it.
#      the AWARD PLAQUES on the wall  one per upgrade (Kind = upgrade), each
#                                     with its own painting. Price card
#                                     under the ones on sale.
#      the WANTED POSTERS             the recruitment board (RecruitBoard.csv):
#                                     name, tier and power on the poster,
#                                     a Sign card under it.
#      the BELL on the bar            new faces on the board now (reroll)
#      the STAMMTISCH sign            your recruits - a list to release them
#
#  Every place and picture: data/ClubhouseLayout.csv. The rules are
#  base_rooms.gd (keys, upgrades) and recruit_board.gd. The Head Coach
#  explains it the first time (Guide.csv clubhouse_explain).
# =============================================================

const LAYOUT_FILE := "res://data/ClubhouseLayout.csv"


func _layout_file() -> String:
	return LAYOUT_FILE


func _guide_screen() -> String:
	return "clubhouse"


func _status_words() -> String:
	var keys := 0
	var wares := 0
	for entry in BaseRooms.upgrades():
		if BaseRooms.upgrade_state(entry, state) == "for_sale":
			if String(entry["kind"]) == "key":
				keys += 1
			else:
				wares += 1
	return "KEYS %d for sale    UPGRADES %d for sale    %d coins" % [keys, wares, ShopBook.purse("coins", state)]


func _fill() -> void:
	_fill_keys()
	_fill_upgrades()
	_fill_recruits()


# ---- THE KEY RACK --------------------------------------------

func _fill_keys() -> void:
	var art := part_art("key")
	var n := 0
	for entry in BaseRooms.upgrades():
		if String(entry["kind"]) != "key":
			continue
		n += 1
		var kind := BaseRooms.upgrade_state(entry, state)
		# A KEY YOU OWN IS OFF ITS HOOK - it is on your keyring.
		if kind == "bought":
			continue
		var name_text := String(entry["name"])
		var id_text := String(entry["id"])
		if kind == "locked":
			thing("key_%d" % n, art, "dim", [name_text, "LOCKED", BaseRooms.upgrade_lock_words(entry, state)],
				func() -> void: tell("%s is locked. %s" % [name_text, BaseRooms.upgrade_lock_words(entry, state)], false), true)
			continue
		var price := price_words(int(entry["cost"]), String(entry["currency"]))
		thing("key_%d" % n, art, "open", [name_text + "    " + price, String(entry["description"])],
			_buy.bind(id_text))


# ---- THE AWARD PLAQUES ---------------------------------------

func _fill_upgrades() -> void:
	var n := 0
	for entry in BaseRooms.upgrades():
		if String(entry["kind"]) == "key":
			continue
		n += 1
		var id_text := String(entry["id"])
		# Its own row (upgrade:<id>) with its own painting, else the n-th
		# free place with the plain plaque.
		var row := "upgrade:" + id_text.to_lower()
		var art: Texture2D = null
		if not has_part(row):
			row = "upgrade_%d" % n
			art = part_art("upgrade_blank")
		var kind := BaseRooms.upgrade_state(entry, state)
		var name_text := String(entry["name"])
		var said := String(entry["description"])
		var plaque: MapBuilding = null
		match kind:
			"bought":
				plaque = thing(row, art, "done", [name_text, "Yours.", said],
					func() -> void: tell("%s is yours." % name_text, true))
			"locked":
				var why := BaseRooms.upgrade_lock_words(entry, state)
				plaque = thing(row, art, "dim", [name_text, "LOCKED", why],
					func() -> void: tell("%s is locked. %s" % [name_text, why], false), true)
			_:
				var price := int(entry["cost"])
				var cur := String(entry["currency"])
				plaque = thing(row, art, "open", [name_text + "    " + price_words(price, cur), said], _buy.bind(id_text))
				if plaque != null:
					card(short_price(price, cur), plaque, can_pay(price, cur), _buy.bind(id_text))
		# A pinned note instead of a painting: its name is written on it.
		if plaque != null and art != null:
			write_on(plaque, name_text, 0.5, 14)


func _buy(id_text: String) -> void:
	say(BaseRooms.buy_upgrade(id_text, state))


# ---- THE RECRUITMENT BOARD -----------------------------------

func _fill_recruits() -> void:
	if not RecruitBoard.on(db):
		return
	var free := RecruitBoard.beds_free(state, db)
	var list := RecruitBoard.offers(state, db)
	var art := part_art("poster")
	for i in list.size():
		var entry: Dictionary = list[i]
		var row: Dictionary = entry["row"]
		var spot := "poster_%d" % (i + 1)
		match String(entry["state"]):
			"open":
				var price := int(row["cost"])
				var cur := String(row["currency"])
				var ok := can_pay(price, cur) and free > 0
				var why := "" if ok else ("No free bed - buy one at the Dorms." if free <= 0 else "Not enough money.")
				var poster := thing(spot, art, "open", [String(entry["name"]),
					"Tier %s    P:%d" % [entry["tier"], int(entry["power"])],
					"A plain player - the Pub can brew him into a class."],
					_sign.bind(i, ok, why))
				if poster != null:
					write_on(poster, String(entry["name"]), 0.42, 14)
					write_on(poster, "%s  P:%d" % [entry["tier"], int(entry["power"])], 0.6, 13, INK_SOFT)
					card("Sign  " + short_price(price, cur), poster, ok, _sign.bind(i, ok, why))
			"signed":
				var done := thing(spot, art, "done", ["Signed", "Somebody new after the next match."],
					func() -> void: tell("Signed already - new faces after the next match.", true))
				if done != null:
					write_on(done, "SIGNED", 0.5, 20, Color(0.7, 0.12, 0.1))
			_:
				var why := DialogueGrammar.describe(String(row["requires"]))
				thing(spot, art, "dim", ["Tier %s" % entry["tier"], "LOCKED", why],
					func() -> void: tell("That place is locked. %s" % why, false), true)

	var reroll := db.tune_int("recruit_board_reroll_cost", 10)
	if reroll > 0:
		var coins := ShopBook.purse("coins", state)
		thing("bell", null, "open" if coins >= reroll else "dim",
			["Ring for new faces", "%d coins - the board fills again now" % reroll],
			func() -> void:
				if coins >= reroll:
					say(RecruitBoard.reroll(state, db))
				else:
					tell("New faces cost %d coins." % reroll, false))

	var mine := RecruitBook.names(state)
	thing("stammtisch", null, "open", ["Your recruits", "%d at the Stammtisch" % mine.size(),
		"%d free bed(s) for more" % maxi(free, 0)], _show_recruits)


func _sign(index: int, ok: bool, why: String) -> void:
	if not ok:
		tell(why, false)
		return
	say(RecruitBoard.sign(index, state, db))


func _show_recruits() -> void:
	var entries: Array = []
	for who in RecruitBook.names(state):
		var turned := state.text(TransformBook.BECAME_PREFIX + CardDatabase._normalise(who))
		entries.append({
			"words": who,
			"sub": ("Brewed at the Pub - plays as %s's double now" % turned) if turned != ""
				else "A plain player - the Pub can brew him into a class",
			"buttons": [{"label": "Release", "ok": true, "do": _release.bind(who)}],
		})
	show_sheet("YOUR RECRUITS", entries)


func _release(who: String) -> void:
	say(RecruitBoard.release(who, state))
