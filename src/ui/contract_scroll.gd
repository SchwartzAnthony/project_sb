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
#    adventure_scroll_width           how wide the scroll is, in pixels
#    adventure_scroll_height          how tall it is, unrolled
# =============================================================

signal accepted
signal closed

const PAPER := Color(0.86, 0.76, 0.56)
const PAPER_EDGE := Color(0.42, 0.27, 0.14)
const ROD := Color(0.30, 0.18, 0.09)

var _words: Dictionary = {}
var _can_accept := true
var _clip: Control
var _bottom_rod: Control
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
	var rod_h := 26.0

	# THE PAPER, behind a clip that grows: that is the unroll.
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)

	var paper: Control
	if art != null:
		var picture := TextureRect.new()
		picture.texture = art
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		paper = picture
		rod_h = 0.0
	else:
		var sheet := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = PAPER
		style.border_color = PAPER_EDGE
		style.set_border_width_all(3)
		sheet.add_theme_stylebox_override("panel", style)
		paper = sheet
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.size = Vector2(_width, _full_height)
	_clip.add_child(paper)
	paper.add_child(_contents())

	# The two rods of the placeholder. The art has its own.
	if rod_h > 0.0:
		add_child(_rod(rod_h))
		_bottom_rod = _rod(rod_h)
		add_child(_bottom_rod)

	_layout(0.0)
	resized.connect(func() -> void: _layout(_clip.size.y / _full_height))
	var tween := create_tween()
	tween.tween_method(_layout, 0.0, 1.0, _seconds) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	var rods := get_children().filter(func(c): return c is Panel and c != _clip)
	if rods.size() >= 2:
		var rod_top: Control = rods[0]
		rod_top.position = Vector2(left - 18.0, top - rod_top.size.y * 0.5)
		_bottom_rod.position = Vector2(left - 18.0, top + high - _bottom_rod.size.y * 0.5)


func _contents() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(_width * 0.12))
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 30)
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
		Vector2(150, 48))
	back.name = "ScrollBack"
	back.pressed.connect(close)
	buttons.add_child(back)

	var accept := MenuSupport.icon_button("play|▶",
		Loc.text("accept_contract", "Accept Contract"), Vector2(220, 48))
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
