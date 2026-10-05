extends SceneTree

# =============================================================
#  READING OutOfBounds.csv BACK TO YOU
#
#  This sequence happens NINE TIMES A MATCH. A second added to it is nine
#  seconds of match, and the difference between a restart that feels like
#  football and one that feels like waiting is about two seconds — so the
#  total is the number to watch, and it is printed first.
#
#      godot --headless --script res://tools/out_of_bounds_check.gd
#
#  Then: every row in order with a clock down the side, everything a row
#  names that does not exist, and the ordering rule (`roll` has to come
#  before the beats that are about the player it picks).
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const KNOWN_WORDS: Array[String] = ["loser", "thrower", "side", "tier", "keeper", "call", "caption"]
const ROUNDS_A_MATCH := 9


func _initialize() -> void:
	var db := CardDatabase.get_db()
	var problems := 0

	print("")
	print("=== OutOfBounds.csv ===")
	for problem in OutOfBoundsBook.problems():
		print("  ! %s" % problem)
		problems += 1

	var beats := OutOfBoundsBook.steps()
	if beats.is_empty():
		print("  No steps. A round opens straight into the picks, which is what")
		print("  it did before this file existed.")
		quit(0)
		return

	print("")
	print("  %-5s %-10s %8s   %s" % ["at", "do", "seconds", "what"])
	var clock := 0.0
	for beat in beats:
		var what := String(beat["text"])
		if what == "":
			what = String(beat["animation"])
		if what == "":
			what = String(beat["sound"])
		print("  %5.1f %-10s %8.2f   %s" % [clock, beat["do"], beat["seconds"], what])
		clock += float(beat["seconds"])

	var total := OutOfBoundsBook.total_seconds()
	print("")
	print("  ONE ROUND OPENS IN %.1fs." % total)
	print("  Nine rounds a match, so %.0fs of every match is this sequence."
		% (total * float(ROUNDS_A_MATCH)))
	if total > 8.0:
		print("  ! Over eight seconds. Nine of those is over a minute of watching.")
		problems += 1

	# ---- what the rows name ----
	print("")
	print("  --- what the rows name ---")
	var said := 0
	for beat in beats:
		var step := String(beat["step"])

		var sound := String(beat["sound"])
		if sound != "" and AudioDB.get_db().cue_by_name(sound).is_empty():
			var waiting := AudioDB.get_db().waiting_for(sound)
			if waiting != "":
				print("  ! %s: sound '%s' has a row but no file (%s) — silent for now."
					% [step, sound, waiting])
			else:
				print("  ! %s: sound '%s' is in neither Audio.csv nor assets/audio/." % [step, sound])
			problems += 1
			said += 1

		var animation := String(beat["animation"])
		if animation != "" and db.get_anim(animation, "") == null:
			print("  ! %s: '%s' is not a row of Animations.csv. The window falls back to 'lose', then 'idle'."
				% [step, animation])
			problems += 1
			said += 1

		var art := String(beat["art"])
		if art != "" and MenuSupport.icon_texture(art) == null:
			print("  ! %s: Art '%s' is not in assets/ — the window will use the animation instead."
				% [step, art])
			problems += 1
			said += 1

		for word in _placeholders(String(beat["text"])):
			if not KNOWN_WORDS.has(word):
				print("  ! %s: {%s} is not a word the game fills in. The ones it knows are: %s"
					% [step, word, ", ".join(KNOWN_WORDS)])
				problems += 1
				said += 1
	if said == 0:
		print("  everything every row names is there.")

	# ---- the numbers that are not per-beat ----
	print("")
	print("  --- Tuning.csv ---")
	print("  %-30s %s" % ["out_of_bounds", db.tune_bool("out_of_bounds", true)])
	print("  %-30s %.2f   (how often YOU give it away)"
		% ["out_of_bounds_player_chance", db.tune_float("out_of_bounds_player_chance", 0.5)])
	for key in ["throw_in_inset", "throw_in_read_seconds", "throw_in_settle_seconds"]:
		print("  %-30s %.2f" % [key, db.tune_float(key, 0.0)])

	print("")
	print("=== %s ===" % ("ALL GOOD" if problems == 0 else "%d thing(s) to look at" % problems))
	print("")
	quit(0)


func _placeholders(text: String) -> Array[String]:
	var out: Array[String] = []
	var at := text.find("{")
	while at >= 0:
		var close := text.find("}", at)
		if close < 0:
			break
		var word := text.substr(at + 1, close - at - 1).strip_edges()
		if word != "" and not out.has(word):
			out.append(word)
		at = text.find("{", close)
	return out
