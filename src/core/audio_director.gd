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

static func fetch(tree: SceneTree) -> AudioDirector:
	if tree == null or tree.root == null:
		return null

	var existing := tree.root.get_node_or_null(NODE_NAME) as AudioDirector
	if existing != null:
		return existing

	var made := AudioDirector.new()
	made.name = NODE_NAME
	# Sound must keep running while the game is paused — the pause menu has
	# its own music, and a paused game with dead audio feels broken.
	made.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(made)
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


func _ready() -> void:
	db = AudioDB.get_db()
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % i
		add_child(voice)
		_voices.append(voice)


# =============================================================
#  PLAYING
# =============================================================

func play_event(event: String, facts: Dictionary, state: GameState) -> void:
	if db == null or _muted:
		return
	for cue in db.cues_for(event, facts, state):
		if bool(cue["loop"]):
			_start_loop(cue)
		else:
			_play_once(cue)


func _play_once(cue: Dictionary) -> void:
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
		_fade_out(player, float(cue["fade"]))

	var fresh := AudioStreamPlayer.new()
	fresh.name = "Loop_%s" % bus
	fresh.stream = cue["stream"]
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
func stop_loop(bus: String = "") -> void:
	for key in _loops.keys():
		if bus != "" and String(key) != bus:
			continue
		var entry: Dictionary = _loops[key]
		_fade_out(entry["player"] as AudioStreamPlayer, 0.4)
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
