extends SceneTree

# =============================================================
#  FREE KICKS, READ BACK TO YOU  (round AG, phase P2)
#
#      godot --headless --script res://tools/free_kick_check.gd
#
#  1. anything wrong with data/FreeKicks.csv
#  2. every row in plain words, in metres
#  3. which row a foul at 5 m, 10 m ... 100 m from goal would use
#  4. the caption words filled in, so a typo in {metres} shows up here
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================


func _initialize() -> void:
	var problems := 0
	var db := CardDatabase.get_db()
	print("")
	print("=== FreeKicks.csv ===")
	for problem in FreeKicks.problems():
		print("  ! %s" % problem)
		problems += 1
	var rows := FreeKicks.rows()
	if rows.is_empty():
		print("  No rows - every foul is the old flat foul_free_kick_power.")
		print("ALL GOOD" if problems == 0 else "%d PROBLEM(S)" % problems)
		quit(0)
		return
	if db != null and not db.tune_bool("free_kicks", true):
		print("  NOTE: free_kicks is 0 in Tuning.csv - this is what it WOULD do.")

	print("")
	var from := 0.0
	for row in rows:
		print("  %-8s %3d - %3d m from goal: +%d on the shot%s   \"%s\"" % [row["range"],
			int(round(from * FreeKicks.PITCH_METRES)), int(round(float(row["up_to"]) * FreeKicks.PITCH_METRES)),
			int(row["power"]), ", they TAKE THE BALL and shoot" if bool(row["takes_ball"]) else "",
			row["call"]])
		from = float(row["up_to"])

	print("")
	var line := "  by distance:"
	for m in range(5, 105, 10):
		var share := float(m) / FreeKicks.PITCH_METRES
		line += "  %dm=%s" % [m, FreeKicks.pick(share)["range"]]
	print(line)

	print("")
	for row in rows:
		var said := FreeKicks.caption(row, float(row["up_to"]) * 0.8, "Oskar")
		if said.contains("{") or said.contains("}"):
			print("  ! %s: the Caption has a word the game does not know: %s" % [row["range"], said])
			problems += 1
		else:
			print("  %s: %s — %s" % [row["range"], row["call"], said])

	# The first row should be the strongest and give the ball; a far kick
	# worth more than a close one is almost certainly a typo.
	for i in range(1, rows.size()):
		if int(rows[i]["power"]) > int(rows[i - 1]["power"]):
			print("  ? %s (further out) is worth more than %s - on purpose?" % [rows[i]["range"], rows[i - 1]["range"]])
	print("")
	print("ALL GOOD" if problems == 0 else "%d PROBLEM(S)" % problems)
	quit(0)
