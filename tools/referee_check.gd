extends SceneTree

# =============================================================
#  THE REFEREE, PRICED IN FOULS
#
#  ============ WHAT IT ANSWERS ============
#
#  A foul is now two questions — did one happen (Fouls.csv) and did he see it
#  (Referee.csv) — and the second one is invisible. You cannot watch a match
#  and know whether he is missing one in three or one in thirty.
#
#  So this plays ten thousand rounds against each referee and prints the
#  numbers in the units you actually feel:
#
#      HOW MANY FOULS HE MISSES       the headline. Too high and the bar is
#                                     decoration; too low and it is a tax
#      HOW LONG THE BAR TAKES         in rounds, from empty to full
#      FOULS BEFORE THE FIRST CARD    the number a player will describe as
#                                     "how long he lets you get away with it"
#      WHAT A SECOND BOOKING COSTS    the red share, before and after
#
#  ============ WHY IT SIMULATES RATHER THAN READS ============
#
#  Because the answer is not in any one column. It falls out of the trigger
#  curve, the fill rate, the segment count and the catch chance all running
#  against each other, and the only honest way to get it is to play it.
#
#  godot --headless --script res://tools/referee_check.gd
# =============================================================

const ROUNDS := 10000
const LINE := "  ────────────────────────────────────────────────────────────"

## A round of this many triggers, roughly how a real match goes: mostly
## quiet, occasionally everything at once.
const TRIGGER_SHAPE := [0, 0, 1, 2, 2, 3, 4, 6, 9]


func _initialize() -> void:
	print("")
	print("=== THE REFEREE ===")
	print("")

	var db := CardDatabase.get_db()
	if db == null:
		print("  no card database.")
		quit()
		return

	if not Referee.on(db):
		print("  `referee` is FALSE in Tuning.csv, so every foul is called the")
		print("  moment it happens and none of this applies. Set it true to use")
		print("  the attention bar.")
		print("")

	_who()
	for ref in Referee.every():
		_measure(db, ref)
	_trouble()
	quit()


func _who() -> void:
	print("  === WHO IS AVAILABLE ===")
	print("  %-10s %-20s %-5s %-9s %-9s %-9s %s"
		% ["id", "name", "segs", "/trigger", "/foul", "when full", "after yellow"])
	print(LINE)
	for ref in Referee.every():
		print("  %-10s %-20s %-5d %-9.2f %-9.2f %-9.0f %.0f" % [
			ref["id"], ref["name"], int(ref["segments"]),
			float(ref["per_trigger"]), float(ref["per_foul"]),
			float(ref["when_full"]), float(ref["after_yellow"])])
	print("")


func _measure(db: CardDatabase, ref: Dictionary) -> void:
	print("  === %s (%s) ===" % [String(ref["name"]).to_upper(), ref["id"]])

	# ---- how long the bar takes, with no fouls at all ----
	var per_round := 0.0
	for many in TRIGGER_SHAPE:
		per_round += float(ref["per_trigger"]) * float(many)
	per_round /= float(TRIGGER_SHAPE.size())
	var rounds_to_full := 999.0
	if per_round > 0.0:
		rounds_to_full = float(ref["segments"]) / per_round
	print("  an average round sets off %.1f trigger(s), which fills %.2f of a segment."
		% [_average_triggers(), per_round])
	print("  SO THE BAR FILLS IN ABOUT %.1f ROUNDS if nothing is given away."
		% rounds_to_full)
	if rounds_to_full > 18.0:
		print("     THAT IS LONGER THAN A MATCH. A bar that never fills is a bar")
		print("     nobody looks at — raise Fill Per Trigger or cut Segments.")
	elif rounds_to_full < 3.0:
		print("     THAT IS VERY FAST. He will be booking people in the first")
		print("     few minutes — lower Fill Per Trigger if that is not the idea.")
	print("")

	# ---- the real thing, played out ----
	var seen := 0
	var missed := 0
	var yellows := 0
	var reds := 0
	var frees := 0
	var fouls_before_first_card := 0
	var counted_first := false
	var matches := 0
	var rounds_this_match := 0

	Referee.clear_heat()
	var yellows_this_match := 0
	var fouls_this_match := 0
	# ROUND X: WHO did it. Twelve men a side; each foul is one of them, and
	# his own record makes the next one easier to see and likelier to be a
	# booking - Caught Per Own Foul and Card Per Own Foul.
	var by_man: Dictionary = {}
	var repeat_bookings := 0

	for i in ROUNDS:
		# A MATCH IS NINE ROUNDS, and the bar is a thing about one afternoon.
		rounds_this_match += 1
		if rounds_this_match > 9:
			rounds_this_match = 1
			matches += 1
			Referee.clear_heat()
			yellows_this_match = 0
			fouls_this_match = 0
			by_man.clear()

		var many: int = TRIGGER_SHAPE[randi() % TRIGGER_SHAPE.size()]
		Referee.watch_round(false, many, db)

		var verdict := FoulBook.roll(many)
		if verdict == "":
			continue
		fouls_this_match += 1

		var man := randi() % 12
		var his := int(by_man.get(man, 0))
		by_man[man] = his + 1
		if randf() * 100.0 >= Referee.notice_chance(false, yellows_this_match, db, his):
			missed += 1
			Referee.got_away_with_it(false, db)
			continue

		seen += 1
		if verdict == "yellow" and randf() * 100.0 < Referee.red_bonus(yellows_this_match, db):
			verdict = "red"
		Referee.whistled(false, db)

		if verdict == "yellow":
			yellows += 1
			yellows_this_match += 1
		elif verdict == "red":
			reds += 1
		else:
			if randf() * 100.0 < Referee.card_bump(false, his, db):
				yellows += 1
				yellows_this_match += 1
				repeat_bookings += 1
			else:
				frees += 1

		if not counted_first and verdict != "free kick":
			fouls_before_first_card = fouls_this_match
			counted_first = true

	var fouls := seen + missed
	print("  %d round(s) played, about %d match(es)." % [ROUNDS, maxi(1, matches)])
	print("  %-34s %d" % ["fouls committed", fouls])
	if fouls > 0:
		print("  %-34s %d  (%.0f%%)" % ["HE DID NOT SEE", missed, 100.0 * missed / fouls])
		print("  %-34s %d  (%.0f%%)" % ["he blew the whistle", seen, 100.0 * seen / fouls])
	print("  %-34s %d" % ["free kicks", frees])
	print("  %-34s %d" % ["yellow cards", yellows])
	print("  %-34s %d" % ["red cards", reds])
	print("  %-34s %d   (free kicks his own record turned into yellows)" % ["...of which repeat offenders", repeat_bookings])
	if matches > 0:
		print("  %-34s %.2f" % ["cards per match", float(yellows + reds) / float(matches)])
	print("")

	# ---- the verdict, in words ----
	var miss_share := 0.0 if fouls == 0 else 100.0 * missed / fouls
	if miss_share > 80.0:
		print("     HE MISSES FOUR IN FIVE. The bar is decoration at that rate —")
		print("     a player will never see a card and will never learn the rule.")
	elif miss_share < 20.0:
		print("     HE SEES ALMOST EVERYTHING, which is the system you had before")
		print("     the bar existed. Lower Caught Per Segment to open it up.")
	else:
		print("     He misses %.0f%% of them, which is the shape you want: getting" % miss_share)
		print("     away with one is common, getting away with four is not.")
	if matches > 0:
		var per_match := float(yellows + reds) / float(matches)
		if per_match > 4.0:
			print("     %.1f cards a match is a lot of football stopped." % per_match)
		elif per_match < 0.8:
			print("     %.1f cards a match means most matches have none at all. That" % per_match)
			print("     is the Fouls.csv curve, not the referee: raise Foul Chance")
			print("     there if you want cards to be part of a normal afternoon.")
	print("")


func _average_triggers() -> float:
	var total := 0.0
	for many in TRIGGER_SHAPE:
		total += float(many)
	return total / float(TRIGGER_SHAPE.size())


func _trouble() -> void:
	var found := Referee.problems()
	if found.is_empty():
		print("=== ALL GOOD ===")
		return
	print("=== %d PROBLEM(S) ===" % found.size())
	for one in found:
		print("  . %s" % one)
