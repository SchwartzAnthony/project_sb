class_name ProgressRow
extends HBoxContainer

# =============================================================
#  A PROGRESS BAR — fills up, and shines when it is finished
#
#  Used by the post-match screen and by the unlock board. It is one file so
#  that restyling the bars restyles them everywhere.
#
#      +------+  Master Brewer                    3 of 5
#      | icon |  [==================>            ]
#      +------+  Brews drunk: 3 of 5
#
#  Nothing in here decides ANYTHING. It is handed a name, a fraction, a line
#  of text and whether it is done. All of that comes from unlock_progress.gd.
#
#  ============ THE ICON ============
#
#  A small square on the left. The picture comes from the Art column of
#  whichever CSV the row came from — Buildings.csv, Talents.csv, Brews.csv
#  all already have one — so giving a thing an icon is typing a file name in
#  a spreadsheet, not editing this file.
#
#  WITH NO ART IT DRAWS A PLACEHOLDER: a coloured square with the first
#  letter of what the row is (B for Building, T for Talent). The layout is
#  therefore right from the first run, and every icon you draw simply
#  replaces a placeholder. Same idea as the keeper on the pitch.
#
#  The row is an HBoxContainer holding [icon][a VBox of everything else].
#  It used to be the VBox itself; callers only ever add_child() it and call
#  setup(), so nothing else had to change.
#
#  THE SHINE
#    A finished bar pulses gently rather than sitting still, because a
#    static full bar and a static nearly-full bar look the same at a glance.
#    It is a sine wave on the fill colour, and it costs nothing: a row that
#    is not shining turns its own _process off.
# =============================================================

const BAR_HEIGHT := 12.0
const CORNER := 4.0

## The square on the left. Change it here and every screen agrees.
const ICON_SIZE := 44.0
const ICON_GAP := 12.0

var fraction: float = 0.0
var shining: bool = false

var _bar: Control
var _clock: float = 0.0

var _fill_colour := MenuSupport.COLOUR_ACCENT
var _track_colour := Color(0.10, 0.11, 0.14, 1.0)

## The placeholder's letter and tint, used only when there is no artwork.
var _icon_letter: String = ""
var _icon_tint := MenuSupport.COLOUR_SLOT_EMPTY


## `value` is 0 to 1. `note` is the line under the bar — what is missing, or
## what you got. `right` is the small number on the right of the title.
##
## `icon` and `kind` are optional, so every existing call still works:
##   icon  a Texture2D, or null to draw the placeholder
##   kind  "Building", "Talent", "Brew"... it colours the placeholder and
##         provides its letter. Pass "" to leave the square blank.
func setup(title: String, value: float, right: String, note: String,
		is_done: bool, icon: Texture2D = null, kind: String = "") -> void:
	fraction = clampf(value, 0.0, 1.0)
	shining = is_done
	add_theme_constant_override("separation", ICON_GAP)
	alignment = BoxContainer.ALIGNMENT_BEGIN

	add_child(_build_icon(icon, kind, is_done))

	# Everything that used to be this node is now this inner column.
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 3)
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)

	var name_label := Label.new()
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color",
		MenuSupport.COLOUR_ACCENT if is_done else MenuSupport.COLOUR_TEXT)
	head.add_child(name_label)

	if right != "":
		var value_label := Label.new()
		value_label.text = right
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 14)
		value_label.add_theme_color_override("font_color",
			MenuSupport.COLOUR_ACCENT if is_done else MenuSupport.COLOUR_TEXT_DIM)
		head.add_child(value_label)

	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	column.add_child(_bar)

	if note != "":
		var note_label := Label.new()
		note_label.text = note
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.add_theme_font_size_override("font_size", 13)
		note_label.add_theme_color_override("font_color", MenuSupport.COLOUR_TEXT_DIM)
		column.add_child(note_label)

	# A bar that will never change does not need a frame-by-frame update.
	set_process(shining)


# =============================================================
#  THE ICON
# =============================================================

## The square on the left: the artwork if there is any, a labelled
## placeholder if there is not. Always the same size either way, so the
## rows line up whether or not the art exists yet.
func _build_icon(icon: Texture2D, kind: String, is_done: bool) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# A finished row gets the accent border, matching its title and its bar.
	holder.add_theme_stylebox_override("panel", MenuSupport.panel_style(
		MenuSupport.COLOUR_PANEL,
		MenuSupport.COLOUR_ACCENT if is_done else MenuSupport.COLOUR_TEXT_DIM))

	if icon != null:
		var rect := TextureRect.new()
		rect.texture = icon
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# An unearned thing is shown dimmed rather than hidden, so you can
		# see what you are working towards.
		rect.modulate = Color(1, 1, 1, 1.0 if is_done else 0.55)
		holder.add_child(rect)
		return holder

	# --- No artwork yet: the placeholder ---
	_icon_letter = kind.strip_edges().substr(0, 1).to_upper()
	_icon_tint = _tint_for(kind)

	var drawn := Control.new()
	drawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawn.draw.connect(_draw_placeholder.bind(drawn, is_done))
	holder.add_child(drawn)
	return holder


func _draw_placeholder(on: Control, is_done: bool) -> void:
	var box := Rect2(Vector2.ZERO, on.size)
	if box.size.x < 4.0 or box.size.y < 4.0:
		return

	var tint := _icon_tint if is_done else _icon_tint.darkened(0.35)
	on.draw_rect(box.grow(-4.0), tint, true)

	if _icon_letter == "":
		return
	var font := ThemeDB.fallback_font
	var size := int(box.size.y * 0.5)
	var width := font.get_string_size(_icon_letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	on.draw_string(font,
		Vector2((box.size.x - width) * 0.5, box.size.y * 0.5 + size * 0.36),
		_icon_letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size,
		MenuSupport.COLOUR_TEXT if is_done else MenuSupport.COLOUR_TEXT_DIM)


## One colour per kind of thing, so the board reads at a glance even before
## any art exists. An unknown kind gets the neutral slot colour.
static func _tint_for(kind: String) -> Color:
	match kind.strip_edges().to_lower():
		"building":
			return Color(0.32, 0.26, 0.18)
		"talent":
			return Color(0.20, 0.28, 0.34)
		"brew":
			return Color(0.30, 0.20, 0.30)
		"fixture":
			return Color(0.20, 0.30, 0.22)
		_:
			return MenuSupport.COLOUR_SLOT_EMPTY


func _process(delta: float) -> void:
	_clock += delta
	if _bar != null:
		_bar.queue_redraw()


func _draw_bar() -> void:
	if _bar == null:
		return
	var box := Rect2(Vector2.ZERO, _bar.size)
	if box.size.x < 2.0:
		return

	_bar.draw_rect(box, _track_colour, true)

	var filled := box
	filled.size.x = box.size.x * fraction
	if filled.size.x < 1.0:
		return

	var colour := _fill_colour
	if shining:
		# 0.78 to 1.0 and back, about three times a second. Enough to read as
		# "this one is finished" without being a distraction.
		var pulse := 0.89 + 0.11 * sin(_clock * 6.0)
		colour = Color(_fill_colour.r * pulse + (1.0 - pulse),
			_fill_colour.g * pulse + (1.0 - pulse) * 0.95,
			_fill_colour.b * pulse + (1.0 - pulse) * 0.75, 1.0)
	_bar.draw_rect(filled, colour, true)

	# A brighter cap on the leading edge, so a part-filled bar has an end to
	# it rather than fading into the track.
	if fraction < 0.999:
		var cap := Rect2(Vector2(filled.size.x - 2.0, 0.0), Vector2(2.0, box.size.y))
		_bar.draw_rect(cap, colour.lightened(0.35), true)
