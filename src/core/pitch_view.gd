class_name PitchView
extends RefCounted

# =============================================================
#  THE TILTED PITCH — data/PitchView.csv  (round AN)
#
#  Anthony: the match is played on the base's own pitch, seen like a drone
#  shot, diagonally, with the base town round it.
#
#  HOW, WITHOUT TOUCHING THE FOOTBALL
#
#  Every rule of the match - where players stand, the zones, the ball's
#  flight, the camera's "whole pitch" - still works on the flat rectangle it
#  always worked on. Only the DRAWING is tilted: the pitch, the zones, the
#  players and the ball live in one CanvasLayer whose transform maps that
#  flat rectangle onto the pitch in the picture (match_ground.png, built by
#  tools/make_match_ground.py from the base's own parts). Menus, cards and
#  the score are in their own layers and stay straight.
#
#  The players themselves are turned back upright (upright()), so a sprite
#  is never skewed - only where it stands is.
#
#  The mapping is worked out from three corners of the white lines: where
#  the top-left, top-right and bottom-left corner of the flat pitch land in
#  the picture. Change those in the CSV and the whole match follows.
# =============================================================

const PATH := "res://data/PitchView.csv"

static var _rows: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = {}
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var header := file.get_csv_line()
	var key_col := header.find("Key")
	var value_col := header.find("Value")
	if key_col < 0 or value_col < 0:
		return
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() <= maxi(key_col, value_col):
			continue
		var key := line[key_col].strip_edges()
		if key != "":
			_rows[key] = line[value_col].strip_edges()


static func value(key: String, fallback: String = "") -> String:
	_load()
	return String(_rows.get(key, fallback))


static func number(key: String, fallback: float) -> float:
	var text := value(key)
	return float(text) if text.is_valid_float() else fallback


static func point(key: String) -> Vector2:
	var parts := value(key).split(",")
	if parts.size() != 2:
		return Vector2.ZERO
	return Vector2(float(parts[0]), float(parts[1]))


static func enabled() -> bool:
	_load()
	return value("enabled", "false").to_lower() == "true" \
		and ResourceLoader.exists(value("background"))


## The white lines of the flat pitch, in match (world) coordinates, worked out
## from the pitch sprite and where the lines sit in its picture.
static func line_rect(pitch_rect: Rect2) -> Rect2:
	var image := point("pitch_image_size")
	var lines := value("lines_in_pitch_image").split(",")
	if image.x < 1.0 or image.y < 1.0 or lines.size() != 4:
		return pitch_rect
	var sx := pitch_rect.size.x / image.x
	var sy := pitch_rect.size.y / image.y
	return Rect2(pitch_rect.position + Vector2(float(lines[0]) * sx, float(lines[1]) * sy),
		Vector2(float(lines[2]) * sx, float(lines[3]) * sy))


## Flat match coordinates -> the picture. Three corners fix an affine map.
static func transform_for(lines: Rect2) -> Transform2D:
	var tl := point("corner_top_left")
	var tr := point("corner_top_right")
	var bl := point("corner_bottom_left")
	if lines.size.x < 1.0 or lines.size.y < 1.0:
		return Transform2D.IDENTITY
	var x_axis := (tr - tl) / lines.size.x
	var y_axis := (bl - tl) / lines.size.y
	var basis := Transform2D(x_axis, y_axis, Vector2.ZERO)
	return Transform2D(x_axis, y_axis, tl - basis * lines.position)


## The undo of the tilt for one sprite: its own position still goes through
## the tilt, but the picture is drawn upright and at its own size.
static func upright(view: Transform2D) -> Transform2D:
	return Transform2D(view.x, view.y, Vector2.ZERO).affine_inverse()


## A rectangle of the flat pitch, tilted, as the box round it in the picture.
static func box_of(view: Transform2D, area: Rect2) -> Rect2:
	var corners := [area.position, Vector2(area.end.x, area.position.y),
		Vector2(area.position.x, area.end.y), area.end]
	var out := Rect2(view * corners[0], Vector2.ZERO)
	for c in corners:
		out = out.expand(view * c)
	return out
