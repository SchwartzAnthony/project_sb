extends SceneTree

# =============================================================
#  DOES EVERY SOUND ACTUALLY PLAY?  (round AN, 10 Oct)
#
#  audio_check.gd asks whether the files are there. This one goes further:
#
#    1. Every row of Audio.csv: its file DECODES and is longer than nothing.
#    2. A walk through the game's moments with the real AudioDirector, in
#       order - menu, base, Brewery window and back, Dorms window and back,
#       team shelf, Adventure board, the Marshlands, a match with its Play
#       Maker, a shot and play resuming - and after each step, which track
#       the Music bus is really playing.
#
#      godot --headless --path . --script res://tools/sound_playback_check.gd
#
#  Prints PASS or FAIL per line and a total. A tool; nothing loads it.
# =============================================================

var _fails := 0


func _initialize() -> void:
	await process_frame
	var book := AudioDB.get_db()

	print("")
	print("[play] ==== EVERY ROW DECODES ====")
	var rows := 0
	for cue in book.cues:
		rows += 1
		var stream: AudioStream = cue["stream"]
		var length := stream.get_length() if stream != null else 0.0
		_check(length > 0.01, "%-24s %-30s %6.2f s" % [cue["id"], cue["sound"], length])
	print("[play] %d rows with a file" % rows)
	for id_text in book.named_but_silent:
		print("[play] WAITING  %-24s %s (no file yet, silent on purpose)" % [id_text, book.named_but_silent[id_text]])

	var director := AudioDirector.fetch(self)
	await process_frame
	await process_frame

	print("")
	print("[play] ==== THE MUSIC BUS, MOMENT BY MOMENT ====")
	var steps := [
		["screen_opened", {"screen": "main"}, "menu_suno"],
		["screen_opened", {"screen": "base"}, "base_suno"],
		["window_opened", {"screen": "brewery", "over": "base"}, "suno_brewery_music"],
		["screen_opened", {"screen": "base"}, "base_suno"],
		["window_opened", {"screen": "dorms", "over": "base"}, "suno_dorms_music"],
		["screen_opened", {"screen": "base"}, "base_suno"],
		["window_opened", {"screen": "trophies", "over": "base"}, "base_suno"],
		["screen_opened", {"screen": "team_select"}, "suno_team_music"],
		["screen_opened", {"screen": "team_builder"}, "suno_team_music"],
		["screen_opened", {"screen": "team_build"}, "suno_team_music"],
		["screen_opened", {"screen": "bounty"}, "suno_adventure_menu_music"],
		["match_started", {"biome": "The Marshlands"}, "suno_marsh_music"],
		["screen_opened", {"screen": "pub"}, "dialogue_suno"],
		["screen_opened", {"screen": "dialogue"}, "dialogue_suno"],
		["screen_opened", {"screen": "match"}, "match_suno"],
		["play_maker", {"cycle": "1", "round": "1"}, "suno_play_maker_music"],
		["play_resumed", {}, "match_suno"],
		["goal_attempt", {"side": "you"}, "suno_goal_attempt_music"],
		["goal_attempt_over", {}, "match_suno"],
		["window_opened", {"screen": "brewery", "over": "match"}, "match_suno"],
	]
	for step in steps:
		director.play_event(step[0], step[1], null)
		var playing := _music_name(director, book)
		_check(playing == step[2], "%-14s %-36s -> %s%s" % [step[0], str(step[1]), playing,
			"" if playing == step[2] else "   (wanted %s)" % step[2]])

	print("")
	print("[play] ==== ONE-SHOT SOUNDS, MOMENT BY MOMENT ====")
	var shots := [
		["drink_big", {}, "drink_big"], ["drink_burp", {}, "drink_burp"],
		["brew_drunk", {"where": "pub"}, "brew_pour"], ["brew_drunk", {"where": "pitch"}, "drink_pitch"],
		["goal_scored", {}, "goal_horn"], ["duel_priority_check", {}, "duel_priority_check"],
		["duel_ability_check", {}, "duel_ability_check"], ["duel_power_check", {}, "duel_power_check"],
		["window_opened", {"screen": "pause", "over": "match"}, "menu_open"],
	]
	for shot in shots:
		var ids: Array[String] = []
		for cue in book.cues_for(shot[0], shot[1], null):
			if not bool(cue["loop"]):
				ids.append(String(cue["id"]))
		_check(ids.has(shot[2]), "%-20s %-28s -> %s" % [shot[0], str(shot[1]), ", ".join(ids)])
	# Juice.csv names sounds by row; every one must be found.
	for row in MenuSupport.read_csv("res://data/Juice.csv"):
		var named := MenuSupport.field(row, "Sound").strip_edges()
		if named != "":
			_check(not book.cue_by_name(named).is_empty(), "Juice %-20s %s" % [MenuSupport.field(row, "ID"), named])

	print("")
	print("[play] %s - %d problem(s)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)


## The Sound name of the track on the Music bus, found by matching its
## stream against the rows' streams.
func _music_name(director: AudioDirector, book: AudioDB) -> String:
	if not director._loops.has("Music"):
		return "(nothing)"
	var player := director._loops["Music"]["player"] as AudioStreamPlayer
	if player == null:
		return "(nothing)"
	for cue in book.cues:
		if cue["stream"] == player.stream:
			return String(cue["sound"])
	return "(unknown)"


func _check(ok: bool, text: String) -> void:
	if not ok:
		_fails += 1
	print("[play] %s  %s" % ["ok  " if ok else "FAIL", text])
