class_name StadiumBook
extends RefCounted

# =============================================================
#  WHAT THE PITCH IS MADE OF — data/Stadium.csv
#
#  ============ THE QUESTION THIS ANSWERS ============
#
#  "I need to know how big to draw the field, because I also want to draw the
#  stadium in the background — give me the size for both."
#
#      the pitch        2400 x 1560   assets/field/soccerfield.png
#      the background   3840 x 2160   assets/field/stadium_back.png
#
#  And those two numbers are ROWS, not constants, so if you draw something a
#  different shape you change the row rather than asking me.
#
#  ============ WHY IT HAD TO BECOME A SPREADSHEET ============
#
#  The pitch used to be a sprite placed by hand in main_scene.tscn: a 1000 x
#  667 photograph at position (956, 534) with a scale of 2.216 by 2.114. Two
#  different scale factors, so the image was slightly squashed, and no answer
#  at all to "what size should I draw it". Everything in the match — the four
#  Tier quarters, both goal mouths, where a throw-in stands — is laid out
#  against that rectangle, so its size is a design number and design numbers
#  live in CSVs.
#
#  ============ THE LAYERS ============
#
#      background   behind the grass. Parallax: drifts slower than the camera
#      crowd        between background and grass. For later unlocks
#      pitch        THE PLAYING SURFACE. Everything is measured against it
#      lights       over the top of everything. Tinted, for floodlights
#
#  A row with no Image draws nothing, which is how three of the four start.
#  A row whose `Requires` fails is not drawn either — the same condition
#  language as the rest of the game, so the Stadium screen can unlock a
#  layer without a line of code here.
#
#  ============ WHAT USES IT ============
#
#  main_scene asks for `pitch_size()` when it lays the match out, and
#  `layers()` when it builds the scenery. Nothing else needs to know.
# =============================================================

const FILE := "res://data/Stadium.csv"
## Used when there is no file at all, so a missing spreadsheet cannot leave
## the match with a pitch of no size.
const PITCH_FALLBACK := Vector2(2400.0, 1560.0)

static var _rows: Array[Dictionary] = []
static var _loaded := false


static func forget() -> void:
	_rows = []
	_loaded = false


## Every layer, in the order they are drawn — back to front, as written.
static func layers() -> Array[Dictionary]:
	if _loaded:
		return _rows
	_loaded = true
	_rows = []
	for row in MenuSupport.read_csv(FILE):
		var layer_name := MenuSupport.field(row, "Layer").strip_edges()
		if layer_name == "":
			continue
		_rows.append({
			"layer": layer_name.to_lower(),
			"image": MenuSupport.field(row, "Image").strip_edges(),
			"size": Vector2(
				MenuSupport.field_float(row, "Width", 0.0),
				MenuSupport.field_float(row, "Height", 0.0)),
			"offset": Vector2(
				MenuSupport.field_float(row, "Offset X", 0.0),
				MenuSupport.field_float(row, "Offset Y", 0.0)),
			"parallax": MenuSupport.field_float(row, "Parallax", 0.0),
			"tint": MenuSupport.field(row, "Tint").strip_edges(),
			"requires": MenuSupport.field(row, "Requires").strip_edges(),
		})
	if _rows.is_empty():
		print("[stadium] No Stadium.csv — the pitch falls back to %d x %d."
			% [int(PITCH_FALLBACK.x), int(PITCH_FALLBACK.y)])
	else:
		print("[stadium] %d layer(s) from Stadium.csv. Pitch is %d x %d."
			% [_rows.size(), int(pitch_size().x), int(pitch_size().y)])
	return _rows


static func row_for(layer_name: String) -> Dictionary:
	for row in layers():
		if String(row["layer"]) == layer_name.to_lower():
			return row
	return {}


## THE RECTANGLE EVERYTHING IS MEASURED AGAINST. A pitch row with a missing
## or nonsense size falls back rather than handing the match a pitch of zero
## width, which would put every player on one pixel.
static func pitch_size() -> Vector2:
	var row := row_for("pitch")
	var wanted: Vector2 = row.get("size", Vector2.ZERO)
	if wanted.x < 200.0 or wanted.y < 200.0:
		return PITCH_FALLBACK
	return wanted


## Should this layer be drawn at all? A blank `Requires` is always yes.
static func allowed(row: Dictionary, state: GameState) -> bool:
	var needs := String(row.get("requires", "")).strip_edges()
	if needs == "" or state == null:
		return needs == ""
	return DialogueGrammar.test(needs, state)


## The colour a layer is multiplied by. Blank is white, which changes nothing.
static func tint_of(row: Dictionary) -> Color:
	var text := String(row.get("tint", "")).strip_edges()
	if text == "":
		return Color.WHITE
	if not text.begins_with("#"):
		text = "#" + text
	return Color.html(text) if Color.html_is_valid(text) else Color.WHITE
