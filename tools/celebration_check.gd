extends SceneTree

# =============================================================
#  READING Celebration.csv BACK TO YOU
#
#  A celebration is a list of beats and a total length, and the thing you
#  will get wrong is the total length: eleven seconds reads beautifully the
#  first time and is unbearable by the fourth goal.
#
#  So this prints the list, in order, with a running clock — and then the
#  three things that are worth being told rather than discovering in a
#  match:
#
#      HOW LONG a goal now costs, yours and theirs, and what that is on top
#      of (goal_pause_seconds is still there afterwards);
#      ANYTHING NAMED THAT DOES NOT EXIST — a sound with no Audio.csv row and
#      no file, an animation with no row in Animations.csv, an Art file that
#      is not in assets/;
#      ANY PLACEHOLDER the caption uses that nothing fills in.
#
#      godot --headless --script res://tools/celebration_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

const KNOWN_WORDS: Array[String] = ["scorer", "team", "class", "tier", "score"]

func _initialize() -> void:
	var db := CardDatabase.get_db()
	var problems := 0

	print("")
	print("=== Celebration.csv ===")
	for problem in CelebrationBook.problems():
		print("  ! %s" % problem)
		problems += 1

	var beats := CelebrationBook.steps()
	if beats.is_empty():
		print("  No steps. A goal is the word GOAL for verdict_seconds and then")
		print("  the restart — exactly what it was before Celebration.csv existed.")
		quit(0)
		return

	# ============ TWO LISTS, NOT ONE ============
	#
	# Your goals and theirs are separate runs of the same spreadsheet, so one
	# combined clock would say a `them` row happens eight seconds in when in
	# its own celebration it is the first thing that happens.
	_running_order("YOUR GOAL", true)
	_running_order("THEIR GOAL", false)

	# ---- how long a goal costs ----
	var after := db.tune_float("goal_pause_seconds", 2.0)
	print("")
	print("  YOUR goal:   %.1fs of celebration, then %.1fs walking back = %.1fs"
		% [CelebrationBook.total_seconds(true), after,
			CelebrationBook.total_seconds(true) + after])
	print("  THEIR goal:  %.1fs of celebration, then %.1fs walking back = %.1fs"
		% [CelebrationBook.total_seconds(false), after,
			CelebrationBook.total_seconds(false) + after])
	if CelebrationBook.total_seconds(true) > 12.0:
		print("  ! Over twelve seconds. It will read well once and be long by the fourth goal.")
		problems += 1

	# ---- is everything it names actually there ----
	print("")
	print("  --- what the rows name ---")
	for beat in beats:
		var step := String(beat["step"])

		var sound := String(beat["sound"])
		if sound != "" and AudioDB.get_db().cue_by_name(sound).is_empty():
			var waiting := AudioDB.get_db().waiting_for(sound)
			if waiting != "":
				print("  ! %s: sound '%s' has a row but no file (%s) — silent for now."
					% [step, sound, waiting])
			else:
				print("  ! %s: sound '%s' is in neither Audio.csv nor assets/audio/."
					% [step, sound])
			problems += 1

		var animation := String(beat["animation"])
		if animation != "" and db.get_anim(animation, "") == null:
			print("  ! %s: '%s' is not a row of Animations.csv. The window will fall back to 'win', then 'idle'."
				% [step, animation])
			problems += 1

		var art := String(beat["art"])
		if art != "" and MenuSupport.icon_texture(art) == null:
			print("  ! %s: Art '%s' is not in assets/ — the window will use the animation instead."
				% [step, art])
			problems += 1

		for word in _placeholders(String(beat["text"])):
			if not KNOWN_WORDS.has(word):
				print("  ! %s: {%s} is not a word the game fills in. The ones it knows are: %s"
					% [step, word, ", ".join(KNOWN_WORDS)])
				problems += 1

	# ---- and the shape numbers ----
	print("")
	print("  --- Tuning.csv ---")
	for key in ["goal_celebration", "celebration_skippable"]:
		print("  %-30s %s" % [key, db.tune_bool(key, true)])
	for key in ["celebration_slide_distance", "celebration_swarm_radius",
			"celebration_confetti_pieces", "celebration_confetti_speed"]:
		print("  %-30s %.0f" % [key, db.tune_float(key, 0.0)])

	print("")
	print("=== %s ===" % ("ALL GOOD" if problems == 0 else "%d thing(s) to look at" % problems))
	print("")
	quit(0)


## One side's celebration, in order, with its own clock.
func _running_order(title: String, scored_by_player: bool) -> void:
	var beats := CelebrationBook.steps_for(scored_by_player)
	print("")
	print("  --- %s ---" % title)
	if beats.is_empty():
		print("  nothing — this side's goals are the word and the restart.")
		return
	print("  %-5s  %-6s  %-9s  %7s   %s" % ["at", "who", "do", "seconds", "what"])
	var clock := 0.0
	for beat in beats:
		var what := String(beat["text"])
		if what == "":
			what = String(beat["animation"])
		if what == "":
			what = String(beat["sound"])
		print("  %5.1f  %-6s  %-9s  %7.2f   %s" % [
			clock, beat["who"], beat["do"], beat["seconds"], what])
		clock += float(beat["seconds"])


## The {words} in a caption, without their braces.
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
