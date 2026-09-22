extends SceneTree

# =============================================================
#  IS THE RIGHT SOUND GOING TO PLAY, AND IS THE FILE EVEN THERE?
#
#  Sound is the hardest thing in the game to test by playing it: you have to
#  get to the moment, and then you have to trust your ears about which of two
#  similar noises you just heard. So this asks the question in writing.
#
#  It prints four things:
#
#    1. EVERY ROW of Audio.csv, and whether the file it names actually
#       exists in assets/audio/. A row whose file is missing is silent, and
#       silence is indistinguishable from a bug.
#
#    2. WHICH ROWS ANSWER each moment — the screens, the match moments, the
#       result of a match. A moment with no row is a moment with no sound.
#
#    3. WHICH SCREENS HAVE MUSIC and which are deliberately quiet. A screen
#       with no looping Music row now STOPS whatever was playing, so this is
#       also the list of screens that will go quiet.
#
#    4. THE DUEL RESULT, worked through all four cases. This is the one that
#       was wrong: the win sound played on half the losses.
#
#      godot --headless --script res://tools/audio_check.gd
#
#  A tool, not part of the game. Nothing loads it.
# =============================================================

func _initialize() -> void:
	await process_frame
	var book := AudioDB.get_db()
	var bad := 0

	# ---- 1. every row, and whether its file is there ----
	print("")
	print("[audio] ==== EVERY ROW, AND ITS FILE ====")
	var missing: Array[String] = []
	for row in MenuSupport.read_csv("res://data/Audio.csv"):
		var id_text := MenuSupport.field(row, "ID").strip_edges()
		if id_text == "":
			continue
		var sound := MenuSupport.field(row, "Sound").strip_edges()
		var cue := book.cue_by_name(sound)
		var there := not cue.is_empty()
		if not there and not missing.has(sound):
			missing.append(sound)
		print("[audio] %-22s %-18s %s" % [id_text, sound,
			"ok" if there else "NO FILE in assets/audio/"])

	# ---- 2. the moments ----
	print("")
	print("[audio] ==== WHICH ROWS ANSWER EACH MOMENT ====")
	var moments := {
		"screen_opened  main": {"screen": "main"},
		"screen_opened  base": {"screen": "base"},
		"screen_opened  match": {"screen": "match"},
		"screen_opened  pub": {"screen": "pub"},
		"screen_opened  season": {"screen": "season"},
		"screen_opened  teamselect": {"screen": "teamselect"},
		"screen_opened  bounty": {"screen": "bounty"},
		"kick_off": {},
		"goal_scored": {},
		"goal_conceded": {},
		"duel_won": {},
		"duel_lost": {},
		"play_maker": {},
	}
	for label in moments:
		var event: String = label.split("  ")[0]
		var cues := book.cues_for(event, moments[label], null)
		var names: Array[String] = []
		for cue in cues:
			names.append("%s%s" % [cue["id"], " (loop)" if bool(cue["loop"]) else ""])
		print("[audio] %-24s %s" % [label,
			", ".join(names) if not names.is_empty() else "— nothing"])

	# ---- 3. the result rows ----
	print("")
	print("[audio] ==== THE RESULT OF A MATCH ====")
	for outcome in ["win", "loss", "draw"]:
		var cues := book.cues_for("match_ended", {"result": outcome}, null)
		var names: Array[String] = []
		for cue in cues:
			names.append("%s -> %s" % [cue["id"], cue["where"]])
		print("[audio] %-6s %s" % [outcome,
			", ".join(names) if not names.is_empty() else "— nothing"])

	# ---- 4. and the duel, all four ways round ----
	print("")
	print("[audio] ==== THE DUEL RESULT, WORKED THROUGH ====")
	print("[audio] (the bug was reading possession AFTER a turnover flipped it)")
	for was_mine_any in [true, false]:
		for attacker_wins_any in [true, false]:
			var was_mine: bool = was_mine_any
			var attacker_wins: bool = attacker_wins_any
			var i_won: bool = attacker_wins == was_mine
			var flipped: bool = was_mine if attacker_wins else not was_mine
			var old_answer: bool = attacker_wins == flipped
			var mark := "ok" if old_answer == i_won else "WAS WRONG"
			print("[audio] ball %-6s attacker %-6s -> you %-4s   (old code said %-4s, %s)" % [
				"yours" if was_mine else "theirs",
				"holds" if attacker_wins else "loses",
				"won" if i_won else "lost",
				"won" if old_answer else "lost", mark])

	print("")
	if missing.is_empty():
		print("[audio] every sound named in Audio.csv has a file. Nothing is silent.")
	else:
		bad += 1
		print("[audio] %d sound(s) named in Audio.csv have NO FILE and are silent:" % missing.size())
		print("[audio]   %s" % ", ".join(missing))
		print("[audio] They are listed in SOUNDS_WANTED.csv with what each should sound like.")
	quit(0 if bad == 0 else 1)
