class_name SignHeader
extends Control

# =============================================================
#  THE MENU HEADER - data/MenuHeader.csv
#
#  The hanging tavern sign at the top of a menu screen, with the screen's
#  name written on it in the game's heading font (20 Oct 2026, Anthony).
#  Three drawn pieces: left (wall plate, left chain), middle (plain bar and
#  board) and right (right chain, board end, bar tip). Only the middle
#  stretches, so a longer name or another language makes the sign wider
#  instead of needing new art.
# =============================================================

const SHEET := "res://data/MenuHeader.csv"
const Look := preload("res://src/ui/screen_look.gd")

var _pieces: Dictionary = {}
var _paths: Dictionary = {}
var _left := 0.0
var _top := 8.0
var _height := 170.0
var _text_start := 108.0
var _text_end := 490.0
var _text_middle := 365.0
var _gap := 40.0
var _text_size := 46
var _text_colour := Color("f6ead0")
var _label: Label
var _outline := 10
var _outline_colour := Color("2a1608")
var _rects: Array[TextureRect] = []
var _backing_reach := 60.0
var _backing_colour := Color(0, 0, 0, 0.63)
## The dark aura behind the sign: one soft shadow picture per piece
## (sign_<part>_aura.png, made by art_tool/menu/header_aura.py), padded by
## _backing_reach pixels of the drawing on the piece's outer sides.
var _auras: Array[TextureRect] = []
## The comic font is a picture font with no outline of its own, so the ink
## edge is the same words drawn dark, nudged out in eight directions.
var _edges: Array[Label] = []


## A header for the screen, with this text on the board. `sheet` picks
## another set of pieces: data/MenuHeaderBoard.csv is the board alone, with
## no iron bar and no chains (Anthony 23 Oct 2026, for the inventory).
static func make(words: String, sheet: String = SHEET) -> SignHeader:
	var sign := SignHeader.new()
	sign.name = "SignHeader"
	sign._read(sheet)
	sign._build(words)
	return sign


func _read(sheet: String = SHEET) -> void:
	for row in MenuSupport.read_csv(sheet):
		var part := MenuSupport.field(row, "Part").strip_edges().to_lower()
		match part:
			"left", "middle", "right":
				_paths[part] = MenuSupport.field(row, "Image").strip_edges()
				_pieces[part] = Look.picture(_paths[part])
			"sign":
				_left = MenuSupport.field_float(row, "X", _left)
				_top = MenuSupport.field_float(row, "Y", _top)
				_height = MenuSupport.field_float(row, "Size", _height)
			"text":
				_text_start = MenuSupport.field_float(row, "X", _text_start)
				_text_middle = MenuSupport.field_float(row, "Y", _text_middle)
				_text_size = int(MenuSupport.field_float(row, "Size", _text_size))
				var colour := MenuSupport.field(row, "Colour").strip_edges()
				if colour != "":
					_text_colour = Color(colour)
			"outline":
				_outline = int(MenuSupport.field_float(row, "Size", _outline))
				var edge := MenuSupport.field(row, "Colour").strip_edges()
				if edge != "":
					_outline_colour = Color(edge)
			"backing":
				_backing_reach = MenuSupport.field_float(row, "Size", _backing_reach)
				var shade := MenuSupport.field(row, "Colour").strip_edges()
				if shade != "":
					_backing_colour = Color(shade)
			"padding":
				_text_end = MenuSupport.field_float(row, "X", _text_end)
				_gap = MenuSupport.field_float(row, "Y", _gap)


func _build(words: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left: Texture2D = _pieces.get("left")
	var middle: Texture2D = _pieces.get("middle")
	var right: Texture2D = _pieces.get("right")
	if left == null or middle == null or right == null:
		# No pictures: still show the name.
		add_child(MenuSupport.heading(words, _text_size, _text_colour))
		position = Vector2(_left + 40.0, _top)
		return
	var label := Label.new()
	label.text = words
	label.add_theme_font_size_override("font_size", _text_size)
	label.add_theme_color_override("font_color", _text_colour)
	var face := ThemeBook.font(String(ThemeBook.row_for("heading").get("font", "")))
	if face != null:
		label.add_theme_font_override("font", face)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_meta(TextScale.FITTED_META, true)
	# The board is the backing: no see-through plate behind these words.
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = label
	if _backing_colour.a > 0.0:
		# Anthony 20 Oct 2026: not a box, an aura hugging the board and bar.
		for part in ["left", "middle", "right"]:
			var aura_path := String(_paths.get(part, "")).get_basename() + "_aura.png"
			var aura_texture := Look.picture(aura_path)
			if aura_texture == null:
				continue
			var aura := TextureRect.new()
			aura.texture = aura_texture
			aura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			aura.stretch_mode = TextureRect.STRETCH_SCALE
			aura.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			aura.modulate = _backing_colour
			aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
			aura.set_meta("part", part)
			add_child(aura)
			_auras.append(aura)
	for texture in [left, middle, right]:
		var piece := TextureRect.new()
		piece.texture = texture
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.stretch_mode = TextureRect.STRETCH_SCALE
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(piece)
		_rects.append(piece)
	if _outline > 0:
		for i in range(8):
			var edge := label.duplicate() as Label
			edge.add_theme_color_override("font_color", _outline_colour)
			add_child(edge)
			_edges.append(edge)
	add_child(label)
	position = Vector2(_left, _top)
	_layout()
	# The game may make every word bigger (text size setting) once the
	# label is on screen: measure again then.
	label.minimum_size_changed.connect(_layout)
	ready.connect(_layout, CONNECT_DEFERRED)


## A smaller, lighter dark aura for one screen: `reach` scales how far it
## spreads past the sign (1 = as MenuHeader.csv says), `strength` how dark.
func soften(reach: float, strength: float) -> void:
	_backing_reach *= clampf(reach, 0.0, 1.0)
	_backing_colour.a *= clampf(strength, 0.0, 1.0)
	for aura in _auras:
		aura.modulate = _backing_colour
	_layout()


## Size the pieces so the words fit, with _gap at both ends of the board.
func _layout() -> void:
	if _label == null or _rects.size() < 3:
		return
	var left: Texture2D = _pieces["left"]
	var right: Texture2D = _pieces["right"]
	var scale_by := _height / float(left.get_height())
	var words_width := _label.get_minimum_size().x
	# How wide the middle must be (in pixels of the drawing) for the words
	# to fit between the ends of the board's writing space.
	var fixed := (left.get_width() - _text_start) + _text_end
	var middle_width := maxf((words_width / scale_by) + 2.0 * _gap - fixed, 40.0)
	var widths := [float(left.get_width()), middle_width, float(right.get_width())]
	var x := 0.0
	for i in range(3):
		var piece: TextureRect = _rects[i]
		piece.position = Vector2(x * scale_by, 0)
		# One pixel of overlap, so no see-through hairline shows at a seam.
		piece.size = Vector2(float(widths[i]) * scale_by + (1.0 if i < 2 else 0.0), _height)
		x += float(widths[i])
	var start := _text_start * scale_by
	var finish := (left.get_width() + middle_width + _text_end) * scale_by
	_label.position = Vector2(start, _text_middle * scale_by - _label.get_minimum_size().y * 0.5)
	_label.size = Vector2(finish - start, _label.get_minimum_size().y)
	var nudge := float(_outline) * 0.5
	for i in range(_edges.size()):
		var turn := TAU * float(i) / float(_edges.size())
		_edges[i].position = _label.position + Vector2(cos(turn), sin(turn)) * nudge
		_edges[i].size = _label.size
	size = Vector2(x * scale_by, _height)
	# Each aura is its piece grown by the reach on its outer sides only.
	var reach := _backing_reach * scale_by
	for aura in _auras:
		var i := ["left", "middle", "right"].find(String(aura.get_meta("part")))
		var piece: TextureRect = _rects[i]
		var grow_left := reach if i == 0 else 0.0
		var grow_right := reach if i == 2 else 0.0
		aura.position = piece.position - Vector2(grow_left, reach)
		aura.size = piece.size + Vector2(grow_left + grow_right, reach * 2.0)
