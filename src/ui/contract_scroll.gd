class_name ContractScroll
extends Control

# =============================================================
#  THE CONTRACT SCROLL  (adventure-look, 10 Oct 2026)
#
#  Anthony: clicking a listing on the board opens a new scroll in an
#  animated window - it UNROLLS - and shows the rewards, the quest text, the
#  requirements and an ACCEPT CONTRACT button. BACK rolls it up again and
#  you are back at the board to look at the other scrolls.
#
#  Nothing here names a job. bounty_board.gd hands over the words, read from
#  Bounties.csv (Name, Kind, Quest Text / Description, Requires, Recommended
#  Power, Reward). The look is Tuning.csv:
#
#    adventure_scroll_art             the scroll picture (PixelLab). Blank or
#                                     missing = a drawn tan paper with rods.
#    adventure_scroll_unroll_seconds  how long the unroll takes
#    adventure_scroll_width           how wide the drawn placeholder is
#    adventure_scroll_height          how tall it is, unrolled
#    adventure_scroll_art_zoom        with art: its whole-pixel zoom (sets the size)
#    adventure_scroll_art_top/_bottom with art: where the rods end, 0-1 down it
#    adventure_scroll_art_side        with art: how far in the words start, 0-1
# =============================================================

signal accepted
signal closed

const PAPER := Color(0.86, 0.76, 0.56)
const PAPER_EDGE := Color(0.42, 0.27, 0.14)
const ROD := Color(0.30, 0.18, 0.09)

var _words: Dictionary = {}
var _can_accept := true
var _clip: Control
var _top_rod: Control
var _bottom_rod: Control
## How far in from each side the words start, as a fraction of the width.
var _paper_side := 0.12
## How much of the paper's bottom is kept clear (the wax seal), 0-1.
var _paper_foot := 0.0
var _full_height := 560.0
var _width := 460.0
var _seconds := 0.45


## Opens a scroll over `parent`. `words` holds: title, kind, quest,
## requirements (Array of String), rewards (Array of String), and `open`
## (false = the requirements are not met, Accept is greyed out).
static func open(parent: Node, words: Dictionary) -> ContractScroll:
	var scroll := ContractScroll.new()
	scroll._words = words
	scroll._can_accept = bool(words.get("open", true))
	parent.add_child(scroll)
	return scroll


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var db := CardDatabase.get_db()
	if db != null:
		_seconds = maxf(0.0, db.tune_float("adventure_scroll_unroll_seconds", 0.45))
		_width = maxf(240.0, db.tune_float("adventure_scroll_width", 460.0))
		_full_height = maxf(240.0, db.tune_float("adventure_scroll_height", 560.0))

	# The board dims behind the scroll, and a click on it does nothing.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var art := MenuSupport.icon_texture(
		db.tune_text("adventure_scroll_art", "") if db != null else "")

	# THE PAPER, behind a clip that grows: that is the unroll.
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)

	var paper: Control
	if art != null:
		# THE PICTURE IN THREE PIECES: the top rod stays put, the paper is
		# revealed, and the bottom rod travels down with the edge of it.
		# Where the rods end is Tuning adventure_scroll_art_top / _bottom
		# (fractions of the picture's height); its size is a whole-pixel
		# zoom, adventure_scroll_art_zoom, so the pixels stay square.
		var zoom := maxf(1.0, roundf(db.tune_float("adventure_scroll_art_zoom", 5.0)))
		var top_cut := clampf(db.tune_float("adventure_scroll_art_top", 0.1), 0.0, 0.5)
		var bottom_cut := clampf(db.tune_float("adventure_scroll_art_bottom", 0.88), 0.5, 1.0)
		var tall := float(art.get_height())
		_width = art.get_width() * zoom
		_full_height = tall * (bottom_cut - top_cut) * zoom
		_paper_side = clampf(db.tune_float("adventure_scroll_art_side", 0.17), 0.0, 0.4)
		_paper_foot = clampf(db.tune_float("adventure_scroll_art_foot", 0.17), 0.0, 0.5)
		_top_rod = _slice(art, 0.0, tall * top_cut, zoom)
		_bottom_rod = _slice(art, tall * bottom_cut, tall, zoom)
		paper = _slice(art, tall * top_cut, tall * bottom_cut, zoom)
	else:
		var sheet := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = PAPER
		style.border_color = PAPER_EDGE
		style.set_border_width_all(3)
		sheet.add_theme_stylebox_override("panel", style)
		paper = sheet
		_top_rod = _rod(26.0)
		_bottom_rod = _rod(26.0)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.size = Vector2(_width, _full_height)
	_clip.add_child(paper)
	paper.add_child(_contents())
	add_child(_top_rod)
	add_child(_bottom_rod)

	_layout(0.0)
	resized.connect(func() -> void: _layout(_clip.size.y / _full_height))
	var tween := create_tween()
	tween.tween_method(_layout, 0.0, 1.0, _seconds) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## One band of the scroll picture, from `from` to `to` (pixels down it),
## drawn at a whole-pixel zoom.
func _slice(art: Texture2D, from: float, to: float, zoom: float) -> TextureRect:
	var region := AtlasTexture.new()
	region.atlas = art
	region.region = Rect2(0.0, from, float(art.get_width()), maxf(1.0, to - from))
	var band := TextureRect.new()
	band.texture = region
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = region.region.size * zoom
	return band


func _rod(height: float) -> Control:
	var rod := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ROD
	style.set_corner_radius_all(int(height * 0.5))
	rod.add_theme_stylebox_override("panel", style)
	rod.custom_minimum_size = Vector2(_width + 36.0, height)
	rod.size = rod.custom_minimum_size
	rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rod


## `open` 0 = rolled up, 1 = fully unrolled. The top stays put; the paper
## and the bottom rod come down together.
func _layout(open: float) -> void:
	var top := (size.y - _full_height) * 0.5
	var left := (size.x - _width) * 0.5
	var high := maxf(0.0, _full_height * open)
	_clip.position = Vector2(left, top)
	_clip.size = Vector2(_width, high)
	if _top_rod != null and _bottom_rod != null:
		var top_left := left + (_width - _top_rod.size.x) * 0.5
		_top_rod.position = Vector2(top_left, top - _top_rod.size.y)
		_bottom_rod.position = Vector2(top_left, top + high)


func _contents() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(_width * _paper_side) + 8)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18 + int(_full_height * _paper_foot))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(page)

	var kind := String(_words.get("kind", ""))
	if kind != "":
		page.add_child(_line(kind.to_upper(), 13, MenuSupport.COLOUR_ACCENT, true))
	page.add_child(_line(String(_words.get("title", "?")), 24, MenuSupport.COLOUR_TEXT, true))

	page.add_child(_line(String(_words.get("quest", "")), 14, MenuSupport.COLOUR_TEXT))

	page.add_child(_line(Loc.text("scroll_requirements", "YOU NEED"), 14, MenuSupport.COLOUR_ACCENT))
	for bit in _words.get("requirements", []):
		page.add_child(_line("•  " + String(bit), 13, MenuSupport.COLOUR_TEXT))

	page.add_child(_line(Loc.text("scroll_rewards", "REWARD"), 14, MenuSupport.COLOUR_ACCENT))
	for bit in _words.get("rewards", []):
		page.add_child(_line("•  " + String(bit), 13, MenuSupport.COLOUR_TEXT))

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(gap)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(buttons)

	var back := MenuSupport.icon_button("back|←", Loc.text("back", "Back"),
		Vector2(130, 46))
	back.name = "ScrollBack"
	back.pressed.connect(close)
	buttons.add_child(back)

	var accept := MenuSupport.icon_button("play|▶",
		Loc.text("accept_contract", "Accept Contract"), Vector2(200, 46))
	accept.name = "AcceptContract"
	accept.disabled = not _can_accept
	accept.pressed.connect(func() -> void: accepted.emit())
	buttons.add_child(accept)
	return margin


func _line(text: String, font_size: int, colour: Color, centred: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	if centred:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# THE ONE RULE FOR WORDS: light words on the see-through black plate
	# (Tuning text_backdrop_alpha), here too. Set by hand because the paper
	# placeholder is a Panel, which TextBackdrop would otherwise skip.
	label.add_theme_stylebox_override("normal", TextBackdrop.plate())
	return label


## Roll it up and go. Escape does the same.
func close() -> void:
	set_process_unhandled_input(false)
	var tween := create_tween()
	tween.tween_method(_layout, 1.0, 0.0, _seconds * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
