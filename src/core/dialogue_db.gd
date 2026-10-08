class_name DialogueDB
extends RefCounted

# =============================================================
#  DIALOGUE DATABASE — the CSVs ARE the story
#
#  Same deal as CardDatabase: drop a CSV in res://data/, press play, it is
#  in the game. No import step, no editor work, no .tres files.
#
#  HOW A FILE IS RECOGNISED
#    Any CSV in res://data/ whose header row has BOTH a "Node ID" column
#    and a "Text" column is a dialogue file. Name it whatever you like —
#    Dialogue.csv, Chapter1.csv, lorelei_intro.csv.
#
#  COLUMN ORDER DOES NOT MATTER, and neither does case, spacing or
#  underscores: "Node ID", "node_id" and "NODEID" are the same column.
#  Columns you do not need can be left out entirely.
#
#  THE COLUMNS
#    Scene          groups rows into one story. Blank = "main".
#    Node ID        unique within the scene. What Next points at.
#    Speaker        name on the plate. Blank = narration.
#    Portrait       PNG name, found in assets/portraits/
#    Side           left / right / centre
#    Animation      a row in Animations.csv, played on the portrait
#    Mood           which face: happy, sad, drunk, mad ... (StoryArt.csv Mood)
#    View           front = talking to the player (blank), side = to someone
#    Leaves         who walks off as this line shows: Speaker names or Portrait
#                   IDs separated by ; or "all". Everybody else stays on stage
#    Background     PNG name, found in assets/backgrounds/
#    Music          OGG or WAV name, found in assets/music/
#    Sound          a one-off sound as the line shows: an Audio.csv ID
#                   (or a file name in assets/audio/), e.g. bld_pub cheering
#    Text           the line itself
#    Next           Node ID to continue to. Blank falls through to the next
#                   row in the file; write "other_scene/node_id" to jump
#                   into a different scene or a different CSV.
#    Requires       when this line may be used  (see DialogueGrammar)
#    Effects        what showing it changes     (see DialogueGrammar)
#    Choice 1 Text / Choice 1 Next / Choice 1 Requires / Choice 1 Effects
#    ... and the same for Choice 2, 3 and 4.
#
#  EVERY problem is collected and printed once at startup rather than
#  crashing: a Next that points nowhere, a choice with no text, a
#  misspelled condition. The story still runs; the report tells you what
#  to fix.
# =============================================================

## WHICH FOLDER THE CONVERSATIONS COME FROM.
##
## `res://data/` normally. The TUTORIAL BASE points it at
## `res://data/tutorial/` so the tutorial's conversations live beside its own
## buildings and never turn up in the real game. Same arrangement as
## BaseDB.DATA_DIR — see tutorial_base.gd.
static var DATA_DIR := "res://data/"
const MAX_CHOICES := 4
const DEFAULT_SCENE := "main"

static var _instance: DialogueDB

## scene key (lower) -> Array[DialogueLine], in file order.
var scenes: Dictionary = {}
## "scene|node" (lower) -> DialogueLine
var by_id: Dictionary = {}
var problems: Array[String] = []


static func get_db() -> DialogueDB:
	if _instance == null:
		_instance = DialogueDB.new()
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
	scenes.clear()
	by_id.clear()
	problems.clear()

	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		problems.append("Could not open %s" % DATA_DIR)
		_report()
		return

	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if file_name.to_lower().ends_with(".csv"):
			_load_csv(DATA_DIR + file_name)

	_validate()
	_report()


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

	# Not a dialogue file — almost certainly a unit or tuning CSV.
	if not (columns.has("nodeid") and columns.has("text")):
		return

	var short_name := path.get_file()

	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var node_id := _cell(row, columns, "nodeid")
		if node_id == "":
			continue

		var line := DialogueLine.new()
		line.source_file = short_name
		line.source_row = i + 1
		line.id = node_id
		line.scene = _cell(row, columns, "scene")
		if line.scene == "":
			line.scene = DEFAULT_SCENE

		line.speaker = _cell(row, columns, "speaker")
		line.portrait = _cell(row, columns, "portrait")
		line.animation = _cell(row, columns, "animation")
		line.mood = _cell(row, columns, "mood").to_lower()
		line.view = _cell(row, columns, "view").to_lower()
		line.leaves = _cell(row, columns, "leaves")
		line.background = _cell(row, columns, "background")
		line.music = _cell(row, columns, "music")
		line.sound = _cell(row, columns, "sound")
		line.text = _cell(row, columns, "text")
		line.next_id = _cell(row, columns, "next")
		line.requires = _cell(row, columns, "requires")
		line.effects = _cell(row, columns, "effects")

		var side := _cell(row, columns, "side").to_lower()
		line.side = side if side in ["left", "right", "centre", "center"] else "left"
		if line.side == "center":
			line.side = "centre"

		for n in range(1, MAX_CHOICES + 1):
			var choice_text := _cell(row, columns, "choice%dtext" % n)
			var choice_next := _cell(row, columns, "choice%dnext" % n)
			var choice_requires := _cell(row, columns, "choice%drequires" % n)
			var choice_effects := _cell(row, columns, "choice%deffects" % n)

			# A choice with no text but a destination is a spreadsheet slip
			# worth naming; a wholly empty slot is just an unused column.
			if choice_text == "":
				if choice_next != "" or choice_effects != "":
					problems.append("%s: choice %d has a destination but no text"
						% [line.where(), n])
				continue

			var choice := DialogueChoice.new()
			choice.slot = n
			choice.text = choice_text
			choice.next_id = choice_next
			choice.requires = choice_requires
			choice.effects = choice_effects
			line.choices.append(choice)

		_add(line)


func _add(line: DialogueLine) -> void:
	var scene_key := _key(line.scene)
	if not scenes.has(scene_key):
		scenes[scene_key] = []
	(scenes[scene_key] as Array).append(line)

	var id_key := _id_key(line.scene, line.id)
	if by_id.has(id_key):
		var clash := by_id[id_key] as DialogueLine
		# Two rows sharing a Node ID is legal and useful: the first whose
		# Requires passes wins, which is how you write "if they are brave say
		# this, otherwise say that". Only flag it when NEITHER has a Requires,
		# because then the second can never be reached.
		if line.requires.strip_edges() == "" and clash.requires.strip_edges() == "":
			problems.append("%s: duplicate Node ID, and neither has a Requires — the second can never play"
				% line.where())
	else:
		by_id[id_key] = line


# =============================================================
#  VALIDATION
# =============================================================

func _validate() -> void:
	for scene_key in scenes.keys():
		for line: DialogueLine in (scenes[scene_key] as Array):
			for complaint in DialogueGrammar.complaints(line.requires, false):
				problems.append("%s: Requires %s" % [line.where(), complaint])
			for complaint2 in DialogueGrammar.complaints(line.effects, true):
				problems.append("%s: Effects %s" % [line.where(), complaint2])

			if line.next_id != "" and not has_target(line.next_id, line.scene):
				problems.append("%s: Next points at '%s', which does not exist"
					% [line.where(), line.next_id])

			if line.text.strip_edges() == "" and not line.has_choices():
				problems.append("%s: no Text and no choices — nothing to show" % line.where())

			for choice in line.choices:
				for c1 in DialogueGrammar.complaints(choice.requires, false):
					problems.append("%s: choice %d Requires %s"
						% [line.where(), choice.slot, c1])
				for c2 in DialogueGrammar.complaints(choice.effects, true):
					problems.append("%s: choice %d Effects %s"
						% [line.where(), choice.slot, c2])
				if choice.next_id != "" and not has_target(choice.next_id, line.scene):
					problems.append("%s: choice %d goes to '%s', which does not exist"
						% [line.where(), choice.slot, choice.next_id])


# =============================================================
#  QUERIES
# =============================================================

func has_node(scene: String, node_id: String) -> bool:
	return by_id.has(_id_key(scene, node_id))


## A Next or Choice Next destination. Plain "node_id" stays in the scene it was
## written in; "other_scene/node_id" jumps between scenes, which is how a story
## is split across several CSVs or chapters.
func has_target(target: String, from_scene: String) -> bool:
	var parts := split_target(target, from_scene)
	return has_node(parts[0], parts[1])


## The line a destination points at, or null.
func target_line(target: String, from_scene: String, state: GameState) -> DialogueLine:
	var parts := split_target(target, from_scene)
	return line_for(parts[0], parts[1], state)


## Splits "scene/node" into its two halves. A bare "node" keeps `default_scene`.
static func split_target(target: String, default_scene: String) -> PackedStringArray:
	var at := target.find("/")
	if at > 0:
		return PackedStringArray([
			target.substr(0, at).strip_edges(),
			target.substr(at + 1).strip_edges()])
	return PackedStringArray([default_scene, target.strip_edges()])


## The line to play for this ID, honouring Requires: several rows may share an
## ID, and the first whose condition passes is the one you get.
func line_for(scene: String, node_id: String, state: GameState) -> DialogueLine:
	var scene_key := _key(scene)
	if not scenes.has(scene_key):
		return null

	var wanted := _key(node_id)
	var fallback: DialogueLine = null
	for line: DialogueLine in (scenes[scene_key] as Array):
		if _key(line.id) != wanted:
			continue
		if line.is_available(state):
			return line
		if fallback == null:
			fallback = line

	# Every version was gated out. Returning null would strand the story, so
	# hand back the first one and let the report explain why.
	return fallback


## The line a scene opens on: its first row whose Requires passes.
func opening_line(scene: String, state: GameState) -> DialogueLine:
	var scene_key := _key(scene)
	if not scenes.has(scene_key):
		return null
	for line: DialogueLine in (scenes[scene_key] as Array):
		if line.is_available(state):
			return line
	return null


## Whatever comes after `line` when it has no Next and no choices: the next row
## in the file. That is what lets you write a scene as a plain top-to-bottom
## list and never fill in the Next column at all.
func line_after(line: DialogueLine, state: GameState) -> DialogueLine:
	if line == null:
		return null
	var scene_key := _key(line.scene)
	if not scenes.has(scene_key):
		return null

	var rows: Array = scenes[scene_key]
	var at := rows.find(line)
	if at < 0:
		return null
	for i in range(at + 1, rows.size()):
		var candidate := rows[i] as DialogueLine
		if candidate.is_available(state):
			return candidate
	return null


func scene_names() -> Array[String]:
	var out: Array[String] = []
	for scene_key in scenes.keys():
		var rows: Array = scenes[scene_key]
		if not rows.is_empty():
			out.append((rows[0] as DialogueLine).scene)
	out.sort()
	return out


func line_count() -> int:
	var total := 0
	for scene_key in scenes.keys():
		total += (scenes[scene_key] as Array).size()
	return total


# =============================================================
#  HELPERS
# =============================================================

static func _key(text: String) -> String:
	return CardDatabase._normalise(text)


static func _id_key(scene: String, node_id: String) -> String:
	return "%s|%s" % [_key(scene), _key(node_id)]


func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()


func _report() -> void:
	print("[Story] %d line(s) across %d scene(s): %s"
		% [line_count(), scenes.size(), ", ".join(scene_names())])
	if problems.is_empty():
		return
	print("[Story] %d thing(s) need attention in your dialogue CSVs:" % problems.size())
	for line in problems:
		print("        - ", line)
