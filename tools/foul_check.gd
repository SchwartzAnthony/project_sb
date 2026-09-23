extends SceneTree

# =============================================================
#  THE FOUL CURVE, READ BACK TO YOU — AND WHAT IT COSTS A MATCH
#
#  A foul chance is a number that is impossible to feel from a spreadsheet.
#  "18% at four triggers" sounds small. It happens TO BOTH SIDES, NINE TIMES
#  A MATCH, which is eighteen rolls — and eighteen rolls at 18% is three
#  fouls a match, one of which is a card. That multiplication is the whole
#  reason this tool exists, and it is the same lesson the out-of-bounds
#  checker teaches about seconds.
#
#      godot --headless --script res://tools/foul_check.gd
#
#  WHAT IT TELLS YOU
#
#      1. anything wrong with data/Fouls.csv
#      2. the curve, in plain words, at every trigger count
#      3. A WHOLE SEASON SIMULATED — fouls, yellows and reds per match, at
#         several different levels of how hard the sides are playing
#
#  HOW MANY TRIGGERS IS NORMAL? Play a match and look for the line
#  "Triggers this round: you N, them N" in the Output panel. That is the real
#  number for your squads, and the row of this table nearest it is the row
#  that is actually happening in your game.
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const MATCHES := 2000
const ROUNDS_PER_MATCH := 9

## The trigger levels the season table is run at. Nothing magic — they are
## "a quiet side", "an ordinary side" and "a side firing everything".
const LEVELS: Array[int] = [0, 1, 2, 3, 4, 6, 9]


func _initialize() -> void:
	var problems := 0
	var db := CardDatabase.get_db()

	print("")
	print("=== Fouls.csv ===")
	for problem in FoulBook.problems():
		print("  ! %s" % problem)
		problems += 1

	var rows := FoulBook.rows()
	if rows.is_empty():
		print("  No rows. Nobody in this game will ever give a foul away.")
		quit(0)
		return

	if db != null and not db.tune_bool("fouls", true):
		print("  NOTE: `fouls` is false in Tuning.csv, so none of this is")
		print("  happening in the game right now. The table below is what it")
		print("  WOULD do if you turned it back on.")

	# ============ 1. THE CURVE ============
	print("")
	print("  %-9s %-13s %-9s %-9s %s" % [
		"triggers", "a foul?", "yellow", "red", "or just a free kick"])
	for many in LEVELS:
		var odds := FoulBook.odds_at(many)
		var chance := float(odds["chance"])
		var yellow := float(odds["yellow"])
		var red := float(odds["red"])
		print("  %-9d %-13s %-9s %-9s %.0f%%" % [
			many, "%.0f%%" % chance, "%.0f%%" % yellow, "%.0f%%" % red,
			maxf(0.0, 100.0 - yellow - red)])

	# ============ 2. WHAT IT COSTS A MATCH ============
	#
	# Both sides roll every round, so a match is eighteen rolls, not nine.
	# Printed per SIDE, because "1.4 cards a match" means something different
	# depending on whether that is your side or both of them together.
	print("")
	print("  === PER SIDE, PER MATCH (%d rounds, %d matches simulated) ===" % [
		ROUNDS_PER_MATCH, MATCHES])
	print("")
	print("  %-9s %-9s %-9s %-9s %s" % [
		"triggers", "fouls", "yellows", "reds", "matches ending 10 v 11"])

	var two_yellows_is_red := true
	if db != null:
		two_yellows_is_red = db.tune_bool("foul_two_yellows_is_red", true)

	for many in LEVELS:
		var fouls := 0
		var yellows := 0
		var reds := 0
		var matches_a_man_down := 0

		for _match in MATCHES:
			# A BOOKING IS REMEMBERED. Two of them are a red, so a match has
			# to be simulated as a match rather than as eighteen loose rolls —
			# otherwise the second-yellow reds never appear and the table
			# under-reports sendings-off by about a third.
			var booked: Dictionary = {}
			var sent_off := 0
			for _round in ROUNDS_PER_MATCH:
				var verdict := FoulBook.roll(many)
				if verdict == "":
					continue
				fouls += 1
				# Which of the four who played gave it away.
				var who := randi() % 4
				if verdict == "yellow":
					yellows += 1
					booked[who] = int(booked.get(who, 0)) + 1
					if two_yellows_is_red and int(booked[who]) >= 2:
						reds += 1
						sent_off += 1
				elif verdict == "red":
					reds += 1
					sent_off += 1
			if sent_off > 0:
				matches_a_man_down += 1

		print("  %-9d %-9.2f %-9.2f %-9.2f %.0f%%" % [
			many,
			float(fouls) / float(MATCHES),
			float(yellows) / float(MATCHES),
			float(reds) / float(MATCHES),
			100.0 * float(matches_a_man_down) / float(MATCHES)])

	# ============ 3. THE LADDER STILL HOLDS ============
	#
	# The thing a red card threatens. A tier holds one card of each power; a
	# sending-off takes one away, and the stand-in is what puts it back. If
	# `foul_stand_ins` is off, say so plainly rather than leaving it as a
	# surprise in the middle of a match.
	print("")
	print("  === THE LADDER ===")
	if db != null and not db.tune_bool("foul_stand_ins", true):
		print("  `foul_stand_ins` is FALSE. A sending-off leaves that tier one")
		print("  card short for the rest of the match. That is harsher and")
		print("  perfectly playable — just know that it is what you chose.")
	else:
		for tier in TierLadder.TIERS:
			var rungs := TierLadder.rungs(tier, db)
			var words: Array[String] = []
			for rung in rungs:
				words.append("P:%d" % rung)
			print("  Tier %-4s %s — lose any one of them and a survivor covers"
				% [tier, ", ".join(words)])
		print("  the empty rung: his name, the missing power, no abilities.")

	print("")
	if problems == 0:
		print("=== ALL GOOD ===")
	else:
		print("=== %d PROBLEM(S) ===" % problems)
	quit(0)
