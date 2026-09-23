extends SceneTree

# =============================================================
#  A COMPETITION'S RULES, AND WHAT A RUN IS WORTH
#
#  Two Phase-10 spreadsheets, and both of them can be wrong in the same
#  invisible way: a rule that does nothing, and a pacing row that never
#  applies. Neither shows up in a spreadsheet and neither crashes anything.
#
#      godot --headless --script res://tools/season_check.gd
#
#  WHAT IT DOES
#
#      1. every competition's rules read back in a sentence
#      2. EVERY KEY IN A Tuning COLUMN CHECKED against Tuning.csv — a
#         misspelling there is a competition that looks like it bends the
#         game and does not
#      3. the pickup pacing per biome, and WHAT A WHOLE RUN IS WORTH, which
#         is the number a biome should be balanced against
#      4. which fixtures have a dialogue before them, and whether that scene
#         exists
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================


func _initialize() -> void:
	var problems := 0
	var db := CardDatabase.get_db()

	print("")
	print("=== Competitions ===")
	for problem in SeasonRules.problems():
		print("  ! %s" % problem)
		problems += 1

	for rules in SeasonRules.every():
		var who := String(rules["season"])
		var said := SeasonRules.words(who)
		print("  %-22s %s" % [who, said if said != "" else "the ordinary rules of football"])
		if String(rules["story"]) != "":
			print("  %-22s   before it: %s" % ["", rules["story"]])

	# ============ LENT, AND HANDED BACK ============
	#
	# The one thing that can go wrong with a borrowed rule and never be
	# traced: a Winter Cup that leaves the keeper tired for the rest of the
	# game. So every competition is applied and then released, and the
	# database is compared with what it was before.
	print("")
	print("  === LENT AND HANDED BACK ===")
	if db != null:
		var before: Dictionary = db.tuning.duplicate(true)
		for rules in SeasonRules.every():
			var who := String(rules["season"])
			if who == "*":
				continue
			SeasonRules.apply_to(who, db)
			SeasonRules.apply_to("", db)     # a friendly: hands everything back
			var drifted: Array[String] = []
			for key in before:
				if String(db.tuning.get(key, "")) != String(before[key]):
					drifted.append(String(key))
			if drifted.is_empty():
				print("  %-22s borrowed %d row(s) and handed them all back."
					% [who, rules["tuning"].size()])
			else:
				print("  %-22s ! LEFT %s CHANGED after the competition ended."
					% [who, ", ".join(PackedStringArray(drifted))])
				problems += 1

	# ============ THE PICKUP PACING ============
	print("")
	print("  === WHAT A RUN IS WORTH ===")
	for problem in RunPlan.problems():
		print("  ! %s" % problem)
		problems += 1

	var adventure := AdventureDB.get_db()
	print("  %-22s %-12s %-12s %s" % ["biome", "per wave", "boss", "a whole run"])
	if adventure != null:
		for biome in adventure.all_biomes():
			var id_text := String(biome["id"])
			var plan := RunPlan.for_biome(id_text)
			var waves := maxi(1, int(biome.get("waves", 1)))
			print("  %-22s %-12d %-12d %d pickup(s) over %d wave(s)" % [
				biome["name"], int(plan["before_wave"]), int(plan["before_boss"]),
				RunPlan.over_a_run(id_text, waves), waves])

	# ============ A DIALOGUE BEFORE A FIXTURE ============
	print("")
	print("  === DIALOGUE BEFORE A FIXTURE ===")
	var seasons_db := SeasonDB.get_db()
	var stories := DialogueDB.get_db() if DialogueDB.get_db() != null else null
	var found := 0
	if seasons_db != null:
		for fixture in seasons_db.fixtures:
			var scene := String(fixture.get("story", "")).strip_edges()
			if scene == "":
				continue
			found += 1
			# THE SAME KEY DialogueDB FILES A SCENE UNDER. Asking with the raw
			# spelling found `season_opening` missing while it was sitting
			# right there in the log — which is the kind of near-miss that
			# makes a tool look broken and then get ignored.
			var there := stories != null \
				and stories.scenes.has(CardDatabase._normalise(scene))
			if there:
				print("  %-10s match %-3d -> %s" % [fixture["season"],
					int(fixture["number"]), scene])
			else:
				print("  %-10s match %-3d ! '%s' is not a scene in Dialogue.csv."
					% [fixture["season"], int(fixture["number"]), scene])
				problems += 1
	if found == 0:
		print("  No fixture has a Story yet. Put a Dialogue.csv scene name in the")
		print("  Story column of Season.csv and it plays on the way to the team sheet.")

	print("")
	if problems == 0:
		print("=== ALL GOOD ===")
	else:
		print("=== %d PROBLEM(S) ===" % problems)
	quit(0)
