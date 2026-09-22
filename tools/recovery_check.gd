extends SceneTree

# =============================================================
#  DO PLAYERS GET TIRED, AND DO THEY GET FIT AGAIN?
#
#  Fatigue is the slowest thing in the game to test by playing it: you would
#  have to finish a match, look at the shelf, play a bounty, look again, and
#  do that four times to see a power-5 player come back. So this does the
#  same thing in a second, with no match and no window.
#
#  It prints, for every power in Recovery.csv:
#
#      how long that power is out
#      the fixture it becomes available again
#      and whether a full squad can be fielded in between
#
#  If the last column says NO for several fixtures in a row, your squad is
#  too thin for the recovery numbers you have written — either lower the
#  Turns in Recovery.csv or sign more players.
#
#      godot --headless --script res://tools/recovery_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame
	var db := CardDatabase.get_db()
	var state := GameState.new()

	print("[rest] recovery is %s (the `recovery` row of Tuning.csv)"
		% ("ON" if db.tune_bool("recovery", true) else "OFF"))
	print("")

	# ---- the table itself ----
	var book := RecoveryBook.table()
	if book.is_empty():
		print("[rest] no Recovery.csv — using recovery_turns_per_power = %.2f"
			% db.tune_float("recovery_turns_per_power", 0.8))
	for power in range(0, 6):
		var stand_in := PlayerData.new()
		stand_in.player_name = "power %d" % power
		stand_in.base_power_left = power
		stand_in.base_power_right = power
		print("[rest] power %d -> %d fixture(s) out" % [
			power, RecoveryBook.turns_for(stand_in, db)])
	print("")

	# ---- a real class, played over and over ----
	var klass := ""
	for card in db.players:
		if card.unit_type.strip_edges() != "":
			klass = card.unit_type
			break
	if klass == "":
		print("[rest] no cards to test with")
		quit(1)
		return

	var squad: Array = []
	for card in db.players:
		if CardDatabase._normalise(card.unit_type) == CardDatabase._normalise(klass):
			squad.append(card)
	print("[rest] playing %s (%d cards) six fixtures in a row" % [klass, squad.size()])
	print("")

	for fixture in range(1, 7):
		# The eleven who play are the first fit ones we find, tier by tier —
		# roughly what the team builder would give you.
		var named: Array = []
		var fit := RecoveryBook.fit_by_tier(db, state, klass)
		for tier in PlayerData.TIER_ORDER:
			var ready_cards: Array = fit[tier]
			for i in mini(3, ready_cards.size()):
				named.append(ready_cards[i])

		var report := RecoveryBook.can_field(db, state, klass, 3)
		print("[rest] fixture %d: %2d fit, %2d named   full squad? %s%s" % [
			fixture, _fit_count(fit), named.size(),
			"yes" if bool(report["ok"]) else "NO",
			"" if bool(report["ok"]) else "  (%s)" % report["words"]])

		RecoveryBook.advance_turn(state, db)
		RecoveryBook.played(named, state, db)

	# ---- AND THE VERDICT, which is the line to read ----
	#
	# A side is `per_tier` players in each of four tiers. To play every week
	# with anybody resting you need more than that in the squad — roughly
	# twice, because the middle powers are out for two fixtures.
	print("")
	var thinnest := 99
	var thin_tier := ""
	var counted := {}
	for card in squad:
		var tier: String = card.get_tier_clean()
		counted[tier] = int(counted.get(tier, 0)) + 1
	for tier in PlayerData.TIER_ORDER:
		var many := int(counted.get(tier, 0))
		if many < thinnest:
			thinnest = many
			thin_tier = tier
	print("[rest] %s has %d player(s) in its thinnest tier (Tier %s). A side needs 3."
		% [klass, thinnest, thin_tier])
	if thinnest >= 6:
		print("[rest] VERDICT: big enough. Set `recovery` to true in Tuning.csv.")
	else:
		print("[rest] VERDICT: TOO THIN — leave `recovery` FALSE for now.")
		print("[rest]   With %d in a tier, one fixture puts enough of them out that you"
			% thinnest)
		print("[rest]   can field neither a match (3 a tier) nor an Adventure run (1 a tier),")
		print("[rest]   and there is then no way to pass a fixture and get them back.")
		print("[rest]   Six a tier is the number to aim at. Until then the system is built,")
		print("[rest]   tested and waiting — it is one row away.")
	quit(0)


func _fit_count(fit: Dictionary) -> int:
	var n := 0
	for tier in fit:
		n += (fit[tier] as Array).size()
	return n
