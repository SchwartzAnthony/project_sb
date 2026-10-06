class_name AudioDirector
extends Node

# =============================================================
#  THE THING THAT ACTUALLY PLAYS THE SOUNDS
#
#  audio_db.gd reads Audio.csv and decides WHAT should play. This plays it.
#  Keeping them apart is what makes the CSV testable without a speaker.
#
#  ------------------------------------------------------------
#  WHY IT LIVES WHERE IT DOES
#
#  It attaches itself to the ROOT of the scene tree, not to a screen. That
#  is the whole reason music can carry across from the base to the season
#  screen without restarting: changing scene throws away the current scene,
#  but never the root.
#
#  There is one of it, it makes itself the first time anything asks for a
#  sound, and nothing has to be registered as an autoload.
#  ------------------------------------------------------------
#
#  ONE LOOPING TRACK PER BUS. Starting a new loop on Music fades the old one
#  out and the new one in. Asking for the track that is already playing does
#  nothing at all — so walking base → pub → base does not restart the theme
#  three times.
#
#  One-shots are separate and never interrupt anything.
# =============================================================

const NODE_NAME := "CoworkAudioDirector"
## How many one-shots can overlap before the oldest is reused. A goal, a
## whistle and three duel hits at once is about the worst case.
const VOICES := 8

var db: AudioDB

## bus -> {"player": AudioStreamPlayer, "cue_id": String}
var _loops: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _muted: bool = false


# =============================================================
#  GETTING HOLD OF IT
# =============================================================

## The director between being made and actually joining the tree. See below.
static var _pending: AudioDirector = null


## ============ WHY THIS IS MORE CAREFUL THAN IT LOOKS ============
##
## The very first sound of the session is fired from a screen's _ready(),
## which happens while Godot is still adding that screen's children. The
## tree is LOCKED at that moment, and a plain add_child() on the root fails:
##
##     Parent node is busy setting up children, `add_child()` failed.
##
## So the director is added with call_deferred(), which means "as soon as
## the tree is free again" — a frame or so later. That leaves a gap where
## the director exists but is not in the tree yet, and two things follow:
##
##   1. `_pending` holds it, so a second fetch() in that same gap gets the
##      SAME director instead of making a second one.
##   2. Anything played during the gap is queued on it and flushed by
##      _ready(). Nothing is dropped and nothing is played twice.
static func fetch(tree: SceneTree) -> AudioDirector:
	if tree == null or tree.root == null:
		return null

	var existing := tree.root.get_node_or_null(NODE_NAME) as AudioDirector
	if existing != null:
		return existing

	# Already made this frame and still waiting to be added.
	if _pending != null and is_instance_valid(_pending):
		return _pending

	var made := AudioDirector.new()
	made.name = NODE_NAME
	# Sound must keep running while the game is paused — the pause menu has
	# its own music, and a paused game with dead audio feels broken.
	made.process_mode = Node.PROCESS_MODE_ALWAYS
	_pending = made
	tree.root.add_child.call_deferred(made)
	return made


## THE ONE CALL EVERYTHING ELSE MAKES.
##
## Safe to call from anywhere, at any time, with a tree that has no director
## yet. If Audio.csv is empty or missing it does nothing and says nothing.
static func fire(tree: SceneTree, event: String, facts: Dictionary = {},
		state: GameState = null) -> void:
	var director := fetch(tree)
	if director != null:
		director.play_event(event, facts, state)


## ============ A SCREEN SAYS WHAT IT IS ============
##
## Called from MenuEscape.install(), which every screen in the game already
## calls, so the screen announces itself the moment it is built — however it
## was reached. That includes the very first screen of the session, which is
## simply there when the window opens and never went through go_to().
##
## The name is worked out from the scene file, so a screen added next year
## gets its music from a row in Audio.csv and no code at all.
static func announce_screen(tree: SceneTree, screen: Node) -> void:
	if tree == null or screen == null:
		return
	var path := screen.scene_file_path
	if path == "":
		# A screen built in code rather than from a .tscn. Its node name is
		# the best word we have, and it is usually the right one.
		path = "res://%s.tscn" % screen.name.to_lower()
	fire(tree, "screen_opened", {"screen": ScenePaths.screen_word(path)},
		GameState.fetch(tree))


## Cues fired before this node reached the tree, oldest first.
var _queued: Array[Dictionary] = []


func _ready() -> void:
	db = AudioDB.get_db()
	# ROUND AN: the Music, Effects and UI buses exist before the first sound
	# is played on one. Without them everything played on Master and only the
	# Everything slider did anything. See GameSettings.ensure_buses().
	GameSettings.ensure_buses()
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % i
		add_child(voice)
		_voices.append(voice)

	# We are in the tree now, so nothing else needs to hold us.
	if _pending == self:
		_pending = null

	# Play whatever was fired while we were still on our way in — the screen
	# music of the very first screen, usually.
	var backlog := _queued.duplicate()
	_queued.clear()
	for entry in backlog:
		play_event(String(entry["event"]), entry["facts"] as Dictionary,
			entry["state"] as GameState)


# =============================================================
#  PLAYING
# =============================================================

func play_event(event: String, facts: Dictionary, state: GameState) -> void:
	# Fired before we joined the tree. Keep it; _ready() will play it.
	# Without this, the first screen of the session opens in silence.
	if not is_inside_tree():
		_queued.append({"event": event, "facts": facts, "state": state})
		return
	if db == null or _muted:
		return

	var cues := db.cues_for(event, facts, state)
	for cue in cues:
		if bool(cue["loop"]):
			_start_loop(cue)
		else:
			_play_once(cue)

	# ============ AND A SCREEN WITH NO MUSIC IS QUIET ============
	#
	# THE BUG THIS FIXES: "the base music plays non-stop and no other music
	# is able to play."
	#
	# A looping track holds its bus until something else claims it. The base
	# has a row in Audio.csv; the team shelf, the bounty board and the
	# builder do not — so walking out of the base handed the base theme a
	# lease on the Music bus for the rest of the session, and every screen
	# after it inherited the wrong music.
	#
	# So a screen opening is now a moment where the Music bus is RECLAIMED:
	# if no looping row claimed it for this screen, the track that is
	# playing is faded out. That is the cut between screens.
	#
	# To carry a track across a screen deliberately, give that screen a row
	# naming the same Sound — the loop logic sees the same cue and leaves it
	# alone, so there is no gap. `music_follows_screen` in Tuning.csv turns
	# the whole reclaim off.
	if event == "screen_opened" and _music_follows_screen():
		var claimed := false
		for cue in cues:
			if bool(cue["loop"]) and String(cue["bus"]) == "Music":
				claimed = true
				break
		if not claimed:
			var quiet := 1.0
			var db_card := CardDatabase.get_db()
			if db_card != null:
				quiet = db_card.tune_float("music_fade_out_seconds", 1.0)
			stop_loop("Music", quiet)


func _music_follows_screen() -> bool:
	var book := CardDatabase.get_db()
	return book == null or book.tune_bool("music_follows_screen", true)


## ============ PLAY ONE SOUND BY NAME ============
##
## What the Juice spreadsheet uses. `sound` is an Audio.csv row ID, or the
## name of a file in assets/audio/ — see AudioDB.cue_by_name().
##
## A name that matches neither is NOT an error: the game is silent until the
## files exist, which is the whole arrangement. It says so once, quietly, so
## a typo is findable without filling the Output panel.
static func play_cue(tree: SceneTree, sound: String,
		_facts: Dictionary = {}) -> void:
	if tree == null or sound.strip_edges() == "":
		return
	var director := fetch(tree)
	if director == null:
		return
	var cue := AudioDB.get_db().cue_by_name(sound)
	if cue.is_empty():
		if not _moaned.has(sound):
			_moaned[sound] = true
			var waiting := AudioDB.get_db().waiting_for(sound)
			if waiting != "":
				print("[audio] '%s' has a row in Audio.csv, but its sound file '%s' is not in assets/audio/ yet. Silent for now." % [sound, waiting])
			else:
				print("[audio] '%s' is named in a spreadsheet but there is no Audio.csv row and no file in assets/audio/. Silent for now." % sound)
		return
	director._play_once(cue)


## Names we have already complained about, so one missing sound does not
## print on every single hit.
static var _moaned: Dictionary = {}


func _play_once(cue: Dictionary) -> void:
	# NO VOICES, NO SOUND, NO CRASH. The pool is built when the director
	# enters the tree, and there are two ways it can be empty when a cue
	# arrives: a headless run with no audio server (every tool in tools/),
	# and the handful of frames before the director is ready. Neither is a
	# reason to take the game down over a sound effect.
	if _voices.is_empty():
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()

	voice.stream = cue["stream"]
	voice.bus = String(cue["bus"])
	voice.volume_db = float(cue["volume"])
	voice.play()


func _start_loop(cue: Dictionary) -> void:
	var bus := String(cue["bus"])
	var cue_id := String(cue["id"]) if String(cue["id"]) != "" else String(cue["where"])

	# ALREADY PLAYING? Then leave it alone. This is what stops the base theme
	# restarting every time you step into the Pub and back out again.
	if _loops.has(bus):
		var current: Dictionary = _loops[bus]
		var player := current["player"] as AudioStreamPlayer
		if String(current["cue_id"]) == cue_id and player != null and player.playing:
			return
		# ROUND AL: THE SAME TRACK FROM ANOTHER ROW keeps playing - no restart,
		# no gap - and only glides to that row's Volume. This is how the menu
		# music carries on into Settings and the save screen, just quieter:
		# their rows name the same Sound with a lower Volume.
		if player != null and player.playing and player.stream == cue["stream"]:
			current["cue_id"] = cue_id
			var glide := create_tween()
			glide.tween_property(player, "volume_db", float(cue["volume"]), maxf(0.3, float(cue["fade"])))
			return
		_fade_out(player, float(cue["fade"]))

	var fresh := AudioStreamPlayer.new()
	fresh.name = "Loop_%s" % bus
	fresh.stream = cue["stream"]
	# ROUND AL: an .ogg or .mp3 told to loop itself joins end to start with no
	# gap at all (tools/make_loop.py cuts them to join cleanly). The restart
	# below stays as the fallback for .wav and anything else.
	if fresh.stream is AudioStreamOggVorbis:
		(fresh.stream as AudioStreamOggVorbis).loop = true
	elif fresh.stream is AudioStreamMP3:
		(fresh.stream as AudioStreamMP3).loop = true
	fresh.bus = bus
	fresh.volume_db = float(cue["volume"])
	add_child(fresh)

	var fade := float(cue["fade"])
	if fade > 0.0:
		fresh.volume_db = float(cue["volume"]) - 40.0
		fresh.play()
		var rise := create_tween()
		rise.tween_property(fresh, "volume_db", float(cue["volume"]), fade)
	else:
		fresh.play()

	# Godot does not loop a stream unless the stream itself says so, and an
	# imported .ogg often does not. Restarting it on finish is the one way
	# that works whatever the import settings are.
	fresh.finished.connect(func() -> void:
		if is_instance_valid(fresh) and not _muted:
			fresh.play())

	_loops[bus] = {"player": fresh, "cue_id": cue_id}


func _fade_out(player: AudioStreamPlayer, seconds: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if seconds <= 0.0:
		player.queue_free()
		return
	var drop := create_tween()
	drop.tween_property(player, "volume_db", -60.0, seconds)
	drop.tween_callback(player.queue_free)


# =============================================================
#  STOPPING
# =============================================================

## Stop the looping track on one bus — "" for all of them.
func stop_loop(bus: String = "", seconds: float = 0.4) -> void:
	for key in _loops.keys():
		if bus != "" and String(key) != bus:
			continue
		var entry: Dictionary = _loops[key]
		_fade_out(entry["player"] as AudioStreamPlayer, seconds)
	if bus == "":
		_loops.clear()
	else:
		_loops.erase(bus)


func set_muted(value: bool) -> void:
	_muted = value
	for key in _loops.keys():
		var entry: Dictionary = _loops[key]
		var player := entry["player"] as AudioStreamPlayer
		if player != null and is_instance_valid(player):
			player.stream_paused = value
