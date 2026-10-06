class_name StoryArt
extends RefCounted

# =============================================================
#  THE STORY SCREEN'S PICTURES — data/StoryArt.csv
#
#  One row per picture the conversations use: the faces that stand beside
#  the text box, and the rooms behind them. Dialogue.csv names a row by its
#  ID (its Portrait and Background columns), so swapping a face or a room
#  for every line at once is ONE cell here.
#
#  THE COLUMNS
#    ID        the name Dialogue.csv uses
#    Kind      portrait  or  background
#    Speaker   portraits only: a line with this Speaker and an EMPTY
#              Portrait cell gets this face. So you never have to type the
#              portrait on every line.
#    Image     the PNG, as a res:// path
#    Mood      portraits only: happy, sad, drunk, mad ... any word. Blank =
#              the everyday face. A Dialogue line picks one in its Mood column.
#    View      portraits only: front (looking at the player) or side (talking
#              to someone else in the scene). A Dialogue line picks one in its
#              View column; blank there means front.
#    Faces     side views: which way the drawing looks, left or right.
#              The game mirrors it when the character stands on the other
#              side, so everybody looks into the room. A front view is never
#              mirrored.
#    Front     backgrounds only: yes = drawn IN FRONT of the characters
#              (a table edge, a beer mug at the bottom of the screen)
#    Notes     for you
#
#  A BACKGROUND IN LAYERS: give several rows the same ID. They are stacked
#  in file order, the first row at the back.
#
#  ONE CHARACTER, MANY FACES: give several portrait rows the same ID, one
#  per Mood and View. When the exact face is missing the game picks the
#  nearest: the same mood from the other side, then the everyday face in
#  the asked view, then any face of that character.
#
#  A Portrait or Background that is not an ID here still works the old way:
#  a PNG name looked for in assets/portraits/ or assets/backgrounds/.
# =============================================================

const PATH := "res://data/StoryArt.csv"

static var _instance: StoryArt

## id (normalised) -> Array of {"image", "faces", "mood", "view"}
var portraits: Dictionary = {}
## speaker (normalised) -> portrait id
var by_speaker: Dictionary = {}
## id (normalised) -> Array of {"image": String, "front": bool}
var backgrounds: Dictionary = {}


static func get_db() -> StoryArt:
	if _instance == null:
		_instance = StoryArt.new()
		_instance.load_file(PATH)
	return _instance


static func reload_files() -> void:
	_instance = null
	get_db()


func load_file(path: String) -> void:
	portraits.clear()
	by_speaker.clear()
	backgrounds.clear()
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
		columns[CardDatabase._normalise(header[i])] = i
	for i in range(1, rows.size()):
		var row: PackedStringArray = rows[i]
		var id := _cell(row, columns, "id")
		var image := _cell(row, columns, "image")
		if id == "" or image == "":
			continue
		var key := CardDatabase._normalise(id)
		var kind := _cell(row, columns, "kind").to_lower()
		if kind == "background":
			if not backgrounds.has(key):
				backgrounds[key] = []
			backgrounds[key].append({
				"image": image,
				"front": _cell(row, columns, "front").to_lower() in ["yes", "true", "1"],
			})
		else:
			var faces := _cell(row, columns, "faces").to_lower()
			var view := _cell(row, columns, "view").to_lower()
			if not portraits.has(key):
				portraits[key] = []
			portraits[key].append({
				"image": image,
				"faces": "left" if faces == "left" else "right",
				"mood": _cell(row, columns, "mood").to_lower(),
				"view": "front" if view == "front" else "side",
			})
			var speaker := _cell(row, columns, "speaker")
			if speaker != "":
				by_speaker[CardDatabase._normalise(speaker)] = key


## The portrait row for a line: its Portrait cell, or else its Speaker, in
## the asked Mood and View (blank view = front). Empty when neither names a
## row here.
func portrait_for(portrait: String, speaker: String, mood: String = "",
		view: String = "") -> Dictionary:
	var id := CardDatabase._normalise(portrait)
	if portrait.strip_edges() == "":
		id = by_speaker.get(CardDatabase._normalise(speaker), "")
	var faces: Array = portraits.get(id, [])
	if faces.is_empty():
		return {}
	var want_view := "side" if view.strip_edges().to_lower() == "side" else "front"
	var want_mood := mood.strip_edges().to_lower()
	for test in [
			func(f): return f["mood"] == want_mood and f["view"] == want_view,
			func(f): return f["mood"] == want_mood,
			func(f): return f["mood"] == "" and f["view"] == want_view,
			func(f): return f["view"] == want_view,
			func(f): return f["mood"] == ""]:
		for face in faces:
			if test.call(face):
				return face
	return faces[0]


## The layers of a background, back to front. Empty when the ID is not here.
func background_layers(id: String) -> Array:
	return backgrounds.get(CardDatabase._normalise(id), [])


func _cell(row: PackedStringArray, columns: Dictionary, key: String) -> String:
	if not columns.has(key):
		return ""
	var index: int = columns[key]
	if index >= row.size():
		return ""
	return row[index].strip_edges()
