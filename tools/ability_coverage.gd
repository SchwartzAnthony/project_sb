extends SceneTree

# =============================================================
#  THE METER — how many of your abilities actually DO something  (round Y)
#
#      godot --headless --script res://tools/ability_coverage.gd
#
#  For every card of every class, both sides (and each Star's Front Side):
#  is its Ability cell filled, does every row it names exist, and is every
#  word in those rows one the engine runs today?
#
#      WORKS        it will go off in a match, at its moment
#      WAITS        it is wired, but a word in it is still `planned`
#      PROSE ONLY   the card has text and no ability row yet
#      BROKEN       a cell names a row that does not exist
#
#  The number to watch is WORKS. Every phase of guides/COMBAT_PHASES.md
#  should push it up, and this is where you see that it did.
# =============================================================

const CLASSES: Array[String] = ["Lorelei", "Rauhnacht-Feuergeister", "Bergmännlein", "Unkengeister"]


func _initialize() -> void:
	var db := CardDatabase.get_db()
	print("")
	print("=== ABILITY COVERAGE ===")
	print("")
	print("  %-24s %6s %6s %11s %7s   %s" % ["class", "WORKS", "WAITS", "PROSE ONLY", "BROKEN", "of"])
	var total := {"works": 0, "waits": 0, "prose": 0, "broken": 0, "all": 0}
	var broken_lines: Array[String] = []
	var waiting_words: Dictionary = {}
	for unit_type in CLASSES:
		var tally := {"works": 0, "waits": 0, "prose": 0, "broken": 0, "all": 0}
		for card in db.players:
			if CardDatabase._normalise(card.unit_type) != CardDatabase._normalise(unit_type):
				continue
			var sides: Array = [["Attack", card.attack_ability_id, card.attack_text]]
			if not card.is_star():
				sides.append(["Defend", card.defend_ability_id, card.defend_text])
			for side in sides:
				if String(side[2]).strip_edges() == "" and String(side[1]).strip_edges() == "":
					continue
				tally["all"] += 1
				var verdict := _judge(String(side[1]), db, waiting_words)
				if verdict.begins_with("broken"):
					broken_lines.append("%s %s: %s" % [card.player_name, side[0], verdict])
					tally["broken"] += 1
				else:
					tally[verdict] += 1
		for key in tally.keys():
			total[key] += tally[key]
		print("  %-24s %6d %6d %11d %7d   %d" % [unit_type, tally["works"], tally["waits"],
			tally["prose"], tally["broken"], tally["all"]])
	print("  " + "-".repeat(70))
	print("  %-24s %6d %6d %11d %7d   %d" % ["ALL FOUR", total["works"], total["waits"],
		total["prose"], total["broken"], total["all"]])
	print("")
	var share := 100.0 * float(total["works"]) / maxf(1.0, float(total["all"]))
	print("  %.0f%% of your class abilities work in a match today." % share)
	if not waiting_words.is_empty():
		print("  Wired but waiting on: %s" % ", ".join(PackedStringArray(waiting_words.keys())))
	print("  The rest are words on a card - data/AbilityAudit.csv says which phase brings each.")
	print("")
	if broken_lines.is_empty():
		print("=== ALL GOOD ===")
	else:
		print("=== %d PROBLEM(S) ===" % broken_lines.size())
		for line in broken_lines:
			print("  . " + line)
	quit()


func _judge(cell: String, db: CardDatabase, waiting: Dictionary) -> String:
	var ids: Array[String] = []
	for piece in cell.split(";"):
		if String(piece).strip_edges() != "":
			ids.append(String(piece).strip_edges())
	if ids.is_empty():
		return "prose"
	var all_live := true
	for ability_id in ids:
		var ability := db.get_ability(ability_id)
		if ability == null:
			return "broken - '%s' is not a row of any abilities file" % ability_id
		if not AbilityData.trigger_is_live(ability.trigger):
			all_live = false
			waiting[ability.trigger] = true
		if not AbilityData.EFFECTS.has(ability.effect):
			all_live = false
			waiting[ability.effect] = true
		for term in AbilityData.condition_terms(ability.condition):
			if not AbilityData.condition_is_live(String(term["word"])):
				all_live = false
				waiting[String(term["raw"])] = true
	return "works" if all_live else "waits"
