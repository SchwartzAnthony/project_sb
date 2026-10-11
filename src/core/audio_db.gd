class_name AudioDB
extends RefCounted

# =============================================================
#  AUDIO.CSV — every sound in the game, from a spreadsheet
#
#  One row per sound. Nothing in code ever names a file, so adding music to
#  a screen or a noise to an event is a row, never an edit.
#
#  THE COLUMNS
#    ID        a name for the row, unique. Yours; the game only prints it.
#    When      the moment it plays. The full list is below.
#    Match     an optional filter on that moment, so one event can have
#              different sounds. `screen=base`, `class=Lorelei`, `tier=IV`,
#              `result=win`. Blank = every time that moment happens.
#    Sound     the file, in assets/audio/. The extension may be left off.
#              Several names split by | are tried in order, and the first
#              file that is there plays: `suno_goal | bav_goal`.
#              End with `| -` for "or nothing yet": `suno_menu_open | -`
#              is silent, and not reported, until that file is there.
#    Bus       Music, Effects or UI. Looping tracks belong on Music.
#    Loop      true  = keeps playing until something else claims that bus.
#              blank = plays once and stops.
#    Volume    in decibels. 0 is the file as recorded, -6 is half as loud,
#              -80 is silent. Positive numbers are louder and usually
#              distort, so stay at or below 0.
#    Fade      seconds to fade in, and to fade the previous track out.
#              Only means anything for a looping track.
#    Requires  an optional condition, the same language as everywhere else.
#              This is how the base gets a different theme once the Brewery
#              is open: two rows, same When, different Requires.
#    Notes     yours.
#
#  WHEN — the moments a row can listen for
#    screen_opened   any screen appears.  Match: screen=base / season / pub…
#    match_started   kick-off
#    play_maker      the PLAY MAKER whistle
#    hold_up         the HOLD UP whistle
#    match_ended     the final whistle.  Match: result=win / loss / draw
#    goal_scored     you scored.    Match: class, tier, card, brew, star
#    goal_conceded   they scored
#    shot_taken      you had a shot
#    save_made       your keeper stopped one
#    duel_won        Match: tier=IV, brew=fire, …
#    duel_lost
#    brew_drunk
#    card_hovered    the mouse goes over a card
#    card_picked     a card is locked in
#    button_pressed  any menu button.  Match: button=play / back / …
#
#  TWO ROWS THAT SHOW THE WHOLE IDEA
#
#    base_theme,screen_opened,screen=base,base_calm,Music,true,-8,1.5,,
#    base_theme_brewing,screen_opened,screen=base,base_warm,Music,true,-8,1.5,unlocked:Brewery,
#
#  Same moment, same bus. Before the Brewery you get the calm track; after
#  it, the warm one. The LAST matching row wins, so put the special cases
#  below the general ones.
#
#  A ROW WITH A MISSING SOUND FILE IS NAMED IN THE STARTUP REPORT and then
#  ignored — a typo costs you a line in the Output panel, never a crash.
# =============================================================

const DATA_DIR := "res://data/"
const AUDIO_DIRS: Array[String] = ["res://assets/audio/", "res://assets/sound/",
	"res://assets/music/", "res://assets/"]
const EXTENSIONS: Array[String] = ["", ".ogg", ".wav", ".mp3"]

## The buses a row may name are the rows of data/SoundBuses.csv (round AN).
## Anything else falls back to Master with a note, so a typo is loud in the
## report rather than silent in the game.

static var _instance: AudioDB

var cues: Array[Dictionary] = []
var problems: Array[String] = []

## Rows that are perfectly good but whose sound file is not in the project
## yet: normalised ID -> the file name it is waiting for. Used only to give
## an accurate message when something asks for a cue by name.
var named_but_silent: Dictionary = {}

## Rows whose sound file is not there YET, counted rather than listed.
var _waiting: int = 0


static func _audio_folder_exists() -> bool:
	for folder in AUDIO_DIRS:
		if folder != "res://assets/" and DirAccess.dir_exists_absolute(folder):
			return true
	return false


static func get_db() -> AudioDB:
	if _instance == null:
		_instance = AudioDB.new()
		_instance.load_all()
	return _instance


## RE-READ THE SPREADSHEETS FROM DISK.
##
## NOT CALLED `reload()`. Every class_name in Godot is also a Script object,
## and Script already has a built-in reload() — so `BaseDB.reload()` resolved
## to THAT and printed
##
##     Cannot reload script while instances exist.
##
## while quietly never calling this at all. Naming it reload_files() is the
## whole fix. If you add a loader of your own, avoid reload(), free(),
## duplicate() and get_name() for the same reason.
static func reload_files() -> void:
	_instance = null
	get_db()


# =============================================================
#  LOADING
# =============================================================

func load_all() -> void:
	cues.clear()
	problems.clear()
	_waiting = 0

	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		problems.append("Could not open %s" % DATA_DIR)
		return

	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if file_name.to_lower().ends_with(".csv"):
			_load_csv(DATA_DIR + file_name)

	if _waiting > 0:
		problems.append("%d sound row(s) are ready and waiting, but there is no assets/audio/ folder yet. Make it, drop the files in, and they play with no further changes."
			% _waiting)


func _load_csv(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var rows := CardDatabase.parse_csv(file.get_as_text())
	file.close()
	if rows.size() < 2:
		return

	var columns: Dictionary = {}
	var header: PackedStringArray = rows[0]
	for i in header.size():
		var key := CardDatabase._normalise(header[i])
		if key != "":
			columns[key] = i

	# An audio file is any CSV with both a When and a Sound column. No other
	# file in the project has both, so yours can be called anything.
	if not (columns.has("when") and columns.has("sound")):
		return
	# ROUND AN (10 Oct): AND A BUS. Juice.csv has When and Sound too, so it
	# was read as a sound sheet: its goal_scored row played the OLD
	# crowd_goal.ogg at full volume on every goal, on top of goal_horn and
	# the quieter crowd_goal row - the "cheering is too loud". Juice plays
	# its sounds by name itself (cue_by_name), so it is skipped here.
	if not columns.has("bus"):
		return

	var short_name := path.get_file()
	var buses := GameSettings.bus_names()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var sound := _cell(row, columns, "sound")
		var when_text := _cell(row, columns, "when")
		if sound == "" and when_text == "":
			continue

		var where := "%s row %d" % [short_name, i + 1]
		if sound == "":
			problems.append("%s: '%s' has no Sound file" % [where, when_text])
			continue
		# ============ A BLANK `When` IS FINE, AND MEANS SOMETHING ============
		#
		# It used to be an error: "a Sound with no When, so nothing would ever
		# play it". That stopped being true the moment Juice.csv arrived.
		#
		# A juice row names a sound by the ID of a row in THIS file — see
		# cue_by_name() below — so the row is played on purpose, by name, and
		# has no event of its own. Blank When now reads as "nothing fires this
		# by itself; something asks for it", which is exactly what it is.

		# ROUND AN (10 Oct): SEVERAL NAMES, FIRST ONE THERE WINS.
		# `suno_goal | bav_goal` plays suno_goal once you drop that file in,
		# and bav_goal until then - so a new sound needs no edit here.
		# A last choice of `-` means "or nothing": the row waits quietly for
		# its file instead of being reported as missing.
		var stream: AudioStream = null
		var may_be_silent := false
		for choice in sound.split("|", false):
			if choice.strip_edges() == "-":
				may_be_silent = true
				continue
			stream = _find_sound(choice)
			if stream != null:
				sound = choice.strip_edges()
				break
		if stream == null and may_be_silent:
			var quiet_id := _cell(row, columns, "id")
			if quiet_id != "":
				named_but_silent[CardDatabase._normalise(quiet_id)] = sound
			continue
		if stream == null:
			# THE ROW IS FINE; THE FILE IS NOT THERE YET. Remembered by ID so
			# that anything asking for this cue by name can say which of the
			# two is missing, instead of "there is no row" when there is one.
			var wanted_id := _cell(row, columns, "id")
			if wanted_id != "":
				named_but_silent[CardDatabase._normalise(wanted_id)] = sound
			# BEFORE YOU HAVE ANY AUDIO AT ALL, this would be one complaint per
			# row and would bury the rest of the report. So a missing file is
			# only named individually once the audio folder exists; until then
			# it is counted and reported as a single line at the end.
			if _audio_folder_exists():
				problems.append("%s: cannot find a sound file called '%s'. Looked in %s"
					% [where, sound, ", ".join(AUDIO_DIRS)])
			else:
				_waiting += 1
			continue

		var bus := _cell(row, columns, "bus")
		if bus == "":
			bus = "Master"
		elif not buses.has(bus):
			problems.append("%s: bus '%s' is not one of %s (data/SoundBuses.csv) — using Master"
				% [where, bus, ", ".join(buses)])
			bus = "Master"

		var volume_text := _cell(row, columns, "volume")
		var volume := 0.0
		if volume_text != "":
			if volume_text.is_valid_float():
				volume = float(volume_text)
			else:
				problems.append("%s: Volume '%s' is not a number of decibels"
					% [where, volume_text])

		cues.append({
			"id": _cell(row, columns, "id"),
			"when": CardDatabase._normalise(when_text),
			"match": _cell(row, columns, "match"),
			"sound": sound,
			"stream": stream,
			"bus": bus,
			"loop": _cell(row, columns, "loop").to_lower() in ["true", "yes", "1", "on"],
			"volume": volume,
			"fade": maxf(0.0, float(_cell(row, columns, "fade")) if _cell(row, columns, "fade").is_valid_float() else 0.0),
			"requires": _cell(row, columns, "requires"),
			"where": where,
		})


func _find_sound(file_name: String) -> AudioStream:
	var clean := file_name.strip_edges()
	if clean == "":
		return null
	for folder in AUDIO_DIRS:
		for extension in EXTENSIONS:
			var candidate := folder + clean + extension
			# ROUND AL: READ THE FILE ITSELF WHEN IT IS THERE. Godot only
			# re-imports a changed file when its editor notices, and until
			# then it keeps playing the OLD copy - the "I do not hear the
			# difference" problem. Reading the .ogg / .wav straight from the
			# folder always plays what is in it now. (In an exported game the
			# raw file is not there, and the imported copy below is used.)
			var fresh := _read_raw(candidate)
			if fresh != null:
				return fresh
			if ResourceLoader.exists(candidate):
				var res := load(candidate)
				if res is AudioStream:
					return res as AudioStream
	return null


## One copy per file, shared by every row that names it - so two rows with
## the same Sound really are the same track, and music can carry across
## screens without restarting.
var _raw_cache: Dictionary = {}


func _read_raw(path: String) -> AudioStream:
	if _raw_cache.has(path):
		return _raw_cache[path]
	if not FileAccess.file_exists(path):
		return null
	var stream: AudioStream = null
	match path.get_extension().to_lower():
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			stream = AudioStreamWAV.load_from_file(path)
		"mp3":
			stream = AudioStreamMP3.load_from_file(path)
	if stream != null:
		_raw_cache[path] = stream
	return stream


## ============ ONE SOUND, BY NAME ============
##
## The Juice spreadsheet names a sound and wants it played, with none of the
## "when" matching the rest of this file does. It looks in two places:
##
##   1. a row of Audio.csv with that ID — so the volume, bus and fade you
##      already set there are honoured
##   2. failing that, a FILE of that name in assets/audio/
##
## The second is the useful one while you are working: drop a WAV in, put its
## name in Juice.csv, hear it. Write the Audio.csv row later when you want to
## set its volume.
## Is this a real row that is only silent because the file is missing?
func waiting_for(name_text: String) -> String:
	return String(named_but_silent.get(CardDatabase._normalise(name_text), ""))


func cue_by_name(name_text: String) -> Dictionary:
	var wanted := CardDatabase._normalise(name_text)
	for cue in cues:
		if CardDatabase._normalise(String(cue["id"])) == wanted:
			return cue

	var stream: AudioStream = null
	for choice in name_text.split("|", false):
		stream = _find_sound(choice)
		if stream != null:
			name_text = choice.strip_edges()
			break
	if stream == null:
		return {}
	return {
		"id": name_text, "when": "", "match": "", "sound": name_text,
		"stream": stream, "bus": "Effects", "loop": false,
		"volume": 0.0, "fade": 0.0, "requires": "",
		"where": "assets/audio/%s (no Audio.csv row yet)" % name_text,
	}


# =============================================================
#  CHOOSING WHAT TO PLAY
# =============================================================

## Every row that wants to play at this moment, in file order.
##
## THE LAST MATCH WINS for a looping track on a bus, which is why the order
## of your rows matters: put the general case at the top and the special
## cases below it.
func cues_for(event: String, facts: Dictionary, state: GameState) -> Array[Dictionary]:
	var wanted := CardDatabase._normalise(event)
	var out: Array[Dictionary] = []

	for cue in cues:
		if String(cue["when"]) != wanted:
			continue
		if not StatsRules._passes(String(cue["match"]), facts):
			continue
		if not DialogueGrammar.test(String(cue["requires"]), state):
			continue
		out.append(cue)

	return out


## Every When named by any row, for the startup report to sanity-check.
func events_used() -> Array[String]:
	var out: Array[String] = []
	for cue in cues:
		var name_text := String(cue["when"])
		if not out.has(name_text):
			out.append(name_text)
	return out


func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()
