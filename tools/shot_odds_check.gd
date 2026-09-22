extends SceneTree

# =============================================================
#  THE SCORING CURVE, PRINTED
#
#  `data/ShotOdds.csv` is six rows that describe a curve, and six rows is
#  not something you can look at and know what it feels like. So this prints
#  THE WHOLE GRID — every stamina band against every shot power — and then
#  plays ten thousand shots at each to check that the dice agree with the
#  table.
#
#      godot --headless --script res://tools/shot_odds_check.gd
#
#  The three things it is really checking:
#
#    * AN EMPTY KEEPER IS 100%. Not 90, not 99. The row exists, it says 100,
#      and ten thousand shots all go in.
#    * IT GETS EASIER ALL THE WAY DOWN. Every step of lost stamina raises the
#      chance. A curve that dips in the middle is a keeper who gets HARDER as
#      you hurt him, which no player will ever guess.
#    * THE DICE MATCH THE TABLE. The number printed on the screen before the
#      shot has to be the number that is rolled — see take_shot().
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const KEEPER_MAX := 25
const SHOTS := 10000


func _initialize() -> void:
	seed(20260923)
	var db := CardDatabase.get_db()

	print("")
	print("=== ShotOdds.csv ===")
	for problem in ShotOdds.problems():
		print("  ! %s" % problem)

	print("")
	print("  the curve you wrote:")
	print("  %-14s %8s %10s" % ["stamina left", "chance", "per power"])
	for row in ShotOdds.rows():
		print("  %11d%%  %7d%% %9.1f" % [int(row["left"]), int(row["chance"]), row["per_power"]])

	# ---- the grid ----
	var powers: Array[int] = [0, 1, 2, 3, 4, 5, 8]
	print("")
	print("  WHAT THAT ACTUALLY MEANS, on a keeper with %d stamina:" % KEEPER_MAX)
	var header := "  %-10s" % "stamina"
	for power in powers:
		header += "%8s" % ("P%d" % power)
	print(header)

	var bands: Array[int] = [25, 20, 15, 12, 10, 6, 3, 1, 0]
	for stamina in bands:
		var line := "  %5d/%-4d" % [stamina, KEEPER_MAX]
		for power in powers:
			line += "%7d%%" % int(round(ShotOdds.chance(stamina, KEEPER_MAX, power)))
		print(line)

	print("")
	print("  and what the keeper says on the pitch (shot_power_shown = %d):"
		% int(db.tune_float("shot_power_shown", 5.0)))
	for stamina in bands:
		print("  %5d/%-4d   %s" % [stamina, KEEPER_MAX,
			ShotOdds.band_text(stamina, KEEPER_MAX, int(db.tune_float("shot_power_shown", 5.0)))])

	# ---- does it ever get harder as he tires? ----
	var problems := ShotOdds.problems().size()
	print("")
	print("  --- does it get easier all the way down? ---")
	var worse := 0
	var last := -1.0
	for stamina in range(KEEPER_MAX, -1, -1):
		var now := ShotOdds.chance(stamina, KEEPER_MAX, 3)
		if last >= 0.0 and now < last - 0.001:
			print("  ! %d stamina is %.0f%%, but %d was %.0f%% — it got HARDER as he tired."
				% [stamina, now, stamina + 1, last])
			worse += 1
			problems += 1
		last = now
	if worse == 0:
		print("  yes — every point of stamina lost raises the chance.")

	# ---- the dice against the table ----
	print("")
	print("  --- %d shots at each, against what the table promised ---" % SHOTS)
	print("  %-10s %8s %8s %8s" % ["stamina", "P3 says", "rolled", "gap"])
	for stamina in [KEEPER_MAX, 18, 12, 6, 2, 0]:
		var promised := ShotOdds.chance(stamina, KEEPER_MAX, 3)
		var scored := 0
		for i in SHOTS:
			if randf() < ShotOdds.odds(stamina, KEEPER_MAX, 3):
				scored += 1
		var rolled := 100.0 * float(scored) / float(SHOTS)
		var gap: float = absf(rolled - promised)
		print("  %5d/%-4d %7.1f%% %7.1f%% %7.1f" % [stamina, KEEPER_MAX, promised, rolled, gap])
		# Two points of slack on ten thousand rolls is ordinary noise; more
		# than that means the roll is not reading the same table as the label.
		if gap > 2.0:
			print("  ! the dice and the table disagree by more than two points.")
			problems += 1

	# ---- the one that matters most ----
	print("")
	var open_goal := ShotOdds.chance(0, KEEPER_MAX, 0)
	if open_goal < 99.99:
		print("  ! AN EMPTY KEEPER IS %.0f%%, NOT 100%%. The 0 row of ShotOdds.csv" % open_goal)
		print("  ! decides this. Set its Chance to 100 unless you meant otherwise.")
		problems += 1
	else:
		var all_in := true
		for i in 2000:
			if randf() >= ShotOdds.odds(0, KEEPER_MAX, 0):
				all_in = false
				break
		if all_in:
			print("  an empty keeper is 100 per cent, and 2000 shots all went in.")
		else:
			print("  ! the table says 100%% but a shot was saved. That should be impossible.")
			problems += 1

	print("")
	print("=== %s ===" % ("ALL GOOD" if problems == 0 else "%d thing(s) to look at" % problems))
	print("")
	quit(0)
