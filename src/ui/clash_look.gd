class_name ClashLook
extends RefCounted

# =============================================================
#  THE FREE KICK NUMBER GAME'S LOOK  (Anthony, 24 Oct 2026)
#
#  "I like the wheel!" The number call (coin_clash.gd) as a fairground
#  booth: a striped awning with the title on its sign, two candy-striped
#  posts, a wheel of fortune that spins and stops under the red flap, and
#  raffle tickets for the numbers and for ATTACK / DEFEND. No line of
#  instructions at the bottom.
#
#  Everything is in data/ClashLook.csv; style old brings the dark window
#  back. The pieces are drawn by tools/art/clash_wheel_pieces.py. The game
#  itself is not touched - this only changes how it looks.
# =============================================================

const PATH := "res://data/ClashLook.csv"

static var _rows: Dictionary = {}
static var _loaded := false


static func value(key: String, fallback: String = "") -> String:
	if not _loaded:
		_loaded = true
		for row in MenuSupport.read_csv(PATH):
			_rows[MenuSupport.field(row, "Key").strip_edges().to_lower()] = MenuSupport.field(row, "Value").strip_edges()
	var found := String(_rows.get(key, ""))
	return found if found != "" else fallback


static func number(key: String, fallback: float) -> float:
	var text := value(key)
	return float(text) if text.is_valid_float() else fallback


static func pair(key: String, fallback: Vector2) -> Vector2:
	var parts := value(key).split(",")
	if parts.size() == 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return fallback


static func colour(key: String, fallback: Color) -> Color:
	return Color.from_string(value(key), fallback)


## The wheel is drawn for one count of numbers; any other coin_faces gets the
## old window rather than a wheel with the wrong wedges.
static func enabled(faces: int) -> bool:
	return value("style", "wheel").to_lower() == "wheel" and faces == int(number("faces", 10))


static func picture(key: String) -> Texture2D:
	var path := value(key)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## A ticket (or any picture) as a button face, the whole picture stretched
## over the button. `tint` is multiplied in (hover).
static func face(key: String, tint: Color = Color.WHITE) -> StyleBox:
	var tex := picture(key)
	if tex == null:
		return StyleBoxEmpty.new()
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.modulate_color = tint
	return style


## The biggest font size (up to `biggest`) at which `text` fits in `box`.
static func fit_size(font: Font, text: String, box: Vector2, biggest: int, smallest: int = 10) -> int:
	if font == null:
		return biggest
	var size := biggest
	while size > smallest:
		var need := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
		if need.x <= box.x and need.y <= box.y:
			break
		size -= 2
	return size
