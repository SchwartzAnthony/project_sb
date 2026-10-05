extends SceneTree

# =============================================================
#  THE RECRUITMENT BOARD, TRIED OUT  (round AH, phase P3)
#
#      godot --headless --script res://tools/recruit_board_check.gd
#
#  Uses a pretend save in memory - your real save is never opened.
#  1. anything wrong with data/RecruitBoard.csv
#  2. the board as a new game sees it
#  3. signing: coins go, he joins under his name, his place says signed
#  4. no bed, no signing
#  5. after a match the board fills again with new men
#  6. releasing him frees his bed and his name
# =============================================================

var problems := 0


func _say(ok: bool, what: String, why: String = "") -> void:
	if ok:
		print("  ok %s" % what)
	else:
		problems += 1
		print("  !! %s  (%s)" % [what, why])


func _initialize() -> void:
	var db := CardDatabase.get_db()
	print("")
	print("=== RecruitBoard.csv ===")
	for p in RecruitBoard.problems():
		print("  ! %s" % p)
		problems += 1
	for row in RecruitBoard.rows():
		print("  slot %s: Tier %s, powers %s, %d %s%s" % [row["slot"], row["tier"], row["powers"],
			int(row["cost"]), row["currency"], "" if String(row["requires"]) == "" else "  (needs %s)" % row["requires"]])
	if not RecruitBoard.on(db):
		print("  NOTE: the board is switched off (recruit_board / named_recruits in Tuning.csv).")

	var state := GameState.new()
	state.set_count("coins", 1000)
	var board := RecruitBoard.offers(state, db)
	var open := 0
	for e in board:
		print("  on the board: %s  %s" % [e["state"], "" if String(e["name"]) == "" else "%s, Tier %s P:%d" % [e["name"], e["tier"], int(e["power"])]])
		if String(e["state"]) == "open":
			open += 1
	_say(open >= 1, "a new game has somebody on the board", "%d open" % open)

	var first := -1
	for i in board.size():
		if String(board[i]["state"]) == "open":
			first = i
			break
	if first >= 0:
		var name_text := String(board[first]["name"])
		var cost := int((board[first]["row"] as Dictionary)["cost"])
		var result := RecruitBoard.sign(first, state, db)
		_say(bool(result["ok"]), "signing %s works" % name_text, String(result["why"]))
		_say(RecruitBook.is_recruit(name_text, state), "%s is a recruit now, under his own name" % name_text)
		_say(state.count("coins") == 1000 - cost, "he cost %d coins" % cost, "coins %d" % state.count("coins"))
		_say(String(RecruitBoard.offers(state, db)[first]["state"]) == "signed", "his place on the board says signed")
		var again := RecruitBoard.sign(first, state, db)
		_say(not bool(again["ok"]), "the same place cannot be signed twice")

		# No bed.
		var keep := db.tune_int("recruit_beds_kept", 9)
		print("  beds: %d, kept for the team %d, recruits %d -> room for %d more" % [
			BaseRooms.beds(state), keep, RecruitBook.names(state).size(), RecruitBoard.beds_free(state, db)])
		var safety := 0
		while RecruitBoard.beds_free(state, db) > 0 and safety < 50:
			safety += 1
			state.add_count("matches_played", 1)
			var list := RecruitBoard.offers(state, db)
			for i in list.size():
				if String(list[i]["state"]) == "open" and RecruitBoard.beds_free(state, db) > 0:
					RecruitBoard.sign(i, state, db)
		state.add_count("matches_played", 1)
		var full := RecruitBoard.offers(state, db)
		var tried := {"ok": true}
		for i in full.size():
			if String(full[i]["state"]) == "open":
				tried = RecruitBoard.sign(i, state, db)
				break
		_say(not bool(tried["ok"]), "with every bed taken, nobody else can sign", String(tried.get("why", "")))

		# A match: new faces.
		var before := ""
		for e in RecruitBoard.offers(state, db):
			before += String(e["name"])
		state.add_count("matches_played", 1)
		var after := ""
		for e in RecruitBoard.offers(state, db):
			after += String(e["name"])
		_say(before != after, "after a match the board has new men on it")

		var held_before := NameBook.held(state).size()
		var r := RecruitBoard.release(name_text, state)
		_say(bool(r["ok"]) and not RecruitBook.is_recruit(name_text, state) and NameBook.held(state).size() == held_before - 1,
			"releasing %s frees his bed and his name" % name_text, String(r["why"]))

	print("")
	print("=== ALL GOOD ===" if problems == 0 else "=== %d PROBLEM(S) ===" % problems)
	quit(0)
