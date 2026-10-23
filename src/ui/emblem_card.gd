class_name EmblemCard
extends Control

# =============================================================
#  ONE EMBLEM, ON THE PITCH  (Anthony, 23 Oct 2026)
#
#  "Have both be the same size. They share the same Emblem Template." From
#  his sketch: a wide box, the Emblem's name along the top, a big pentagon in
#  the middle standing on the bottom edge with the Emblem's own symbol in it,
#  and a small circle bottom left (how far along it is).
#
#  The box is a piece of the beer mat card's centre panel, so the Emblems
#  match the player cards. Yours sits top
#  left under the speed buttons, theirs top right under the clock
#  (EmblemBar). Sizes and places are in data/CardFace.csv (emblem_ rows).
#
#  CLICK IT (his ask, 20:17): the first click opens it with its text (the
#  Basic side and what turns it over), the next shows the Ultimate side, the
#  next closes it again. Only the Emblem itself takes the click.
#
#  THE SYMBOL is the Emblem's own picture (the Emblem column of the
#  <Class> Emblems.csv files, looked for in the icon folders). Until it is
#  drawn the pentagon shows the Emblem's first letter.
# =============================================================

## The small circle bottom left, like his sketch: cream, inked edge.
class Ring:
	extends Control
	var ink := Color(0.1, 0.07, 0.04)
	var edge := Color(0.18, 0.36, 0.66)

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		var centre := size / 2.0
		draw_circle(centre, r, Color(0.96, 0.92, 0.8))
		draw_arc(centre, r - 2.0, 0.0, TAU, 40, edge, maxf(2.0, r * 0.18), true)
		draw_arc(centre, r - 2.0, 0.0, TAU, 40, ink, maxf(1.0, r * 0.06), true)


## The pentagon with the symbol in it.
class Pentagon:
	extends Control
	var fill := Color(0.96, 0.92, 0.8)
	var ink := Color(0.1, 0.07, 0.04)
	var edge := Color(0.18, 0.36, 0.66)

	func points() -> PackedVector2Array:
		var out := PackedVector2Array()
		var centre := Vector2(size.x / 2.0, size.y * 0.55)
		var r := minf(size.x / 2.0, size.y / 1.81)
		for i in 5:
			var a := -PI / 2.0 + TAU * float(i) / 5.0
			out.append(centre + Vector2(cos(a), sin(a)) * r)
		return out

	func _draw() -> void:
		var p := points()
		draw_colored_polygon(p, fill)
		var ring := p.duplicate()
		ring.append(p[0])
		var thick := maxf(2.0, size.x * 0.045)
		draw_polyline(ring, edge, thick * 1.8, true)
		draw_polyline(ring, ink, thick * 0.6, true)


## Sent when it is clicked, with the page it now shows (0 shut, 1 the text,
## 2 the Ultimate side), so the bar can keep it open across a refresh.
signal page_changed(page: int)

var basic_text := ""
var ultimate_text := ""
var page := 0
var _sheet: Control = null
## Their Emblem is red (his ask, 23 Oct): the blue of the panel, the
## pentagon's edge and the circle's edge.
var enemy := false
const RED := Color(0.72, 0.12, 0.10)


static func make(title: String, letter: String, art: String, have: int, need: int,
		up: bool, dim: bool, basic: String = "", ultimate: String = "",
		open_page: int = 0, is_enemy: bool = false) -> EmblemCard:
	var card := EmblemCard.new()
	card.enemy = is_enemy
	card.basic_text = basic
	card.ultimate_text = ultimate
	card._build(title, letter, art, have, need, up, dim)
	card._show_page(open_page)
	return card


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		# An Emblem with no Ultimate side (No Emblem) only opens and shuts.
		_show_page((page + 1) % (3 if ultimate_text != "" else 2))
		page_changed.emit(page)
		accept_event()


## The text under the Emblem: nothing, the Basic side, or the Ultimate side.
func _show_page(which: int) -> void:
	page = which
	if _sheet != null and is_instance_valid(_sheet):
		_sheet.queue_free()
	_sheet = null
	var box := _size()
	if page == 0:
		custom_minimum_size = box
		size = box
		return
	var ink := Color.from_string(BeerMatCard.value("ink", "#19110a"), Color(0.1, 0.07, 0.04))
	var words := Label.new()
	words.text = ("BASIC SIDE\n" + basic_text) if page == 1 else ("ULTIMATE SIDE\n" + ultimate_text)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_theme_color_override("font_color", ink)
	words.add_theme_constant_override("outline_size", 0)
	words.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	words.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	words.add_theme_font_size_override("font_size", int(BeerMatCard.number("emblem_text_size", 14.0)))
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Room enough that the words stay clear of the panel's blue corners.
	var pad := box.x * BeerMatCard.number("emblem_text_margin", 0.12)
	words.position = Vector2(pad, pad * 0.8)
	words.size = Vector2(box.x - pad * 2.0, 10)
	var font := ThemeDB.fallback_font
	var text_size := font.get_multiline_string_size(words.text, HORIZONTAL_ALIGNMENT_LEFT,
		words.size.x, words.get_theme_font_size("font_size"))
	var tall := text_size.y * 1.12 + pad * 2.2
	words.size = Vector2(words.size.x, text_size.y * 1.12)
	var sheet := Control.new()
	sheet.position = Vector2(0, box.y - 4.0)
	sheet.size = Vector2(box.x, tall)
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(_dress(_panel(sheet.size)))
	sheet.add_child(words)
	add_child(sheet)
	_sheet = sheet
	custom_minimum_size = Vector2(box.x, box.y - 4.0 + tall)
	size = custom_minimum_size
	_fit_sheet.call_deferred(words, pad)


## Once the words are on screen their real wrapped height is known; grow the
## sheet to hold all of them.
func _fit_sheet(words: Label, pad: float) -> void:
	if _sheet == null or not is_instance_valid(_sheet) or not is_instance_valid(words):
		return
	var text_tall := words.get_minimum_size().y
	words.size = Vector2(words.size.x, text_tall)
	var tall := text_tall + pad * 2.2
	_sheet.size = Vector2(_sheet.size.x, tall)
	for child in _sheet.get_children():
		if child is NinePatchRect:
			var patch := child as NinePatchRect
			patch.size = _sheet.size / patch.scale.x
	var box := _size()
	custom_minimum_size = Vector2(box.x, box.y - 4.0 + tall)
	size = custom_minimum_size


func _build(title: String, letter: String, art: String, have: int, need: int,
		up: bool, dim: bool) -> void:
	var box := _size()
	custom_minimum_size = box
	size = box
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if dim:
		modulate = Color(0.6, 0.6, 0.6, 0.9)
	var ink := Color.from_string(BeerMatCard.value("ink", "#19110a"), Color(0.1, 0.07, 0.04))

	add_child(_dress(_panel(box)))
	var name_area := Rect2(box.x * 0.06, box.y * 0.07, box.x * 0.88, box.y * 0.2)
	BeerMatCard.add_label(self, ("★ " if up else "") + title.to_upper(), name_area, ink, 0.85)

	# The pentagon stands on the bottom edge, in the middle.
	var tall := box.y * BeerMatCard.number("emblem_pentagon", 0.66)
	var penta := Pentagon.new()
	penta.size = Vector2(tall * 1.05, tall)
	penta.position = Vector2((box.x - penta.size.x) / 2.0, box.y - tall - box.y * 0.04)
	penta.ink = ink
	if enemy:
		penta.edge = RED
	if up:
		penta.edge = Color(0.86, 0.64, 0.12)
	penta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(penta)
	var symbol := MenuSupport.icon_texture(art)
	var inner := Rect2(penta.position + penta.size * Vector2(0.14, 0.2), penta.size * Vector2(0.72, 0.7))
	if symbol != null:
		var picture := TextureRect.new()
		picture.texture = symbol
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		picture.position = inner.position
		picture.size = inner.size
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(picture)
	else:
		BeerMatCard.add_label(self, letter, inner, ink, 0.9)

	# Bottom left: the small circle with how far along it is.
	if need > 0:
		var cap_size := box.y * BeerMatCard.number("emblem_cap", 0.3)
		var cap := Ring.new()
		cap.ink = ink
		if enemy:
			cap.edge = RED
		cap.size = Vector2(cap_size, cap_size)
		cap.position = Vector2(box.x * 0.06, box.y - cap_size - box.y * 0.08)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cap)
		BeerMatCard.add_label(self, "%d/%d" % [have, need],
			Rect2(cap.position + cap.size * 0.22, cap.size * 0.56), ink, 0.75)


## Their panel's blue turned red.
func _dress(patch: NinePatchRect) -> NinePatchRect:
	if enemy and ResourceLoader.exists("res://assets/shaders/blue_to_red.gdshader"):
		var paint := ShaderMaterial.new()
		paint.shader = load("res://assets/shaders/blue_to_red.gdshader")
		patch.material = paint
	return patch


static func _size() -> Vector2:
	var parts := BeerMatCard.value("emblem_size", "300,150").split(",")
	if parts.size() == 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return Vector2(300, 150)


## The cream panel with its blue and red edge, cut from the card frame.
static func _panel(box: Vector2) -> NinePatchRect:
	var frame_tex := load(BeerMatCard.value("frame")) as Texture2D
	var patch := NinePatchRect.new()
	patch.texture = frame_tex
	var full := frame_tex.get_size()
	var parts := BeerMatCard.value("sign").split(",")
	if parts.size() == 4:
		patch.region_rect = Rect2(Vector2(float(parts[0]), float(parts[1])) * full,
			Vector2(float(parts[2]), float(parts[3])) * full)
	var edge := int(BeerMatCard.number("tier_window_edge", 34.0))
	patch.patch_margin_left = edge
	patch.patch_margin_right = edge
	patch.patch_margin_top = edge
	patch.patch_margin_bottom = edge
	# Draw it at the frame's own scale so the edge keeps its thickness.
	var shrink := clampf(minf(box.y, 150.0) / patch.region_rect.size.y, 0.05, 1.0)
	patch.size = box / shrink
	patch.scale = Vector2(shrink, shrink)
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return patch
